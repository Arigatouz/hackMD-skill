# HackMD REST API Reference

Base URL: `https://api.hackmd.io/v1`
Auth header: `Authorization: Bearer $HACKMD_API_TOKEN`

---

## User

### GET /me
Retrieve the authenticated user's profile.

```bash
curl -s -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  https://api.hackmd.io/v1/me
```

Response:
```json
{
  "id": "user-uuid",
  "name": "Alice",
  "email": "alice@example.com",
  "userPath": "alice",
  "photo": "https://...",
  "teams": []
}
```

---

## Personal Notes

### GET /notes
List all personal notes.

```bash
curl -s -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  https://api.hackmd.io/v1/notes
```

Response: array of note summary objects (no `content` field, **no `folderPaths`**).

```json
[
  {
    "id": "AbCdEfGh",
    "title": "My Note",
    "shortId": "AbCdEfGh",
    "publishLink": "https://hackmd.io/AbCdEfGh",
    "createdAt": 1700000000000,
    "lastChangedAt": 1700000000000,
    "readPermission": "owner",
    "writePermission": "owner",
    "commentPermission": "disabled"
  }
]
```

> The summary objects do not include folder information. To know which folder
> a note is in, fetch it individually via `GET /notes/{id}` and inspect
> `folderPaths`.

### GET /notes/{noteId}
Fetch a single note including its full content.

```bash
curl -s -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  https://api.hackmd.io/v1/notes/AbCdEfGh
```

Response includes:

- `content` — raw markdown string (omitted from list responses)
- `tags`, `description`, `permalink`, `publishType`, `publishedAt`,
  `titleUpdatedAt`, `tagsUpdatedAt`, `lastChangedAt`, `lastChangeUser`
- `userPath`, `teamPath`, `readPermission`, `writePermission`
- **`folderPaths`** — array describing the folder ancestry of this note,
  e.g. `[{"id":"...","name":"google/io","icon":"🔵","parentId":null,...},
  {"id":"...","name":"google/io-2026","icon":"🟢","parentId":"...","...":"..."}]`.
  This is the **only** read-side surface for folder membership; there is **no
  scalar `parentFolderId` field** in responses.

> **Note:** `GET /notes` (the list endpoint) returns summaries that **omit
> `folderPaths`** entirely. To know which folder a note is in, you must
> `GET /notes/{id}` individually.

### POST /notes
Create a new personal note.

```bash
curl -s -X POST \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Sprint Retro",
    "content": "# Sprint Retro\n\nNotes here.",
    "readPermission": "signed_in",
    "writePermission": "owner",
    "commentPermission": "everyone"
  }' \
  https://api.hackmd.io/v1/notes
```

Request body fields:
| Field | Type | Required | Values |
|---|---|---|---|
| `title` | string | no | any string |
| `content` | string | no | markdown string |
| `readPermission` | string | no | `owner`, `signed_in`, `guest` |
| `writePermission` | string | no | `owner`, `signed_in`, `guest` |
| `commentPermission` | string | no | `disabled`, `forbidden`, `owners`, `signed_in_users`, `everyone` |
| `suggestEditPermission` | string | no | suggest-edit permission role |
| `parentFolderId` | string | no | folder UUID (see `/folders`) — places the note inside that folder |
| `permalink` | string | no | custom URL slug; `409` if already taken |
| `tags` | string[] | no | tag list |
| `description` | string | no | note description |
| `noteFeatures` | object | no | per-feature permission overrides |
| `origin` | string | no | client origin identifier |

The body may alternatively be a raw markdown string (the API will treat it as `content`).

> **Empirically verified:** `POST /notes` **silently ignores `parentFolderId`**
> as of 2026-05. The note is always created at the workspace root. To place a
> new note in a folder, immediately follow with `PATCH /notes/{id}` setting
> `parentFolderId` (PATCH returns `202 Accepted` and the move persists). The
> curl helper `hackmd_create_note_in_folder` automates both steps.

Response: full note object with `id`, `shortId`, `publishLink`, `folderPaths`
(see GET below).

### PATCH /notes/{noteId}
Update an existing note. Only include fields to change.

Patchable fields: `title`, `content`, `readPermission`, `writePermission`,
`tags`, `description`, `permalink`, `parentFolderId`.

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Updated Title", "content": "New content"}' \
  https://api.hackmd.io/v1/notes/AbCdEfGh
```

Move a note into a folder:
```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"parentFolderId":"<folderId>"}' \
  https://api.hackmd.io/v1/notes/AbCdEfGh
```
Use `{"parentFolderId": null}` to move back to the root.

Response: **`202 Accepted`** (the patch is queued and applied asynchronously,
typically within milliseconds). The response body is the pre-patch note.
Read the note back via `GET /notes/{id}` and check `folderPaths` to confirm
the move landed.

### POST /notes/{noteId}/images
Upload an image attached to a note. Multipart form-data, field name `image`.

```bash
curl -s -X POST \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  -F "image=@./screenshot.png" \
  https://api.hackmd.io/v1/notes/AbCdEfGh/images
```

Response:
```json
{ "data": { "link": "https://hackmd.io/_uploads/abcdef.png" } }
```
Embed the returned URL in markdown as `![alt](<link>)`.

### DELETE /notes/{noteId}
Permanently delete a note.

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  https://api.hackmd.io/v1/notes/AbCdEfGh
```

Response: `204 No Content` on success.

---

## Reading History

