#!/usr/bin/env node
/**
 * Installer for the @arigatouz/hackmd-skill Claude Code skill.
 *
 * Usage:
 *   npx @arigatouz/hackmd-skill            # install (default)
 *   npx @arigatouz/hackmd-skill install    # install
 *   npx @arigatouz/hackmd-skill uninstall  # remove
 *   npx @arigatouz/hackmd-skill --dry-run  # show what would happen
 *   npx @arigatouz/hackmd-skill --force    # overwrite an existing install
 *   npx @arigatouz/hackmd-skill --target ~/.claude/skills/hackmd  # custom path
 */
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const SKILL_NAME = 'hackmd';
const DEFAULT_TARGET = path.join(os.homedir(), '.claude', 'skills', SKILL_NAME);
const SOURCE_DIR = path.resolve(__dirname, '..', 'skill');

function parseArgs(argv) {
  const args = { command: 'install', dryRun: false, force: false, target: DEFAULT_TARGET };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === 'install' || a === 'uninstall') args.command = a;
    else if (a === '--dry-run' || a === '-n') args.dryRun = true;
    else if (a === '--force' || a === '-f') args.force = true;
    else if (a === '--target' || a === '-t') args.target = path.resolve(argv[++i]);
    else if (a === '--help' || a === '-h') {
      printHelp();
      process.exit(0);
    } else if (a.startsWith('-')) {
      console.error(`Unknown flag: ${a}`);
      printHelp();
      process.exit(2);
    }
  }
  return args;
}

function printHelp() {
  console.log(`@arigatouz/hackmd-skill — installer

Usage:
  npx @arigatouz/hackmd-skill [command] [flags]

Commands:
  install      Copy the skill into ~/.claude/skills/hackmd (default)
  uninstall    Remove ~/.claude/skills/hackmd

Flags:
  --dry-run, -n           Show what would happen without writing
  --force,   -f           Overwrite an existing install
  --target,  -t <path>    Install to a custom path
  --help,    -h           Print this help

Examples:
  npx @arigatouz/hackmd-skill
  npx @arigatouz/hackmd-skill install --force
  npx github:Arigatouz/hackMD-plugin install
`);
}

function copyDir(src, dest, dryRun) {
  if (!dryRun) fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name);
    const d = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(s, d, dryRun);
    } else if (entry.isFile()) {
      if (dryRun) {
        console.log(`  would copy  ${s} -> ${d}`);
      } else {
        fs.copyFileSync(s, d);
        // Preserve executable bit for *.sh
        if (entry.name.endsWith('.sh')) {
          fs.chmodSync(d, 0o755);
        }
      }
    }
  }
}

function removeDir(p, dryRun) {
  if (!fs.existsSync(p)) return false;
  if (dryRun) {
    console.log(`  would remove  ${p}`);
    return true;
  }
  fs.rmSync(p, { recursive: true, force: true });
  return true;
}

function install({ target, dryRun, force }) {
  if (!fs.existsSync(SOURCE_DIR)) {
    console.error(`ERROR: source skill directory not found: ${SOURCE_DIR}`);
    process.exit(1);
  }
  const exists = fs.existsSync(target);
  if (exists && !force) {
    console.error(`ERROR: target already exists: ${target}`);
    console.error(`Re-run with --force to overwrite, or --target <other-path>.`);
    process.exit(1);
  }
  if (exists && force) {
    console.log(`Removing existing install at ${target} ...`);
    if (!dryRun) fs.rmSync(target, { recursive: true, force: true });
  }
  console.log(`Installing hackmd skill -> ${target}`);
  copyDir(SOURCE_DIR, target, dryRun);
  if (dryRun) {
    console.log('\nDry run only — no files were written.');
    return;
  }
  console.log('\nDone.');
  console.log('\nNext steps:');
  console.log('  1. Make sure HACKMD_API_TOKEN is set in your shell or MCP config.');
  console.log('     Get a token at https://hackmd.io/settings#api');
  console.log('  2. (Optional) Install the hackmd MCP server for richer integration:');
  console.log('       claude mcp add hackmd "npx -y hackmd-mcp"');
  console.log('     The skill auto-detects MCP and falls back to scripts/hackmd-curl.sh when needed.');
  console.log('  3. In Claude Code, the skill activates automatically when HackMD is mentioned.');
}

function uninstall({ target, dryRun }) {
  console.log(`Uninstalling hackmd skill from ${target}`);
  const removed = removeDir(target, dryRun);
  if (!removed) {
    console.log('Nothing to remove.');
    return;
  }
  if (!dryRun) console.log('Done.');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  switch (args.command) {
    case 'install':
      install(args);
      break;
    case 'uninstall':
      uninstall(args);
      break;
    default:
      printHelp();
      process.exit(2);
  }
}

main();
