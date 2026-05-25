#!/usr/bin/env bash
# hackmd-curl.sh — Bash fallback CLI for HackMD API
# Usage: source this file, then call hackmd_* functions.
#        Or run directly: ./hackmd-curl.sh <command> [args...]
# Requires: curl, python3 (for JSON escaping), HACKMD_API_TOKEN env var

set -euo pipefail

readonly _HACKMD_BASE_URL="https://api.hackmd.io/v1"

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_hackmd_check_token() {
  if [[ -z "${HACKMD_API_TOKEN:-}" ]]; then
    echo "ERROR: HACKMD_API_TOKEN is not set." >&2
    echo "Export it before calling hackmd functions:" >&2
    echo "  export HACKMD_API_TOKEN=your_token_here" >&2
    return 1
  fi
}

# _hackmd_request METHOD PATH [BODY]
# Outputs: HTTP_STATUS\nRESPONSE_BODY
_hackmd_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  _hackmd_check_token

  local args=(
    -s
    -w "\n%{http_code}"
    -X "$method"
    -H "Authorization: Bearer $HACKMD_API_TOKEN"
    -H "Accept: application/json"
  )

  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi

  local raw
  raw=$(curl "${args[@]}" "${_HACKMD_BASE_URL}${path}")

  local http_status
  http_status=$(echo "$raw" | tail -n1)
  local response_body
  # sed '$d' is portable; head -n -1 is GNU-only and breaks on macOS/BSD.
  response_body=$(echo "$raw" | sed '$d')

  if [[ "$http_status" -ge 400 ]]; then
    echo "ERROR: HTTP $http_status" >&2
    echo "$response_body" >&2
    return 1
  fi

  echo "$response_body"
}

# _hackmd_json_string reads stdin and outputs a JSON-encoded string (with quotes)
_hackmd_json_string() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

