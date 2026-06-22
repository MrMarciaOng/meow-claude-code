#!/usr/bin/env node
'use strict';

// Thin launcher so `npx meow-claude-code [args]` (or a global `meow` install)
// runs the bash tool. All real logic lives in ../meow.sh.
const { spawnSync } = require('child_process');
const path = require('path');

const script = path.join(__dirname, '..', 'meow.sh');
const result = spawnSync('bash', [script, ...process.argv.slice(2)], {
  stdio: 'inherit',
});

if (result.error) {
  const msg =
    result.error.code === 'ENOENT'
      ? 'meow: this tool needs bash on macOS or Linux (bash was not found).'
      : `meow: ${result.error.message}`;
  console.error(msg);
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
