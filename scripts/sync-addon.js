#!/usr/bin/env node
// Copies the DhoxarModules addon into the game's AddOns folder so a /reload
// in game picks up the latest code.
//
//   node scripts/sync-addon.js          sync now
//   node scripts/sync-addon.js --hook   Claude Code PostToolUse hook mode:
//                                       reads the tool call from stdin and
//                                       syncs only if it touched the addon
//
// The destination is mirrored: files removed from the repo are removed from
// the game folder too. Only the DhoxarModules folder inside AddOns is ever
// touched. Set WOW_ADDONS_DIR to target a different AddOns folder.

const fs = require('fs');
const path = require('path');

const ADDON = 'DhoxarModules';
const DEFAULT_ADDONS_DIR = 'C:\\Program Files (x86)\\World of Warcraft\\_forever_\\Interface\\AddOns';

const source = path.resolve(__dirname, '..', ADDON);
const addonsDir = process.env.WOW_ADDONS_DIR || DEFAULT_ADDONS_DIR;
const dest = path.join(addonsDir, ADDON);

function isInside(file, dir) {
  const rel = path.relative(dir, path.resolve(file));
  return rel !== '' && !rel.startsWith('..') && !path.isAbsolute(rel);
}

function countFiles(dir) {
  let n = 0;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    n += entry.isDirectory() ? countFiles(path.join(dir, entry.name)) : 1;
  }
  return n;
}

function sync() {
  if (!fs.existsSync(source)) throw new Error('addon source not found: ' + source);
  if (!fs.existsSync(addonsDir)) throw new Error('AddOns folder not found: ' + addonsDir);
  fs.rmSync(dest, { recursive: true, force: true });
  fs.cpSync(source, dest, { recursive: true });
  return countFiles(dest);
}

function main() {
  const hookMode = process.argv.includes('--hook');

  if (hookMode) {
    let input = {};
    try {
      input = JSON.parse(fs.readFileSync(0, 'utf8'));
    } catch (e) {
      return; // no usable payload: nothing to do
    }
    const file = (input.tool_response && input.tool_response.filePath)
      || (input.tool_input && input.tool_input.file_path);
    if (!file || !isInside(file, source)) return;
  }

  try {
    const n = sync();
    const message = `Synced ${ADDON} (${n} files) to ${dest}`;
    console.log(hookMode ? JSON.stringify({ systemMessage: message + ' - /reload in game.' }) : message);
  } catch (e) {
    const message = `${ADDON} sync failed: ${e.message}`;
    if (hookMode) {
      // Report without failing the edit that triggered the hook.
      console.log(JSON.stringify({ systemMessage: message }));
    } else {
      console.error(message);
      process.exitCode = 1;
    }
  }
}

main();