# _hackmd_confirm PROMPT — returns 0 only if user types "yes" (case-insensitive)
_hackmd_confirm() {
  local prompt="$1"
  echo "$prompt" >&2
  local answer
  read -r answer
  if [[ "${answer,,}" != "yes" ]]; then
    echo "Aborted." >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# User
# ---------------------------------------------------------------------------

hackmd_get_user_info() {
  _hackmd_request GET /me
}

# ---------------------------------------------------------------------------
# Personal Notes
# ---------------------------------------------------------------------------

hackmd_list_notes() {
  _hackmd_request GET /notes
}

hackmd_get_note() {
  local note_id="${1:?Usage: hackmd_get_note <noteId>}"
  _hackmd_request GET "/notes/$note_id"
}

hackmd_create_note() {
  local title="${1:?Usage: hackmd_create_note <title> [content] [readPerm] [writePerm]}"
  local content="${2:-}"
  local read_perm="${3:-owner}"
  local write_perm="${4:-owner}"

  local json_content
  json_content=$(echo -n "$content" | _hackmd_json_string)
  local json_title
  json_title=$(echo -n "$title" | _hackmd_json_string)

  local body
  body=$(printf '{"title":%s,"content":%s,"readPermission":"%s","writePermission":"%s"}' \
    "$json_title" "$json_content" "$read_perm" "$write_perm")

  _hackmd_request POST /notes "$body"
}

hackmd_update_note() {
  local note_id="${1:?Usage: hackmd_update_note <noteId> <json_patch>}"
  local json_patch="${2:?Provide a JSON patch object, e.g. {\"title\":\"New Title\"}}"

  _hackmd_request PATCH "/notes/$note_id" "$json_patch"
}

# hackmd_create_note_in_folder <title> <folderId> [content_file] [readPerm] [writePerm]
# Two-step because POST /notes silently DROPS parentFolderId in the current API
# (empirically verified — the field is documented in the OpenAPI spec but not
# honored on create). This helper creates the note, then PATCHes parentFolderId.
# Pass "" for content_file to create an empty note.
hackmd_create_note_in_folder() {
  local title="${1:?Usage: hackmd_create_note_in_folder <title> <folderId> [content_file] [readPerm] [writePerm]}"
  local folder_id="${2:?Provide a folderId}"
  local content_file="${3:-}"
  local read_perm="${4:-owner}"
  local write_perm="${5:-owner}"

  local content=""
  if [[ -n "$content_file" ]]; then
    if [[ ! -f "$content_file" ]]; then
      echo "ERROR: content file not found: $content_file" >&2
      return 1
    fi
    content=$(cat "$content_file")
  fi

  local create
  create=$(hackmd_create_note "$title" "$content" "$read_perm" "$write_perm") || return 1
  local note_id
  note_id=$(echo "$create" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

  # PATCH returns 202 (async) but the move persists.
  _hackmd_request PATCH "/notes/$note_id" "$(printf '{"parentFolderId":%s}' "$(printf '%s' "$folder_id" | _hackmd_json_string)")" >/dev/null || return 1

  echo "$create"
}

# hackmd_get_note_folder_path <noteId>
# Prints the note's folder path (or empty if root). Uses the `folderPaths`
# array returned by GET /notes/{id} — this is the ancestor chain, not a
# scalar parentFolderId (which is the request-only field name).
hackmd_get_note_folder_path() {
  local note_id="${1:?Usage: hackmd_get_note_folder_path <noteId>}"
  local note
  note=$(hackmd_get_note "$note_id") || return 1
  echo "$note" | python3 -c '
import json, sys
d = json.load(sys.stdin)
paths = d.get("folderPaths") or []
print(" / ".join(p.get("name","?") for p in paths))
'
}

# Update note content from a file
hackmd_update_note_content() {
  local note_id="${1:?Usage: hackmd_update_note_content <noteId> <file_path>}"
  local file_path="${2:?Provide a file path}"

  if [[ ! -f "$file_path" ]]; then
    echo "ERROR: File not found: $file_path" >&2
    return 1
  fi

  local json_content
  json_content=$(cat "$file_path" | _hackmd_json_string)
  local body
  body=$(printf '{"content":%s}' "$json_content")

  _hackmd_request PATCH "/notes/$note_id" "$body"
}

hackmd_delete_note() {
  local note_id="${1:?Usage: hackmd_delete_note <noteId>}"

  _hackmd_confirm "Are you sure you want to permanently delete note '$note_id'? Type 'yes' to confirm:"

  _hackmd_request DELETE "/notes/$note_id"
  echo "Note '$note_id' deleted."
}

# ---------------------------------------------------------------------------
# Reading History
# ---------------------------------------------------------------------------

hackmd_get_history() {
  _hackmd_request GET /history
}

# ---------------------------------------------------------------------------
# Teams
# ---------------------------------------------------------------------------

hackmd_list_teams() {
  _hackmd_request GET /teams
}

# ---------------------------------------------------------------------------
# Team Notes
# ---------------------------------------------------------------------------

hackmd_list_team_notes() {
  local team_path="${1:?Usage: hackmd_list_team_notes <teamPath>}"
  _hackmd_request GET "/teams/$team_path/notes"
}

hackmd_create_team_note() {
  local team_path="${1:?Usage: hackmd_create_team_note <teamPath> <title> [content] [readPerm] [writePerm]}"
  local title="${2:?Provide a title}"
  local content="${3:-}"
  local read_perm="${4:-signed_in}"
  local write_perm="${5:-signed_in}"

  local json_content
  json_content=$(echo -n "$content" | _hackmd_json_string)
  local json_title
  json_title=$(echo -n "$title" | _hackmd_json_string)

  local body
  body=$(printf '{"title":%s,"content":%s,"readPermission":"%s","writePermission":"%s"}' \
    "$json_title" "$json_content" "$read_perm" "$write_perm")

  _hackmd_request POST "/teams/$team_path/notes" "$body"
}

hackmd_update_team_note() {
  local team_path="${1:?Usage: hackmd_update_team_note <teamPath> <noteId> <json_patch>}"
  local note_id="${2:?Provide a noteId}"
  local json_patch="${3:?Provide a JSON patch object}"

  _hackmd_request PATCH "/teams/$team_path/notes/$note_id" "$json_patch"
}

hackmd_delete_team_note() {
  local team_path="${1:?Usage: hackmd_delete_team_note <teamPath> <noteId>}"
  local note_id="${2:?Provide a noteId}"

  _hackmd_confirm "Are you sure you want to permanently delete note '$note_id' from team '$team_path'? Type 'yes' to confirm:"

  _hackmd_request DELETE "/teams/$team_path/notes/$note_id"
  echo "Team note '$note_id' from '$team_path' deleted."
}

# ---------------------------------------------------------------------------
# Folders (Personal)
# ---------------------------------------------------------------------------

hackmd_list_folders() {
  _hackmd_request GET /folders
}

hackmd_get_folder() {
  local folder_id="${1:?Usage: hackmd_get_folder <folderId>}"
  _hackmd_request GET "/folders/$folder_id"
}

# hackmd_create_folder <name> [parentFolderId] [icon] [color] [description]
# Pass "" (empty string) to skip an optional argument and provide a later one,
# e.g. hackmd_create_folder "Specs" "" "📐" "#FFB400" "Product specs"
# Empty strings are dropped from the JSON body, not sent as "".
hackmd_create_folder() {
  local name="${1:?Usage: hackmd_create_folder <name> [parentFolderId] [icon] [color] [description]}"
  local parent_id="${2:-}"
  local icon="${3:-}"
  local color="${4:-}"
  local description="${5:-}"

  local body
  body=$(NAME="$name" PARENT="$parent_id" ICON="$icon" COLOR="$color" DESC="$description" \
    python3 -c '
import json, os
out = {"name": os.environ["NAME"]}
for key, env in (("parentFolderId","PARENT"),("icon","ICON"),("color","COLOR"),("description","DESC")):
    v = os.environ.get(env, "")
    if v:
        out[key] = v
print(json.dumps(out))')

  _hackmd_request POST /folders "$body"
}

# hackmd_update_folder <folderId> <json_patch>
hackmd_update_folder() {
  local folder_id="${1:?Usage: hackmd_update_folder <folderId> <json_patch>}"
  local json_patch="${2:?Provide a JSON patch, e.g. {\"name\":\"New\"} or {\"parentFolderId\":null}}"

  _hackmd_request PATCH "/folders/$folder_id" "$json_patch"
}

hackmd_delete_folder() {
  local folder_id="${1:?Usage: hackmd_delete_folder <folderId>}"

  # --skip-notes by default — counting notes requires a GET per note (HackMD's
  # list endpoint omits folder info). Call hackmd_count_folder_children
  # directly without --skip-notes for an accurate but slower count.
  local counts
  if counts=$(hackmd_count_folder_children "$folder_id" --skip-notes 2>/dev/null); then
    echo "Folder '$folder_id' contains: $counts" >&2
  fi
  _hackmd_confirm "Are you sure you want to permanently delete folder '$folder_id'? Children may be orphaned. Type 'yes' to confirm:"

  _hackmd_request DELETE "/folders/$folder_id"
  echo "Folder '$folder_id' deleted."
}

hackmd_get_folder_order() {
  _hackmd_request GET /folders/folder-order
}

# hackmd_put_folder_order <json_order_body>
# Body must be wrapped: {"order": { "root": [...], "<folderId>": [...] }}
# PREFER hackmd_reorder_folder_children for safe partial updates — this PUT
# REPLACES the entire order map.
hackmd_put_folder_order() {
  local body="${1:?Usage: hackmd_put_folder_order '{\"order\":{...}}'}"
  _hackmd_request PUT /folders/folder-order "$body"
}

# hackmd_reorder_folder_children <parentIdOrRoot> <childId1> [childId2 ...]
# Safe merge: fetches current order, replaces only the entry for the given
# parent (use literal "root" for top-level), and PUTs the merged map.
# This prevents accidentally wiping unrelated parent entries.
hackmd_reorder_folder_children() {
  local parent="${1:?Usage: hackmd_reorder_folder_children <parentIdOrRoot> <childId1> [childId2 ...]}"
  shift
  if [[ $# -eq 0 ]]; then
    echo "ERROR: provide at least one child folder id" >&2
    return 1
  fi
  local children=("$@")

  local current
  current=$(hackmd_get_folder_order) || return 1

  local body
  body=$(PARENT="$parent" CHILDREN="${children[*]}" CURRENT="$current" python3 -c '
import json, os
current = json.loads(os.environ["CURRENT"]) if os.environ["CURRENT"].strip() else {}
current[os.environ["PARENT"]] = os.environ["CHILDREN"].split(" ")
print(json.dumps({"order": current}))')

  _hackmd_request PUT /folders/folder-order "$body"
}

# hackmd_reorder_team_folder_children <teamPath> <parentIdOrRoot> <childId1> [childId2 ...]
hackmd_reorder_team_folder_children() {
  local team_path="${1:?Usage: hackmd_reorder_team_folder_children <teamPath> <parentIdOrRoot> <childId1> [childId2 ...]}"
  local parent="${2:?Provide parent id or 'root'}"
  shift 2
  if [[ $# -eq 0 ]]; then
    echo "ERROR: provide at least one child folder id" >&2
    return 1
  fi
  local children=("$@")

  local current
  current=$(hackmd_get_team_folder_order "$team_path") || return 1

  local body
  body=$(PARENT="$parent" CHILDREN="${children[*]}" CURRENT="$current" python3 -c '
import json, os
current = json.loads(os.environ["CURRENT"]) if os.environ["CURRENT"].strip() else {}
current[os.environ["PARENT"]] = os.environ["CHILDREN"].split(" ")
print(json.dumps({"order": current}))')

  _hackmd_request PUT "/teams/$team_path/folders/folder-order" "$body"
}

# hackmd_check_folder_cycle <folderId> <newParentId>
# Returns 0 if it is SAFE to set folderId.parentFolderId = newParentId.
# Returns 1 if it would create a cycle (newParent is a descendant of folder,
# or equals folder itself). Pass "" or "root" as newParentId to mean top-level
# (always safe).
hackmd_check_folder_cycle() {
  local folder_id="${1:?Usage: hackmd_check_folder_cycle <folderId> <newParentId>}"
  local new_parent="${2:-}"

  if [[ -z "$new_parent" || "$new_parent" == "root" || "$new_parent" == "null" ]]; then
    return 0
  fi
  if [[ "$new_parent" == "$folder_id" ]]; then
    echo "ERROR: cannot make a folder its own parent" >&2
    return 1
  fi

  local all
  all=$(hackmd_list_folders) || return 1

  FOLDER="$folder_id" NEW_PARENT="$new_parent" ALL="$all" python3 <<'PY'
import json, os, sys
all_folders = json.loads(os.environ["ALL"])
by_id = {f["id"]: f for f in all_folders}
target = os.environ["FOLDER"]
node = os.environ["NEW_PARENT"]
seen = set()
while node and node not in seen:
    if node == target:
        print(f"ERROR: cycle detected — {os.environ['NEW_PARENT']} is a descendant of {target}", file=sys.stderr)
        sys.exit(1)
    seen.add(node)
    f = by_id.get(node)
    if not f:
        break
    node = f.get("parentFolderId")
sys.exit(0)
PY
}

# hackmd_count_folder_children <folderId>
# Prints "<subfolderCount> subfolders, <noteCount> notes".
# Subfolder count is from GET /folders (cheap). Note count requires a GET on
# each note because the API's GET /notes list omits folder info — pass
# --skip-notes as a second arg if that O(N) fetch is too expensive and you
# just want the subfolder count.
hackmd_count_folder_children() {
  local folder_id="${1:?Usage: hackmd_count_folder_children <folderId> [--skip-notes]}"
  local mode="${2:-}"

  local folders
  folders=$(hackmd_list_folders) || return 1
  local sub
  sub=$(FOLDER="$folder_id" FOLDERS="$folders" python3 -c '
import json, os
print(sum(1 for f in json.loads(os.environ["FOLDERS"]) if f.get("parentFolderId") == os.environ["FOLDER"]))
')

  if [[ "$mode" == "--skip-notes" ]]; then
    echo "$sub subfolders, ? notes (skipped)"
    return 0
  fi

  local notes
  notes=$(hackmd_list_notes) || return 1
  local nts
  nts=$(FOLDER="$folder_id" NOTES="$notes" TOKEN="$HACKMD_API_TOKEN" python3 <<'PY'
import json, os, urllib.request
fid = os.environ["FOLDER"]
notes = json.loads(os.environ["NOTES"])
hdr = {"Authorization": f"Bearer {os.environ['TOKEN']}"}
count = 0
for n in notes:
    try:
        r = urllib.request.urlopen(urllib.request.Request(
            f"https://api.hackmd.io/v1/notes/{n['id']}", headers=hdr), timeout=10).read()
        d = json.loads(r)
    except Exception:
        continue
    if any(p.get("id") == fid for p in (d.get("folderPaths") or [])):
        count += 1
print(count)
PY
)
  echo "$sub subfolders, $nts notes"
}

# hackmd_count_team_folder_children <teamPath> <folderId> [--skip-notes]
hackmd_count_team_folder_children() {
  local team_path="${1:?Usage: hackmd_count_team_folder_children <teamPath> <folderId> [--skip-notes]}"
  local folder_id="${2:?Provide a folderId}"
  local mode="${3:-}"

  local folders
  folders=$(hackmd_list_team_folders "$team_path") || return 1
  local sub
  sub=$(FOLDER="$folder_id" FOLDERS="$folders" python3 -c '
import json, os
print(sum(1 for f in json.loads(os.environ["FOLDERS"]) if f.get("parentFolderId") == os.environ["FOLDER"]))
')

  if [[ "$mode" == "--skip-notes" ]]; then
    echo "$sub subfolders, ? notes (skipped)"
    return 0
  fi

  local notes
  notes=$(hackmd_list_team_notes "$team_path") || return 1
  local nts
  nts=$(FOLDER="$folder_id" TEAM="$team_path" NOTES="$notes" TOKEN="$HACKMD_API_TOKEN" python3 <<'PY'
import json, os, urllib.request
fid = os.environ["FOLDER"]
team = os.environ["TEAM"]
notes = json.loads(os.environ["NOTES"])
hdr = {"Authorization": f"Bearer {os.environ['TOKEN']}"}
count = 0
for n in notes:
    try:
        r = urllib.request.urlopen(urllib.request.Request(
            f"https://api.hackmd.io/v1/teams/{team}/notes/{n['id']}", headers=hdr), timeout=10).read()
        d = json.loads(r)
    except Exception:
        continue
    if any(p.get("id") == fid for p in (d.get("folderPaths") or [])):
        count += 1
print(count)
PY
)
  echo "$sub subfolders, $nts notes"
}

# ---------------------------------------------------------------------------
# Folders (Team)
# ---------------------------------------------------------------------------

hackmd_list_team_folders() {
  local team_path="${1:?Usage: hackmd_list_team_folders <teamPath>}"
  _hackmd_request GET "/teams/$team_path/folders"
}

hackmd_get_team_folder() {
  local team_path="${1:?Usage: hackmd_get_team_folder <teamPath> <folderId>}"
  local folder_id="${2:?Provide a folderId}"
  _hackmd_request GET "/teams/$team_path/folders/$folder_id"
}

# hackmd_create_team_folder <teamPath> <name> [parentFolderId] [icon] [color] [description]
# Same empty-string-skip semantics as hackmd_create_folder.
hackmd_create_team_folder() {
  local team_path="${1:?Usage: hackmd_create_team_folder <teamPath> <name> [parentFolderId] [icon] [color] [description]}"
  local name="${2:?Provide a folder name}"
  local parent_id="${3:-}"
  local icon="${4:-}"
  local color="${5:-}"
  local description="${6:-}"

  local body
  body=$(NAME="$name" PARENT="$parent_id" ICON="$icon" COLOR="$color" DESC="$description" \
    python3 -c '
import json, os
out = {"name": os.environ["NAME"]}
for key, env in (("parentFolderId","PARENT"),("icon","ICON"),("color","COLOR"),("description","DESC")):
    v = os.environ.get(env, "")
    if v:
        out[key] = v
print(json.dumps(out))')

  _hackmd_request POST "/teams/$team_path/folders" "$body"
}

# hackmd_update_team_folder <teamPath> <folderId> <json_patch>
hackmd_update_team_folder() {
  local team_path="${1:?Usage: hackmd_update_team_folder <teamPath> <folderId> <json_patch>}"
  local folder_id="${2:?Provide a folderId}"
  local json_patch="${3:?Provide a JSON patch}"

  _hackmd_request PATCH "/teams/$team_path/folders/$folder_id" "$json_patch"
}

hackmd_delete_team_folder() {
  local team_path="${1:?Usage: hackmd_delete_team_folder <teamPath> <folderId>}"
  local folder_id="${2:?Provide a folderId}"

  local counts
  if counts=$(hackmd_count_team_folder_children "$team_path" "$folder_id" --skip-notes 2>/dev/null); then
    echo "Folder '$folder_id' in team '$team_path' contains: $counts" >&2
  fi
  _hackmd_confirm "Are you sure you want to permanently delete folder '$folder_id' from team '$team_path'? Children may be orphaned. Type 'yes' to confirm:"

  _hackmd_request DELETE "/teams/$team_path/folders/$folder_id"
  echo "Team folder '$folder_id' from '$team_path' deleted."
}

hackmd_get_team_folder_order() {
  local team_path="${1:?Usage: hackmd_get_team_folder_order <teamPath>}"
  _hackmd_request GET "/teams/$team_path/folders/folder-order"
}

hackmd_put_team_folder_order() {
  local team_path="${1:?Usage: hackmd_put_team_folder_order <teamPath> '{\"order\":{...}}'}"
  local body="${2:?Provide the order body}"
  _hackmd_request PUT "/teams/$team_path/folders/folder-order" "$body"
}

# ---------------------------------------------------------------------------
# Note Images
# ---------------------------------------------------------------------------

# hackmd_upload_note_image <noteId> <image_path>
# Uses multipart form-data (does not go through _hackmd_request).
# Soft size warning at 5 MB — HackMD's exact upload limit is not published in
# the OpenAPI spec, but uploads above ~5 MB commonly return 413. If 413 is
# returned, downsize or recompress the image and retry.
readonly _HACKMD_IMAGE_SOFT_LIMIT_BYTES=$((5 * 1024 * 1024))

hackmd_upload_note_image() {
  local note_id="${1:?Usage: hackmd_upload_note_image <noteId> <image_path>}"
  local image_path="${2:?Provide an image path}"

  _hackmd_check_token

  if [[ ! -f "$image_path" ]]; then
    echo "ERROR: Image file not found: $image_path" >&2
    return 1
  fi

  local size_bytes
  size_bytes=$(stat -f%z "$image_path" 2>/dev/null || stat -c%s "$image_path" 2>/dev/null || echo 0)
  if [[ "$size_bytes" -gt "$_HACKMD_IMAGE_SOFT_LIMIT_BYTES" ]]; then
    echo "WARNING: '$image_path' is $size_bytes bytes (>5 MB). Upload may return 413; downsize if it fails." >&2
  fi

  local raw
  raw=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer $HACKMD_API_TOKEN" \
    -H "Accept: application/json" \
    -F "image=@$image_path" \
    "${_HACKMD_BASE_URL}/notes/$note_id/images")

  local http_status
  http_status=$(echo "$raw" | tail -n1)
  local response_body
  response_body=$(echo "$raw" | sed '$d')

  if [[ "$http_status" == "413" ]]; then
    echo "ERROR: HTTP 413 — image too large. Downsize the file (e.g. with sips -Z 1600) and retry." >&2
    return 1
  fi
  if [[ "$http_status" -ge 400 ]]; then
    echo "ERROR: HTTP $http_status" >&2
    echo "$response_body" >&2
    return 1
  fi

  echo "$response_body"
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

hackmd_help() {
  cat <<'EOF'
hackmd-curl.sh — HackMD API CLI

Usage: source hackmd-curl.sh && <command> [args...]
       ./hackmd-curl.sh <command> [args...]

Requires: export HACKMD_API_TOKEN=<your_token>

Commands:

  User / History:
    hackmd_get_user_info
    hackmd_get_history

  Personal notes:
    hackmd_list_notes
    hackmd_get_note <noteId>
    hackmd_create_note <title> [content] [readPerm] [writePerm]
    hackmd_create_note_in_folder <title> <folderId> [content_file] [readPerm] [writePerm]
    hackmd_update_note <noteId> <json_patch>
    hackmd_update_note_content <noteId> <file_path>
    hackmd_delete_note <noteId>
    hackmd_get_note_folder_path <noteId>

  Personal folders:
    hackmd_list_folders
    hackmd_get_folder <folderId>
    hackmd_create_folder <name> [parentFolderId] [icon] [color] [description]
    hackmd_update_folder <folderId> <json_patch>
    hackmd_delete_folder <folderId>                # previews child count
    hackmd_count_folder_children <folderId>
    hackmd_check_folder_cycle <folderId> <newParentId>
    hackmd_get_folder_order
    hackmd_reorder_folder_children <parentIdOrRoot> <childId1> [...] # SAFE merge
    hackmd_put_folder_order '<json_order_body>'    # raw — replaces full map

  Teams:
    hackmd_list_teams
    hackmd_list_team_notes <teamPath>
    hackmd_create_team_note <teamPath> <title> [content] [readPerm] [writePerm]
    hackmd_update_team_note <teamPath> <noteId> <json_patch>
    hackmd_delete_team_note <teamPath> <noteId>

  Team folders:
    hackmd_list_team_folders <teamPath>
    hackmd_get_team_folder <teamPath> <folderId>
    hackmd_create_team_folder <teamPath> <name> [parentFolderId] [icon] [color] [description]
    hackmd_update_team_folder <teamPath> <folderId> <json_patch>
    hackmd_delete_team_folder <teamPath> <folderId>             # previews child count
    hackmd_count_team_folder_children <teamPath> <folderId>
    hackmd_get_team_folder_order <teamPath>
    hackmd_reorder_team_folder_children <teamPath> <parentIdOrRoot> <childId1> [...]  # SAFE
    hackmd_put_team_folder_order <teamPath> '<json_order_body>'  # raw — replaces full map

  Note images:
    hackmd_upload_note_image <noteId> <image_path>

  hackmd_help

Permission values:
  readPermission / writePermission: owner | signed_in | guest
  commentPermission: disabled | forbidden | owners | signed_in_users | everyone

Note write-body extras (passed via hackmd_update_note JSON patch):
  parentFolderId, permalink, tags[], description, suggestEditPermission

Examples:
  hackmd_create_note "Sprint Retro" "## What went well" "signed_in" "owner"
  hackmd_get_note AbCdEfGh
  hackmd_update_note AbCdEfGh '{"title":"Updated Title"}'
  hackmd_update_note AbCdEfGh '{"parentFolderId":"<folderId>"}'   # move into folder
  hackmd_update_note AbCdEfGh '{"parentFolderId":null}'           # move to root
  hackmd_update_note_content AbCdEfGh ./retro.md

  hackmd_create_folder "Specs" "" "📐" "#FFB400" "Product specs"
  hackmd_update_folder <folderId> '{"name":"Specs (archived)","color":"#888"}'

  hackmd_create_team_note engineering "ADR-001" "# Decision" "signed_in" "signed_in"
  hackmd_create_team_folder engineering "ADRs" "" "📐" "#3E63DD"

  hackmd_upload_note_image AbCdEfGh ./diagram.png
EOF
}

# ---------------------------------------------------------------------------
# Direct execution support
# ---------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being run directly (not sourced)
  if [[ $# -eq 0 ]]; then
    hackmd_help
    exit 0
  fi

  command="$1"
  shift
  "hackmd_${command}" "$@"
fi
