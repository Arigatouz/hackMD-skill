---
name: hackmd
description: |
  Manage HackMD notes, folders, images, and team workspaces. Use for creating,
  reading, updating, and deleting notes; organizing notes into folders (personal
  or team) and reordering them; uploading images attached to notes; browsing
  reading history; and working with team workspaces. Leverages the mcp__hackmd__*
  MCP tools where they exist, and falls back to scripts/hackmd-curl.sh for direct
  API access (required for folders and image uploads, which the MCP server does
  not currently expose).

  NOT for: editing local .md files, GitHub wikis, Confluence pages, Notion pages,
  or any markdown that lives outside HackMD. Do not trigger on general markdown
  formatting questions or README.md edits.
---

# HackMD Skill

## When to Use

Trigger this skill when the user wants to:
- Create a new HackMD note (personal or team)
- Read or fetch an existing HackMD note by ID or URL
- List their personal notes or team notes
- Update the content or metadata of a note (title, content, tags, description,
  permalink, permissions, parent folder)
- Delete a HackMD note
- Browse their HackMD reading history
- List their teams or team note collections
- Manage permissions on a HackMD note
- Create, fetch, list, rename, recolor, move, or delete folders (personal or team)
- Reorder folders in the sidebar (folder-order)
- Place a note in a folder via `parentFolderId`
- Upload an image attached to a note

## When NOT to Use

- Editing local `.md` files on disk → use standard file editing tools
- GitHub wikis, Confluence, Notion, or any non-HackMD platform
- General markdown formatting help not tied to HackMD
- README.md, CHANGELOG.md, or documentation files in the codebase

---

## Prerequisites

### 1. Verify MCP availability
Check if `mcp__hackmd__get_user_info` is available. If it is, use MCP tools for all
operations. If not, fall back to `scripts/hackmd-curl.sh`.

### 2. Confirm authentication
Call `mcp__hackmd__get_user_info`. If it returns a valid user object, authentication
is working. If it returns 401, prompt the user to set `HACKMD_API_TOKEN` in their
environment or MCP configuration.

### 3. Fallback path
If MCP tools are unavailable:
```bash
source ~/.claude/skills/hackmd/scripts/hackmd-curl.sh
hackmd_help
```
Ensure `HACKMD_API_TOKEN` is exported before sourcing.

---

## Available MCP Tools

| Tool | Purpose |
|---|---|
| `mcp__hackmd__get_user_info` | Get authenticated user profile |
| `mcp__hackmd__get_history` | List recently viewed notes |
| `mcp__hackmd__list_user_notes` | List all personal notes |
| `mcp__hackmd__get_note` | Fetch a note by ID |
| `mcp__hackmd__create_note` | Create a new personal note |
| `mcp__hackmd__update_note` | Update note metadata/content |
| `mcp__hackmd__delete_note` | Delete a personal note |
| `mcp__hackmd__list_teams` | List teams the user belongs to |
| `mcp__hackmd__list_team_notes` | List notes in a team workspace |
| `mcp__hackmd__create_team_note` | Create a note in a team workspace |
| `mcp__hackmd__update_team_note` | Update a team note |
| `mcp__hackmd__delete_team_note` | Delete a team note |

> **Coverage gaps — use curl fallback for these:** Verified against
> `hackmd-mcp@1.5.7` (current latest on npm). The MCP server does **not**
> expose:
>
> - any folder CRUD or folder-order tool;
> - the image upload endpoint;
> - the `title` field on `update_note` (only `content`, `readPermission`,
>   `writePermission`, `permalink` are in the schema);
> - the extended note fields `parentFolderId`, `tags`, `description`,
>   `suggestEditPermission`, `noteFeatures` on either `create_note` or
>   `update_note`.
>
> Whenever a workflow needs any of the above, source
> `scripts/hackmd-curl.sh` and call the relevant `hackmd_*` function (which
> talks to the REST API directly). Re-check this list against
> `https://registry.npmjs.org/hackmd-mcp/latest` if the table looks stale.

### Note write-body fields (POST/PATCH)

Both the REST API and the curl helpers accept the full field set below. The
MCP tools accept only the subset noted as **"MCP"**; everything else is
**curl-only** until the MCP server is updated.

