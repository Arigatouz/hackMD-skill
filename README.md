# @arigatouz/hackmd-skill

A **[Claude Code](https://claude.com/claude-code)** skill for managing
[HackMD](https://hackmd.io) notes, folders, images, and team workspaces — using
the official HackMD v1 REST API and the `hackmd-mcp` MCP server when available,
with a portable bash fallback.

Drop it into `~/.claude/skills/hackmd/` with one command and your Claude Code
sessions will automatically use it whenever HackMD is mentioned.

---

## Quick install

```bash
# One-shot install from npm (after publish)
npx @arigatouz/hackmd-skill

# Or directly from this GitHub repo, no npm publish required:
npx github:Arigatouz/hackMD-plugin install
```

That copies the skill into `~/.claude/skills/hackmd/`. Restart Claude Code (or
just start a new conversation) and it's live.

To uninstall:
```bash
npx @arigatouz/hackmd-skill uninstall
```

Flags:
- `--force, -f` — overwrite an existing install
- `--target, -t <path>` — install to a custom location
- `--dry-run, -n` — show what would happen without writing
- `--help, -h` — print help

---

## Prerequisites

1. **A HackMD API token.** Get one at <https://hackmd.io/settings#api> and
   export it in your shell:
   ```bash
   export HACKMD_API_TOKEN="hmd_xxx..."
   ```
   Add it to `~/.zshrc` / `~/.bashrc` so future sessions inherit it.

2. **(Recommended) The `hackmd-mcp` MCP server**, which Claude Code uses for
   the common workflows (read/create/update/delete notes, list teams,
   reading history):
   ```bash
   claude mcp add hackmd "npx -y hackmd-mcp"
   ```
   Configure the same `HACKMD_API_TOKEN` in your MCP environment.

The skill auto-detects whether the MCP server is reachable and falls back to
the bundled bash helper (`scripts/hackmd-curl.sh`) for anything the MCP
server doesn't yet expose — currently folders, folder ordering, and image
uploads.

---

## What this skill covers

| Area | MCP support | Skill workflow |
|---|---|---|
| Personal notes — list / read / create / update / delete | ✅ via `mcp__hackmd__*` | Workflows 1–5 |
| Reading history | ✅ | Workflow 6 |
| Teams — list / list notes / create / update / delete | ✅ | Workflows 7–11 |
| **Personal folders — list / create / fetch / update / delete** | ❌ curl fallback | Workflows 12–14 |
| **Move a note into a folder via `parentFolderId`** | ❌ curl fallback (MCP silently drops the field) | Workflow 15 |
| **Folder display order (sidebar reorder)** | ❌ curl fallback | Workflow 16 |
| **Image upload on a note** | ❌ curl fallback | Workflow 17 |
| **Team folders & team folder-order** | ❌ curl fallback | Workflows 12–16, team variants |

All curl-fallback paths are wrapped by `hackmd_*` shell helpers (`source
scripts/hackmd-curl.sh && hackmd_help`).

---

## What you get inside `~/.claude/skills/hackmd/`

```
SKILL.md                            # Top-level instructions Claude Code reads
references/
  api-endpoints.md                  # Full REST API reference with curl examples
  markdown-cheatsheet.md            # HackMD-specific markdown extensions
  permissions-guide.md              # Permission levels & best practices
scripts/
  hackmd-curl.sh                    # Bash fallback CLI (POSIX + macOS-portable)
```

### `scripts/hackmd-curl.sh` highlights

Source it and call `hackmd_help` for the full menu. Notable helpers:

| Helper | Purpose |
|---|---|
| `hackmd_create_note_in_folder <title> <folderId> [content_file]` | POST + PATCH in one call (the API silently drops `parentFolderId` on POST, so a single create is impossible) |
| `hackmd_reorder_folder_children <parentIdOrRoot> <id1> [id2 ...]` | **Safe** merge — fetches the order map, replaces only the entry for that parent, and PUTs back. Avoids wiping unrelated keys |
| `hackmd_check_folder_cycle <folderId> <newParentId>` | Walks `parentFolderId` ancestors locally and refuses a move that would create a cycle (the API has no documented cycle prevention) |
| `hackmd_count_folder_children <folderId> [--skip-notes]` | Counts subfolders + (optionally) notes. Notes are O(N) reads because `GET /notes` summaries omit folder info |
| `hackmd_delete_folder <folderId>` | Previews subfolder count, then prompts for `yes` before issuing `DELETE` |
| `hackmd_get_note_folder_path <noteId>` | Pretty-prints the note's folder ancestry from `folderPaths` |
| `hackmd_upload_note_image <noteId> <path>` | Multipart upload with a 5 MB soft-warning + a `413` recovery hint |

Team variants exist for every folder helper (`hackmd_*_team_*`).

---

## Verified-against-live-API quirks

The HackMD OpenAPI spec is partially incorrect. The skill documents the
**empirically verified** behavior so Claude Code doesn't follow broken
assumptions:

| What the spec implies | What actually happens |
|---|---|
| `POST /notes` accepts `parentFolderId` | **Silently dropped.** Always POST then PATCH. Use `hackmd_create_note_in_folder` |
| `PATCH /notes/{id}` returns `200` | Returns **`202 Accepted`** (async). Read back to confirm |
| Note responses carry a scalar `parentFolderId` | Read field is **`folderPaths`** — array of ancestor folder objects |
| `GET /notes` summaries are filterable by folder | Summaries **omit folder info entirely** |
| `PATCH /folders/{id}` works regardless of name | Returns **`500`** when the folder's current name contains `/`. Workaround: rename to a slash-free name, PATCH, rename back |
| MCP `update_note` accepts any update field | Only `content`, `readPermission`, `writePermission`, `permalink` — drops `title`, `tags`, `description`, `parentFolderId`, etc. |
| `head -n -1` works in the bash helper | GNU-only. Helper uses portable `sed '$d'` instead |

These quirks are also called out inline in `SKILL.md` and
`references/api-endpoints.md`.

---

## Manual install (if you don't want npx)

```bash
git clone https://github.com/Arigatouz/hackMD-plugin
mkdir -p ~/.claude/skills/hackmd
cp -R hackMD-plugin/skill/. ~/.claude/skills/hackmd/
chmod +x ~/.claude/skills/hackmd/scripts/hackmd-curl.sh
```

---

## Using the bash fallback standalone (no Claude Code)

```bash
export HACKMD_API_TOKEN="hmd_xxx..."
source ~/.claude/skills/hackmd/scripts/hackmd-curl.sh
hackmd_help                                            # menu
hackmd_get_user_info                                   # auth check
hackmd_create_folder "Specs" "" "" "#FFB400" "Product specs"
hackmd_create_note_in_folder "Sprint Retro" <folderId> ./retro.md
hackmd_get_note_folder_path <noteId>
```

The script is POSIX-compliant on macOS/BSD and Linux. It requires `curl`,
`python3`, and `bash >= 4`.

---

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

Bumping the skill:
1. Edit files under `skill/`.
2. Bump the version in `package.json` (semver).
3. Tag and publish: `npm version <patch|minor|major> && npm publish --access public`.

Local end-to-end test of the installer:
```bash
node bin/install.js install --target /tmp/_hackmd-skill-test --force
ls /tmp/_hackmd-skill-test
node bin/install.js uninstall --target /tmp/_hackmd-skill-test
```

---

## License

MIT — see [LICENSE](./LICENSE).
