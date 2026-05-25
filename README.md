# @arigatouz/hackmd-skill

A [Claude Code](https://claude.com/claude-code) skill for managing [HackMD](https://hackmd.io) notes, folders, images, and team workspaces via the HackMD v1 REST API.

One command drops it into `~/.claude/skills/hackmd/`. Claude Code picks it up automatically in any session where HackMD comes up.

## Quick install

```bash
npx @arigatouz/hackmd-skill
```

That copies the skill into `~/.claude/skills/hackmd/`. Start a new Claude Code conversation and it's live.

To uninstall:
```bash
npx @arigatouz/hackmd-skill uninstall
```

Flags:
- `--force, -f`: overwrite an existing install
- `--target, -t <path>`: install to a custom location
- `--dry-run, -n`: show what would happen without writing
- `--help, -h`: print help

## API reference

Full Swagger docs: <https://api.hackmd.io/v1/docs>

## Prerequisites

1. **A HackMD API token.** Get one at <https://hackmd.io/settings#api> and export it:
   ```bash
   export HACKMD_API_TOKEN="hmd_xxx..."
   ```
   Add it to `~/.zshrc` or `~/.bashrc` so it carries across sessions.

2. **(Recommended) The `hackmd-mcp` MCP server** for note CRUD, teams, and reading history:
   ```bash
   claude mcp add hackmd "npx -y hackmd-mcp"
   ```
   Set the same `HACKMD_API_TOKEN` in your MCP environment.

The skill auto-detects whether the MCP server is available. For folders, folder ordering, and image uploads (which the MCP server does not expose), it automatically uses the bundled `hackmd-curl.sh` helper instead.

## What this skill covers

Everything in the table below works. The "How" column shows whether Claude uses MCP tools or the curl helper under the hood. You don't need to think about it.

| Area | How | Workflows |
|---|---|---|
| Personal notes (list, read, create, update, delete) | MCP tools | 1–5 |
| Reading history | MCP tools | 6 |
| Teams (list, list notes, create, update, delete) | MCP tools | 7–11 |
| Personal folders (list, create, fetch, update, delete) | curl helper | 12–14 |
| Move a note into a folder | curl helper (MCP silently drops `parentFolderId`) | 15 |
| Folder display order (sidebar reorder) | curl helper | 16 |
| Image upload on a note | curl helper | 17 |
| Team folders and team folder-order | curl helper | 12–16, team variants |

## What you get inside `~/.claude/skills/hackmd/`

```
SKILL.md                            # Instructions Claude Code reads
references/
  api-endpoints.md                  # Full REST API reference with curl examples
  markdown-cheatsheet.md            # HackMD-specific markdown extensions
  permissions-guide.md              # Permission levels and best practices
scripts/
  hackmd-curl.sh                    # Bash helper for folder and image operations
```

### `scripts/hackmd-curl.sh` highlights

Source it and run `hackmd_help` for the full menu. Key helpers:

| Helper | What it does |
|---|---|
| `hackmd_create_note_in_folder <title> <folderId> [content_file]` | POST + PATCH in one call (single POST can't set a folder; the API silently ignores `parentFolderId` on create) |
| `hackmd_reorder_folder_children <parentIdOrRoot> <id1> [id2 ...]` | Safe merge: fetches the current order, updates only the target parent's entry, and writes it back without touching other keys |
| `hackmd_check_folder_cycle <folderId> <newParentId>` | Walks `parentFolderId` ancestors client-side and refuses a move that would create a cycle |
| `hackmd_count_folder_children <folderId> [--skip-notes]` | Counts subfolders and optionally notes. Notes require individual fetches since list summaries omit folder info |
| `hackmd_delete_folder <folderId>` | Shows subfolder count first, then requires `yes` confirmation before deleting |
| `hackmd_get_note_folder_path <noteId>` | Prints the note's full folder path from `folderPaths` |
| `hackmd_upload_note_image <noteId> <path>` | Multipart upload with a 5 MB size warning and a `413` recovery hint |

Team variants exist for every folder helper (`hackmd_*_team_*`).

## Live API behavior that differs from the spec

The HackMD OpenAPI spec has a few gaps. These are the ones that matter:

| What the spec says | What actually happens |
|---|---|
| `POST /notes` accepts `parentFolderId` | Silently ignored. Always POST then PATCH. Use `hackmd_create_note_in_folder` |
| `PATCH /notes/{id}` returns `200` | Returns `202 Accepted` (async). Read back to confirm the change landed |
| Note responses include a scalar `parentFolderId` | Folder membership comes back as `folderPaths`, an array of ancestor objects |
| `GET /notes` summaries include folder info | Folder info is omitted entirely from list responses |
| `PATCH /folders/{id}` works for any folder | Returns `500` if the folder name contains `/`. Rename it first, patch, then rename back |
| MCP `update_note` accepts any field | Only `content`, `readPermission`, `writePermission`, `permalink`, and silently drops `title`, `tags`, `description`, `parentFolderId` |
| `head -n -1` works in the bash helper | GNU-only. The helper uses `sed '$d'` instead |

These quirks are also documented inline in `SKILL.md` and `references/api-endpoints.md`.

## Manual install

```bash
git clone https://github.com/Arigatouz/hackMD-plugin
mkdir -p ~/.claude/skills/hackmd
cp -R hackMD-plugin/skill/. ~/.claude/skills/hackmd/
chmod +x ~/.claude/skills/hackmd/scripts/hackmd-curl.sh
```

## Using the curl helper standalone (no Claude Code)

```bash
export HACKMD_API_TOKEN="hmd_xxx..."
source ~/.claude/skills/hackmd/scripts/hackmd-curl.sh
hackmd_help                                            # menu
hackmd_get_user_info                                   # auth check
hackmd_create_folder "Specs" "" "" "#FFB400" "Product specs"
hackmd_create_note_in_folder "Sprint Retro awsome HackMD" <folderId> ./retro-Hackmd.md
hackmd_get_note_folder_path <noteId>
```

Requires `curl`, `python3`, and `bash >= 4`. Works on macOS, Linux, and WSL.

## Development

```
hackMD-plugin/
├── README.md
├── LICENSE
├── package.json
├── bin/
│   └── install.js          # npx-runnable installer
└── skill/                  # mirrors ~/.claude/skills/hackmd/ exactly
    ├── SKILL.md
    ├── references/
    └── scripts/
```

## License

MIT. See [LICENSE](./LICENSE).