| Field | Type | Available via | Notes |
|---|---|---|---|
| `title` | string | MCP `create_note`; **curl-only** for updates | Use `hackmd_update_note` to rename — MCP `update_note` ignores title |
| `content` | string | MCP + curl | Markdown body |
| `readPermission` / `writePermission` | enum | MCP + curl | `owner` \| `signed_in` \| `guest` |
| `commentPermission` | enum | MCP `create_note` + curl | `disabled` \| `forbidden` \| `owners` \| `signed_in_users` \| `everyone` |
| `permalink` | string | MCP + curl | Custom URL slug; 409 if taken |
| `parentFolderId` | string \| null | **curl-only, PATCH only** | Folder UUID from `/folders`. **POST silently drops this field** — use `hackmd_create_note_in_folder` (POST + PATCH) instead. On read, exposed as `folderPaths` (ancestor array), not as a scalar |
| `tags` | string[] | **curl-only** | Tag list on the note |
| `description` | string | **curl-only** | Note description |
| `suggestEditPermission` | enum | **curl-only** | Who can suggest edits |
| `noteFeatures` | object | **curl-only** | Per-feature permission map |

---

## Workflows

### 1. Create a personal note

1. Collect from the user: title, content (markdown), and desired permissions.
   Default permissions: `readPermission: "owner"`, `writePermission: "owner"`.
2. Call `mcp__hackmd__create_note` with `title`, `content`, `readPermission`,
   `writePermission`, and optionally `commentPermission`.
3. Return the note's `id`, `publishLink`, and `shortId` to the user.

> **Empirically verified quirk:** `POST /notes` **silently drops** the
> `parentFolderId` field, even though the OpenAPI spec lists it. If the user
> wants the new note placed in a folder, use the curl helper
> `hackmd_create_note_in_folder <title> <folderId> [content_file]` which does
> the create + PATCH in one call, or follow workflow 15 manually after create.

```json
{
  "title": "Sprint Retrospective",
  "content": "# Sprint Retro\n\n## What went well\n\n## What to improve",
  "readPermission": "signed_in",
  "writePermission": "owner",
  "commentPermission": "everyone"
}
```

### 2. Read / fetch a note

1. Extract the note ID from the user's input (full URL or bare ID).
   - From URL `https://hackmd.io/AbCdEfGh` → ID is `AbCdEfGh`
   - From URL `https://hackmd.io/@team/note-slug` → use the path as the ID
2. Call `mcp__hackmd__get_note` with `noteId`.
3. Present the note's `title`, `content`, `lastChangedAt`, and `publishLink`.

### 3. List personal notes

1. Call `mcp__hackmd__list_user_notes`.
2. Present results as a table: ID, title, last modified, read/write permissions.
3. If the list is long (>20), offer to filter by title keyword.

### 4. Update a note

1. Identify the note by ID (fetch first if the user gave a title or URL).
2. Collect changes. Route by field:
   - `content`, `readPermission`, `writePermission`, `permalink` → `mcp__hackmd__update_note` with `noteId` and only the changed fields.
   - `title`, `tags`, `description`, `parentFolderId`, `suggestEditPermission`, or `noteFeatures` → curl helper `hackmd_update_note <noteId> '<json_patch>'` (MCP `update_note` ignores these fields — see the field table above).
3. Confirm success and show the updated `lastChangedAt`.

### 5. Delete a personal note

> **Warning:** Deletion is permanent and cannot be undone.

1. Fetch the note with `mcp__hackmd__get_note` to confirm it exists and show the title.
2. Explicitly ask the user: "Are you sure you want to permanently delete «{title}»? Type YES to confirm."
3. Only proceed if the user responds with exactly `YES`.
4. Call `mcp__hackmd__delete_note` with `noteId`.
5. Confirm deletion.

### 6. Browse reading history

1. Call `mcp__hackmd__get_history`.
2. Present results as a list: title, ID, last viewed time.
3. Offer to open/fetch any note from the list.

### 7. List teams

1. Call `mcp__hackmd__list_teams`.
2. Present each team's `name`, `path` (used as `teamPath` in subsequent calls), and `description`.

### 8. List team notes

1. Obtain `teamPath` from the user or from `mcp__hackmd__list_teams`.
2. Call `mcp__hackmd__list_team_notes` with `teamPath`.
3. Present results as a table: ID, title, last modified, permissions.

### 9. Create a team note

