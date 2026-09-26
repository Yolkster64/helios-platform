import { createRequire } from 'node:module';
import { mkdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const require = createRequire(import.meta.url);
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = join(root, 'build', 'Release', 'particle_field.node');
mkdirSync(dirname(output), { recursive: true });

let command;
let args;
if (process.platform === 'win32') {
  command = process.execPath;
  args = [require.resolve('node-gyp/bin/node-gyp.js'), 'rebuild'];
} else if (process.platform === 'linux' || process.platform === 'darwin') {
  // Raw Node-API needs only public headers, not V8 headers or libnode. This
  // avoids downloading a full Node source distribution for the POSIX build.
  const headerRoot = process.env.NODE_INCLUDE_DIR ||
    join(dirname(require.resolve('node-api-headers/package.json')), 'include');
  if (!existsSync(join(headerRoot, 'node_api.h'))) {
    throw new Error(`node_api.h was not found in ${headerRoot}`);
  }
  command = process.env.CXX || 'c++';
  args = ['-std=c++17', '-O2', '-Wall', '-Wextra', '-Werror', '-DNAPI_VERSION=8',
    '-DNODE_GYP_MODULE_NAME=particle_field', '-I', headerRoot,
    '-shared', '-fPIC', join(root, 'src', 'particle_field.cc'), '-o', output];
  if (process.platform === 'darwin') args.push('-undefined', 'dynamic_lookup');
} else {
  throw new Error(`Unsupported native build platform: ${process.platform}`);
}

const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', shell: false });
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
console.log(`Built ${output}`);
