import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer, CompileError, validateSource } from './server.mjs';

async function fixture(t, compile) {
  let time = 10000;
  const server = createServer({ compile, origins: ['https://example.test'], now: () => time });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  return {
    request: (body, options = {}) => fetch(`http://127.0.0.1:${server.address().port}/compile`, {
      method: 'POST', body, ...options,
    }),
    advance: () => { time += 5001; },
  };
}

test('literal includes reject process, absolute and parent paths', () => {
  for (const path of ['process.x', 'lib/process.x', '/etc/passwd', '../private.x', 'C:\\file.x']) {
    assert.throws(() => validateSource(`# include "${path}"`), CompileError);
  }
  assert.throws(() => validateSource('#include \\\n"process.x"'), CompileError);
  assert.throws(() => validateSource('#include /*comment*/ "process.x"'), CompileError);
  assert.throws(() => validateSource('#include HEADER'), CompileError);
  validateSource('#include "array.x"\nint main() { return 0; }');
});

test('returns compiler artifacts, enforces rate limit and reuses source cache', async t => {
  let calls = 0;
  const fixtureData = { loader: 'export default function() {}', wasm: 'AGFzbQ==' };
  const app = await fixture(t, async source => { calls++; assert.equal(source, 'hello'); return fixtureData; });
  let response = await app.request('hello', { headers: { Origin: 'https://example.test' } });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('access-control-allow-origin'), 'https://example.test');
  assert.deepEqual(await response.json(), fixtureData);
  response = await app.request('hello');
  assert.equal(response.status, 429);
  assert.equal(response.headers.get('retry-after'), '5');
  app.advance();
  assert.equal((await app.request('hello')).status, 200);
  assert.equal(calls, 1);
});

test('rejects large source and disallowed origins without compiling', async t => {
  const app = await fixture(t, () => assert.fail('must not compile'));
  assert.equal((await app.request('hello', { headers: { Origin: 'https://bad.test' } })).status, 403);
  const response = await app.request('x'.repeat(65537));
  assert.equal(response.status, 413);
  assert.match((await response.json()).error, /64 KB/);
});

test('preserves translation diagnostics and timeout response', async t => {
  const app = await fixture(t, async () => { throw new CompileError(422, 'program.x: expected expression'); });
  const response = await app.request('bad source');
  assert.equal(response.status, 422);
  assert.deepEqual(await response.json(), { error: 'program.x: expected expression' });
  const timeout = await fixture(t, async () => { throw new CompileError(504, 'Compilation exceeded 20 seconds.'); });
  assert.equal((await timeout.request('loop')).status, 504);
});

test('handles browser preflight without consuming compile allowance', async t => {
  const app = await fixture(t, async () => ({ loader: '', wasm: '' }));
  const response = await app.request(undefined, { method: 'OPTIONS', headers: { Origin: 'https://example.test' } });
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('access-control-allow-methods'), 'POST');
  assert.equal((await app.request('source')).status, 200);
});

test('container runner supplies isolation flags and removes timed-out containers', async t => {
  const { mkdtemp, writeFile, readFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const { compileInContainer } = await import('./server.mjs');
  const directory = await mkdtemp(join(tmpdir(), 'playground-runner-'));
  const oldPath = process.env.PATH;
  const log = join(directory, 'args');
  await writeFile(join(directory, 'docker'), `#!/bin/sh\nprintf '%s\\n' "$*" >> '${log}'\nif [ "$1" = rm ]; then exit 0; fi\ncat >/dev/null\nif [ "$FAKE_TIMEOUT" = yes ]; then exec sleep 10; fi\nprintf '%s' '{"loader":"export default 1","wasm":"AA=="}'\n`, { mode: 0o755 });
  process.env.PATH = `${directory}:${oldPath}`;
  t.after(async () => { process.env.PATH = oldPath; delete process.env.FAKE_TIMEOUT; await rm(directory, { recursive: true }); });
  assert.deepEqual(await compileInContainer('source'), { loader: 'export default 1', wasm: 'AA==' });
  const args = await readFile(log, 'utf8');
  for (const flag of ['--network=none', '--read-only', '--user=65534:65534', '--memory=512m', '--pids-limit=64', '--cap-drop=ALL', '--tmpfs=/tmp:rw,exec,nosuid,nodev,size=128m,mode=1777'])
    assert.ok(args.includes(flag), flag);
  process.env.FAKE_TIMEOUT = 'yes';
  await assert.rejects(compileInContainer('source', { timeout: 30 }), error => error.status === 504);
  await new Promise(resolve => setTimeout(resolve, 30));
  assert.match(await readFile(log, 'utf8'), /rm -f x2c-playground-/);
});