1. Confirm the target `teamPath`.
2. Collect: title, content, and permissions.
3. Call `mcp__hackmd__create_team_note` with `teamPath`, `title`, `content`,
   `readPermission`, `writePermission`, and optionally `commentPermission`.
4. Return the note's `id` and `publishLink`.

### 10. Update a team note

1. Identify the note by `noteId` within the team (use `mcp__hackmd__list_team_notes`
   if needed to locate it).
2. Collect the changes to apply.
3. Call `mcp__hackmd__update_team_note` with `teamPath`, `noteId`, and updated fields.
4. Confirm success.

### 11. Delete a team note

> **Warning:** Deletion is permanent and cannot be undone.

1. Fetch the note details to confirm it exists and show the title.
2. Explicitly ask the user: "Are you sure you want to permanently delete «{title}» from team «{teamPath}»? Type YES to confirm."
3. Only proceed if the user responds with exactly `YES`.
4. Call `mcp__hackmd__delete_team_note` with `teamPath` and `noteId`.
5. Confirm deletion.

### 12. List folders (personal or team)

The folder API is not yet exposed via MCP — use the curl fallback.

```bash
source ~/.claude/skills/hackmd/scripts/hackmd-curl.sh
hackmd_list_folders                 # personal
hackmd_list_team_folders <teamPath> # team
```

Returns an array of `ApiFolder` objects: `{ id, name, description, icon, color,
parentFolderId, createdAt, updatedAt }`. `parentFolderId` is `null` for top-level
folders. Present as a tree grouped by `parentFolderId`.

### 13. Create a folder (personal or team)

1. Collect: `name` (required), optional `description`, `icon`, `color`,
   `parentFolderId` (to nest under an existing folder).
2. Call:

   ```bash
   hackmd_create_folder "<name>" [parentFolderId] [icon] [color] [description]
   hackmd_create_team_folder <teamPath> "<name>" [parentFolderId] [icon] [color] [description]
   ```

3. Return the new folder's `id` to the user; reference it as `parentFolderId`
   when nesting or when placing notes via `POST /notes` / `PATCH /notes/{id}`.

### 14. Fetch / update / delete a folder

```bash
hackmd_get_folder <folderId>
hackmd_get_team_folder <teamPath> <folderId>

hackmd_update_folder <folderId> '<json_patch>'
hackmd_update_team_folder <teamPath> <folderId> '<json_patch>'

hackmd_delete_folder <folderId>
hackmd_delete_team_folder <teamPath> <folderId>
```

- Update body fields: `name`, `description`, `icon`, `color`, `parentFolderId`.
  Pass `null` to clear a field (e.g. `{"parentFolderId": null}` moves a folder
  to the top level).
- **Before re-nesting** (changing `parentFolderId` to a non-null value), call
  `hackmd_check_folder_cycle <folderId> <newParentId>` first. The API does not
  document cycle-prevention, so the helper walks `parentFolderId` chains
  client-side and refuses the move if `newParentId` is a descendant of
  `folderId` (or equals it).
- **Before deletion**, the `hackmd_delete_folder*` helpers print the
  **subfolder** count (skipping notes for speed — see next bullet). The API's
  behavior on non-empty folder delete is undocumented in the spec; children
  may be orphaned to root. Surface this count to the user, then require
  explicit `YES` confirmation (see workflow 5/11 pattern).
- **Accurate note count is expensive.** `GET /notes` summaries omit folder
  info, so `hackmd_count_folder_children <folderId>` without `--skip-notes`
  has to fetch each note individually. Run it explicitly only when the user
  needs the precise number before deleting.

### 15. Move a note into a folder

1. Resolve the target folder's `id` via workflow 12/13 (or create one first).
2. PATCH the note with `parentFolderId` via the curl helper:

   ```bash
   hackmd_update_note <noteId> '{"parentFolderId":"<folderId>"}'
   # team note:
   hackmd_update_team_note <teamPath> <noteId> '{"parentFolderId":"<folderId>"}'
   ```

3. To move back to "no folder" / root: `'{"parentFolderId":null}'`.

4. Verify the move with `hackmd_get_note_folder_path <noteId>` — the API
   `PATCH` returns **`202 Accepted`** (the move is async), so a quick read-back
   confirms it landed.

