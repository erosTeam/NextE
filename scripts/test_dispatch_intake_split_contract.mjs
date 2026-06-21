#!/usr/bin/env node

import fs from 'fs';
import path from 'path';

const root = process.cwd();
const indexPath = path.join(root, 'docs/plans/active/product-bug-intake.md');
const dispatchPath = path.join(root, 'docs/plans/active/current-dispatch-state.md');
const intakeDir = path.join(root, 'docs/plans/active/intake');

const expectedFiles = [
  'downloads.md',
  'favorites.md',
  'gallery-detail-comments.md',
  'gallery-list-grid.md',
  'history-archive.md',
  'reader.md',
  'search.md',
  'settings.md',
  'write-operations.md',
];

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function lineCount(text) {
  return text.split(/\n/).length;
}

function headerCount(text) {
  const matches = text.match(/^### /gm);
  return matches === null ? 0 : matches.length;
}

const index = read(indexPath);
const dispatch = read(dispatchPath);

assert(lineCount(index) <= 180, 'product-bug-intake.md must remain a short index, not a long evidence ledger');
assert(headerCount(index) === 0, 'product-bug-intake.md must not contain domain item sections');
assert(index.includes('## Domain Intake Files'), 'product-bug-intake.md must list domain intake files');
assert(index.includes('current-dispatch-state.md'), 'product-bug-intake.md must point scheduling to current-dispatch-state.md');
assert(dispatch.includes('short intake index and writing-rule file'),
  'current-dispatch-state.md must describe product-bug-intake.md as an index, not an evidence ledger');
assert(lineCount(dispatch) <= 220, 'current-dispatch-state.md must remain a short dispatch entry file');
assert(dispatch.includes('docs(dispatch): split active intake by domain') === false,
  'completed docs split lane must not remain active in current-dispatch-state.md');
assert(!/## Active Queue[\s\S]*Settings shell audit/.test(dispatch),
  'implemented Settings shell audit must not remain active in current-dispatch-state.md');
assert(dispatch.includes('Settings shell audit is implemented and pending controller acceptance'),
  'current-dispatch-state.md must record Settings shell audit as implemented, not active');

let totalItems = 0;
for (const fileName of expectedFiles) {
  const filePath = path.join(intakeDir, fileName);
  assert(fs.existsSync(filePath), `missing domain intake file: ${fileName}`);
  const text = read(filePath);
  assert(text.includes('Status: domain intake ledger.'), `${fileName} must declare domain intake status`);
  assert(text.includes('../current-dispatch-state.md'), `${fileName} must point readers back to dispatch state`);
  totalItems += headerCount(text);
}

assert(totalItems === 75, `domain intake split must preserve 75 intake items, found ${totalItems}`);

console.log('✓ dispatch intake split contract: index short, domain files present, 75 items preserved');
