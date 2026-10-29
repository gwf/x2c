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
  await writeFile(join(directory, 'docker'), `#!/bin/sh\nprintf '%s\\n' "$*" >> '${log}'\nif [ "$1" = rm ]; then [ ! -f "$FAKE_REMOVE_FAIL" ] || exit 1; sleep 0.1; exit 0; fi\nif [ "$1" = ps ]; then printf existing; exit 0; fi\nif [ "$1" = create ]; then sleep 0.1; exit 0; fi\ncat >/dev/null\nif [ "$FAKE_EARLY_EXIT" = yes ]; then sleep 0.15; exit 1; fi\nif [ "$FAKE_OUTPUT" = yes ]; then head -c 9000000 /dev/zero; exec sleep 10; fi\nif [ "$FAKE_TIMEOUT" = yes ]; then exec sleep 10; fi\nprintf '%s' '{"loader":"export default 1","wasm":"AA=="}'\n`, { mode: 0o755 });
  process.env.PATH = `${directory}:${oldPath}`;
  t.after(async () => { process.env.PATH = oldPath; delete process.env.FAKE_TIMEOUT; delete process.env.FAKE_OUTPUT; delete process.env.FAKE_REMOVE_FAIL; delete process.env.FAKE_EARLY_EXIT; await rm(directory, { recursive: true }); });
  assert.deepEqual(await compileInContainer('source'), { loader: 'export default 1', wasm: 'AA==' });
  const args = await readFile(log, 'utf8');
  for (const flag of ['--network=none', '--read-only', '--user=65534:65534', '--memory=512m', '--pids-limit=64', '--cap-drop=ALL', '--tmpfs=/tmp:rw,exec,nosuid,nodev,size=128m,mode=1777'])
    assert.ok(args.includes(flag), flag);
  process.env.FAKE_OUTPUT = 'yes';
  await assert.rejects(compileInContainer('source'), error => error.status === 422);
  delete process.env.FAKE_OUTPUT;
  process.env.FAKE_TIMEOUT = 'yes';
  await assert.rejects(compileInContainer('source', { timeout: 150 }), error => error.status === 504);
  await new Promise(resolve => setTimeout(resolve, 30));
  assert.match(await readFile(log, 'utf8'), /rm -f x2c-playground-/);
  const runningAbort = new AbortController();
  let settled = false;
  const running = compileInContainer('source', { signal: runningAbort.signal }).finally(() => { settled = true; });
  const runningRejected = assert.rejects(running, { name: 'AbortError' });
  const starts = args => args.split('\n').filter(line => line.startsWith('start ')).length;
  const previousStarts = starts(await readFile(log, 'utf8'));
  for (let i = 0; i < 100 && starts(await readFile(log, 'utf8')) === previousStarts; i++)
    await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal(starts(await readFile(log, 'utf8')), previousStarts + 1);
  runningAbort.abort();
  await new Promise(resolve => setTimeout(resolve, 30));
  assert.equal(settled, false, 'must await container removal and client close');
  await runningRejected;
  const abort = new AbortController();
  const cancelled = compileInContainer('source', { signal: abort.signal });
  const rejected = assert.rejects(cancelled, { name: 'AbortError' });
  abort.abort();
  await rejected;
  const lifecycle = (await readFile(log, 'utf8')).trim().split('\n');
  assert.match(lifecycle.at(-2), /^create /);
  assert.match(lifecycle.at(-1), /^rm -f /);
  assert.equal(lifecycle.at(-2).match(/--name ([^ ]+)/)[1], lifecycle.at(-1).split(' ').at(-1));
  const failRemoval = join(directory, 'fail-removal');
  await writeFile(failRemoval, '');
  process.env.FAKE_REMOVE_FAIL = failRemoval;
  process.env.FAKE_EARLY_EXIT = 'yes';
  const failedAbort = new AbortController();
  let cleanupSettled = false;
  const cleanup = compileInContainer('source', { signal: failedAbort.signal }).finally(() => { cleanupSettled = true; });
  const cleanupRejected = assert.rejects(cleanup, { name: 'AbortError' });
  const beforeStarts = starts(await readFile(log, 'utf8'));
  for (let i = 0; i < 100 && starts(await readFile(log, 'utf8')) === beforeStarts; i++)
    await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal(starts(await readFile(log, 'utf8')), beforeStarts + 1);
  failedAbort.abort();
  await new Promise(resolve => setTimeout(resolve, 250));
  assert.equal(cleanupSettled, false, 'failed removal must hold the slot after client closure');
  await rm(failRemoval);
  await cleanupRejected;
});

test('cancels only the disconnected compilation and holds its slot through cleanup', async t => {
  const calls = [];
  const app = await fixture(t, (source, { signal } = {}) => new Promise((resolve, reject) => {
    const call = { source, signal, resolve, reject };
    calls.push(call);
  }));
  const waitFor = async predicate => {
    for (let i = 0; i < 100; i++) {
      if (predicate()) return;
      await new Promise(resolve => setTimeout(resolve, 5));
    }
    assert.fail('condition did not become true');
  };
  const abort = new AbortController();
  const first = app.request('first', { signal: abort.signal });
  const firstRejected = assert.rejects(first, { name: 'AbortError' });
  await waitFor(() => calls.length === 1);
  app.advance();
  const second = app.request('second');
  await waitFor(() => calls.length === 2);
  abort.abort();
  await firstRejected;
  await waitFor(() => calls[0].signal?.aborted);
  assert.equal(calls[1].signal.aborted, false);
  app.advance();
  assert.equal((await app.request('before cleanup')).status, 503);
  calls[0].reject(calls[0].signal.reason);
  await new Promise(resolve => setTimeout(resolve, 10));
  app.advance();
  const third = app.request('after cleanup');
  await waitFor(() => calls.length === 3);
  calls[1].resolve({ loader: 'second', wasm: '' });
  calls[2].resolve({ loader: 'third', wasm: '' });
  assert.equal((await second).status, 200);
  assert.equal((await third).status, 200);
});