> **MCP caveat (verified against hackmd-mcp@1.5.7):** `mcp__hackmd__update_note`
> only accepts `content`, `readPermission`, `writePermission`, `permalink` —
> it silently drops `parentFolderId`. Always use the `hackmd_update_note`
> curl helper (which calls `PATCH /notes/{id}` directly) for folder moves.

> **Read-side field name:** When reading a note back (`GET /notes/{id}`),
> folder membership is exposed as the array **`folderPaths`** (full ancestor
> chain of `{id,name,icon,parentId,…}` objects) — NOT as a scalar
> `parentFolderId`. The list endpoint `GET /notes` omits folder info
> entirely. Use `hackmd_get_note_folder_path <noteId>` for a human-readable
> path.

### 16. Reorder folders in the sidebar

The order is a per-user map of `parentId → orderedChildIds[]`. Use the literal
string `root` as the key for top-level folders.

**Prefer the safe-merge helper** — it fetches the current order, replaces only
the entry for the target parent, and writes the merged map back in one call:

```bash
hackmd_reorder_folder_children <parentIdOrRoot> <childId1> [childId2 ...]
hackmd_reorder_team_folder_children <teamPath> <parentIdOrRoot> <childId1> [...]
```

Example — reorder top-level folders for the personal workspace:
```bash
hackmd_reorder_folder_children root folder-uuid-b folder-uuid-a
```

**Raw read / write** (when you need to inspect or replace the whole map):
```bash
hackmd_get_folder_order
hackmd_put_folder_order '<json_order_body>'    # see api-endpoints.md for body shape
hackmd_get_team_folder_order <teamPath>
hackmd_put_team_folder_order <teamPath> '<json_order_body>'
```

> **Caution:** `hackmd_put_folder_order` and `hackmd_put_team_folder_order`
> REPLACE the entire order map. Only use them when you've already merged the
> existing map locally; otherwise call `hackmd_reorder_folder_children`.

### 17. Upload an image to a note

`POST /notes/{noteId}/images` takes a multipart form-data body with field `image`.
Returns `{ "data": { "link": "<cdn-url>" } }`.

```bash
hackmd_upload_note_image <noteId> <path/to/image.png>
```

After upload, embed the returned link in markdown:
```markdown
![alt text](https://hackmd.io/_uploads/abcdef.png)
```

The MCP server does not expose this — always use the curl helper.

> **Size limits:** HackMD's exact upload limit is not in the public OpenAPI
> spec, but uploads ≥ ~5 MB commonly return `413 Payload Too Large`. The
> helper warns on files over 5 MB before sending. On 413, downsize before
> retrying — for example:
>
> ```bash
> sips -Z 1600 ./diagram.png --out ./diagram-small.png   # macOS
> # then:
> hackmd_upload_note_image <noteId> ./diagram-small.png
> ```

---

## Markdown Formatting

HackMD supports CommonMark, GitHub Flavored Markdown (GFM), plus HackMD-specific
extensions including admonition blocks, `[TOC]`, KaTeX math, Mermaid diagrams, and
YAML front matter.

See `references/markdown-cheatsheet.md` for the full reference.

**Quick admonition example:**
```
:::info
This is an info block.
:::
```

---

## Error Handling

| HTTP Status | Meaning | Action |
|---|---|---|
| 400 | Bad request / invalid payload | Check required fields; validate permission values |
| 401 | Unauthorized | Prompt user to set/refresh `HACKMD_API_TOKEN` |
| 403 | Forbidden | User lacks permission on this note/team |
| 404 | Not found | Confirm note ID or team path is correct |
| 429 | Rate limited | Wait and retry; inform user of rate limiting |
| 500 | Server error | Retry once; if persistent, report to HackMD support |

---

## Supplementary References

Load on demand — do not read these unless the trigger applies.

| File | Load when… |
|---|---|
| `references/api-endpoints.md` | The MCP server lacks a tool for the desired operation (folders, image upload), or you need exact request/response shapes for the curl path |
| `references/markdown-cheatsheet.md` | The user asks about HackMD-specific markdown (admonitions, `[TOC]`, KaTeX, Mermaid, YAML front matter) |
| `references/permissions-guide.md` | The user asks about who-can-do-what, permission presets, or chooses between `owner` / `signed_in` / `guest` |
| `scripts/hackmd-curl.sh` | Source it whenever the curl fallback path is needed (folders, image upload, or MCP unavailable) |
