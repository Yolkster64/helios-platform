const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const target = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(target) : [target];
  });
}
for (const directory of ['main', 'shared', 'renderer', 'test']) {
  for (const file of walk(path.join(root, directory)).filter((file) => /\.(c?js)$/.test(file))) {
    execFileSync(process.execPath, ['--check', file], { stdio: 'inherit' });
  }
}
console.log('Desktop JavaScript syntax passed.');
