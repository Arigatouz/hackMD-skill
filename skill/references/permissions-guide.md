# HackMD Permissions Guide

---

## Permission Axes

HackMD notes have three independent permission controls:

### `readPermission`

| Value | Who can read |
|---|---|
| `owner` | Only the note owner (or team members for team notes) |
| `signed_in` | Any logged-in HackMD user |
| `guest` | Anyone with the link, including unauthenticated users |

### `writePermission`

| Value | Who can edit |
|---|---|
| `owner` | Only the note owner (or team members for team notes) |
| `signed_in` | Any logged-in HackMD user |
| `guest` | Anyone with the link, including unauthenticated users |

> `writePermission` cannot be more permissive than `readPermission`.
> e.g., you cannot set `readPermission: "owner"` with `writePermission: "guest"`.

### `commentPermission`

| Value | Who can comment |
|---|---|
| `disabled` | Comments are turned off |
| `forbidden` | Commenting UI is hidden |
| `owners` | Only the owner |
| `signed_in_users` | Any logged-in HackMD user |
| `everyone` | Anyone (including unauthenticated) |

---

## Named Presets

### 1. Private Draft
Personal scratchpad. Only the owner can read or write.

```json
{
  "readPermission": "owner",
  "writePermission": "owner",
  "commentPermission": "disabled"
}
```

**Use when:** drafting content that is not ready to share, storing sensitive notes.

---

### 2. Internal Team Note
Readable and editable by any logged-in HackMD user, no public access.

```json
{
  "readPermission": "signed_in",
  "writePermission": "signed_in",
  "commentPermission": "signed_in_users"
}
```

**Use when:** collaborating with team members who all have HackMD accounts,
internal meeting notes, team ADRs.

---

### 3. Collaborative Pad
Open for anyone with the link to read; only logged-in users can edit and comment.

```json
{
  "readPermission": "guest",
  "writePermission": "signed_in",
  "commentPermission": "signed_in_users"
}
```

**Use when:** workshop pads, event notes where attendees may not all have accounts
but you want editing restricted to known users.

---

### 4. Public Read-Only
Published article. Anyone can read, only the owner can edit.

```json
{
  "readPermission": "guest",
  "writePermission": "owner",
  "commentPermission": "everyone"
}
```

**Use when:** publishing blog-style posts, sharing documentation publicly,
public retrospective summaries.

---

### 5. Public Collaborative Pad
Fully open. Anyone can read, write, and comment without logging in.

```json
{
  "readPermission": "guest",
  "writePermission": "guest",
  "commentPermission": "everyone"
}
```

**Use when:** public hackathon pads, community event notes, open source project
discussion boards. Use with caution; anonymous edits are possible.

---

## Team Notes

Team notes are created within a team workspace (`teamPath`). Permissions still
apply but are interpreted relative to team membership:

- `readPermission: "owner"` → only team members can read
- `readPermission: "signed_in"` → any logged-in HackMD user can read
- `readPermission: "guest"` → anyone with the link can read

Recommended default for team notes: Internal Team Note preset
(`signed_in` / `signed_in` / `signed_in_users`).

---

## Permalink Field

The optional `permalink` field sets a custom URL slug for the note:

```json
{
  "permalink": "sprint-42-retro"
}
```

Results in: `https://hackmd.io/@userPath/sprint-42-retro`

- Must be unique within your account (or team)
- Only alphanumeric characters, hyphens, and underscores
- Returns `409 Conflict` if the slug is already taken
- Once set, changing it creates a new URL (old links break unless HackMD redirects them)
