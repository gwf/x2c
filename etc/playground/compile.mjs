// This process runs inside a fresh, restricted container for one request.
import { readFile, writeFile, mkdtemp } from 'node:fs/promises';
import { spawn } from 'node:child_process';

const directory = await mkdtemp('/tmp/playground-');
let source = '';
for await (const chunk of process.stdin) source += chunk;
await writeFile(`${directory}/program.x`, source);
const child = spawn('/opt/x2c/tools/wasm-build', [`${directory}/program.x`, `${directory}/program`], {
  cwd: directory, stdio: ['ignore', 'ignore', 'pipe'],
  env: { ...process.env, HOME: directory, WASM_LDFLAGS: '--embed-file /opt/x2c/examples/data/power-exceptions@examples/data/power-exceptions' },
});
child.stderr.pipe(process.stderr);
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('close', async code => {
  if (code !== 0) { process.exitCode = 1; return; }
  const loader = await readFile(`${directory}/program.js`, 'utf8');
  const wasm = (await readFile(`${directory}/program.wasm`)).toString('base64');
  process.stdout.write(JSON.stringify({ loader, wasm }));
});