### GET /history
List recently viewed notes.

```bash
curl -s -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  https://api.hackmd.io/v1/history
```

Response:
```json
[
  {
    "id": "AbCdEfGh",
    "title": "Some Note",
    "publishLink": "https://hackmd.io/AbCdEfGh",
    "lastVisit": 1700000000000
  }
]
```

---

## Teams

### GET /teams
List all teams the authenticated user belongs to.

```bash
curl -s -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  https://api.hackmd.io/v1/teams
```

Response:
```json
[
  {
    "id": "team-uuid",
    "name": "Engineering",
    "path": "engineering",
    "description": "Eng team workspace",
    "hardLimit": 100,
    "visibility": "private"
  }
]
```

### GET /teams/{teamPath}/notes
List notes in a team workspace.

```bash
curl -s -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  https://api.hackmd.io/v1/teams/engineering/notes
```

Response: array of note summaries (same shape as personal notes list).

### POST /teams/{teamPath}/notes
Create a note in a team workspace. Same body shape as `POST /notes` (title,
content, permissions, plus `parentFolderId`, `permalink`, `tags`, `description`,
`suggestEditPermission`, `commentPermission`, `noteFeatures`, `origin`).

```bash
curl -s -X POST \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Team ADR",
    "content": "# ADR-001\n\nDecision record.",
    "readPermission": "signed_in",
    "writePermission": "signed_in",
    "parentFolderId": "<folderId>",
    "tags": ["adr", "architecture"]
  }' \
  https://api.hackmd.io/v1/teams/engineering/notes
```

### PATCH /teams/{teamPath}/notes/{noteId}
Update a team note. Patchable fields match `PATCH /notes/{noteId}` plus team
context (e.g. `parentFolderId` referencing a team folder).

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Updated content"}' \
  https://api.hackmd.io/v1/teams/engineering/notes/AbCdEfGh
```

### DELETE /teams/{teamPath}/notes/{noteId}
Permanently delete a team note.

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  https://api.hackmd.io/v1/teams/engineering/notes/AbCdEfGh
```

Response: `204 No Content` on success.

---

## Folders (Personal)

A folder (`ApiFolder`) has shape:
`{ id, name, description, icon, color, parentFolderId, createdAt, updatedAt }`.
`parentFolderId` is `null` for top-level folders.

### GET /folders
List all personal folders (flat array; clients build the tree from `parentFolderId`).

```bash
curl -s -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  https://api.hackmd.io/v1/folders
```

### GET /folders/{folderId}
Fetch a single folder.

### POST /folders
Create a personal folder.

```bash
curl -s -X POST \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Specs","description":"Product specs","icon":"📐","color":"#FFB400","parentFolderId":"<optional-parent>"}' \
  https://api.hackmd.io/v1/folders
```

Body fields:
| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | display name |
| `description` | string | no | folder description |
| `icon` | string | no | emoji or icon code |
| `color` | string | no | hex color (e.g. `#FFB400`) |
| `parentFolderId` | string | no | nest under another folder |

### PATCH /folders/{folderId}
Update `name`, `description`, `icon`, `color`, or `parentFolderId`. All except
`name` accept `null` to clear (e.g. `{"parentFolderId":null}` moves the folder
to top level).

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Specs (archived)","color":"#888888"}' \
  https://api.hackmd.io/v1/folders/<folderId>
```

### DELETE /folders/{folderId}
Permanently delete a folder. `204 No Content` on success.

### GET /folders/folder-order
Per-user folder display order: map of `parentFolderId` (or literal `"root"`) →
ordered child folder ids.

```json
{ "root": ["folder-a","folder-b"], "folder-a": ["folder-a1"] }
```

### PUT /folders/folder-order
Replace the order map. Body: `{ "order": { ... } }`.

```bash
curl -s -X PUT \
  -H "Authorization: Bearer $HACKMD_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"order":{"root":["folder-a","folder-b"],"folder-a":["folder-a1"]}}' \
  https://api.hackmd.io/v1/folders/folder-order
```

> **Caution:** PUT replaces the entire map. Always GET first, mutate, then PUT.

---

## Folders (Team)

Team folders mirror personal folders, scoped under `/teams/{teamPath}`:

- `GET /teams/{teamPath}/folders` — list
- `GET /teams/{teamPath}/folders/{folderId}` — fetch one
- `POST /teams/{teamPath}/folders` — body identical to `POST /folders`
- `PATCH /teams/{teamPath}/folders/{folderId}` — fields identical to personal PATCH
- `DELETE /teams/{teamPath}/folders/{folderId}` — `204 No Content`
- `GET /teams/{teamPath}/folders/folder-order` / `PUT /teams/{teamPath}/folders/folder-order`
  — same body shape as personal order endpoints

---

## Status Code Reference

| Code | Meaning |
|---|---|
| 200 | Success with body |
| 201 | Created |
| 202 | Accepted — async processing (returned by `PATCH /notes/{id}` when changing `parentFolderId`). Verify with a follow-up `GET /notes/{id}` |
| 204 | Success, no body (delete operations) |
| 400 | Bad request — malformed JSON or invalid field value |
| 401 | Unauthorized — missing or invalid token |
| 403 | Forbidden — valid token but insufficient permissions |
| 404 | Not found — note ID or team path does not exist |
| 409 | Conflict — e.g. duplicate permalink |
| 429 | Rate limited — back off and retry |
| 500 | Internal server error |
