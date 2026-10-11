const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { Registry } = require('vscode-textmate');
const onig = require('vscode-oniguruma');

const root = path.resolve(__dirname, '../../..');
const sourceGrammar = fs.readFileSync(path.join(root, 'etc/syntax/grammar.x'), 'utf8');
const grammarData = JSON.parse(fs.readFileSync(path.join(__dirname,
  '../syntaxes/x2c.tmLanguage.json'), 'utf8'));
const onigLib = onig.loadWASM(fs.readFileSync(require.resolve('vscode-oniguruma/release/onig.wasm')))
  .then(() => ({
    createOnigScanner: patterns => new onig.OnigScanner(patterns),
    createOnigString: value => new onig.OnigString(value)
  }));
const registry = new Registry({ onigLib, loadGrammar: async () => grammarData });
const grammar = registry.loadGrammar('source.x2c');

function kinds(rule) {
  const body = sourceGrammar.split(`(rule ${rule}\n`)[1].split('\n    (rule ')[0];
  return [...body.matchAll(/\(token "([A-Za-z]+)"\)/g)].map(match => match[1]);
}
async function check(line, word, scope, present = true, offset) {
  const tokens = (await grammar).tokenizeLine(line).tokens;
  const start = offset ?? line.indexOf(word);
  assert.ok(start >= 0);
  for (let at = start; at < start + word.length; at++) {
    const token = tokens.find(token => token.startIndex <= at && at < token.endIndex);
    assert.equal(token.scopes.includes(scope), present,
      `${line}: ${word}: ${token.scopes.join(' ')}`);
  }
}
const typeScope = 'support.type.prelude.x2c';
const sigilScope = 'punctuation.definition.macro.sigil.x2c';

test('cataloged semantic types and every grammar kind have a special type scope', async () => {
  const types = ['Code', 'Macro', 'Type', 'TypeInfo', 'Source',
    ...kinds('result-kind'), ...kinds('hole-kind')];
  for (const name of new Set(types)) {
    await check(`${name} value;`, name, typeScope);
    await check(`consume(${name}.member(value));`, name, typeScope);
    await check(`Var x = $( ${name}.member $value );`, name, typeScope);
    await check(`// ${name}`, name, typeScope, false);
    await check(`char *x = "${name}";`, name, typeScope, false);
  }
  await check('Statement value;', 'Statement', typeScope, false);
});

test('named, local, static and anonymous macros retain result and hole scopes', async () => {
  for (const kind of kinds('result-kind')) {
    for (const name of ['$named', 'local', '']) {
      const line = `macro ${kind}${name ? ' ' + name : ''}(Expr $value) => $value;`;
      await check(line, 'macro', 'keyword.declaration.macro.x2c');
      await check(line, kind, 'storage.type.macro.result.x2c');
    }
    await check(`static macro ${kind} $named() {}`, 'static', 'storage.modifier.x2c');
    await check(`Code value = $!${kind}{ $value };`, kind, 'storage.type.macro.result.x2c');
    await check(`Code value = $! ${kind}{ $value };`, kind, 'storage.type.macro.result.x2c');
  }
  for (const kind of kinds('hole-kind')) {
    for (const prefix of ['$', '@']) {
      await check(`macro Decorator $m(${kind} ${prefix}value) {}`, kind,
        'storage.type.macro.hole.x2c');
    }
  }
});

test('meta and native modifiers cover static, qualified and pointer return types', async () => {
  for (const modifier of ['meta', 'meta static', 'meta native', 'meta native static']) {
    for (const result of ['Code build', 'Code Owner.build', 'char *build', 'pkg.Value build']) {
      const line = `${modifier} ${result}(Code value);`;
      await check(line, 'meta', 'storage.modifier.meta.x2c');
      if (modifier.includes('native')) await check(line, 'native', 'storage.modifier.native.x2c');
      if (modifier.includes('static')) await check(line, 'static', 'storage.modifier.x2c');
    }
  }
  for (const line of ['int meta = 0;', 'meta();', 'meta value;', 'meta = 1;'])
    await check(line, 'meta', 'storage.modifier.meta.x2c', false);
  for (const line of ['int native = 0;', 'native();'])
    await check(line, 'native', 'storage.modifier.native.x2c', false);
});

test('quotation and unquote sigils survive code, data, and Lisp contexts', async () => {
  for (const line of ['Code x = $!{ $value; };', 'Code x = $!( $value );',
    'Code x = ${value};', 'Code x = $;', 'consume($);', 'Var x = %( $ );',
    'Var x = %[ $ ];', 'Var x = $( $ );']) {
    const word = line.includes('$!') ? '$!' : '$';
    await check(line, word, sigilScope, true, line.includes('$( $') ? line.lastIndexOf('$') : undefined);
  }
  for (const line of ['// $!', 'char *x = "$!";'])
    await check(line, '$!', sigilScope, false);
});

test('recommended dark and light settings color modifiers and make sigils bold', async () => {
  const readme = fs.readFileSync(path.join(__dirname, '../README.md'), 'utf8');
  const settings = [...readme.matchAll(/```json\n("editor.tokenColorCustomizations"[\s\S]*?)\n```/g)];
  assert.equal(settings.length, 2);
  for (const [, body] of settings) {
    const config = JSON.parse(`{${body}}`)['editor.tokenColorCustomizations'];
    const themeRegistry = new Registry({ onigLib, loadGrammar: async () => grammarData,
      theme: { settings: [
        { settings: { foreground: '#D4D4D4', background: '#1E1E1E' } },
        ...config.textMateRules
      ] }
    });
    const themed = await themeRegistry.loadGrammar('source.x2c');
    for (const line of ['Code value = $!{ return $value; };', 'consume($);',
      'meta native static Code build(Code value);', 'Var value = %( ${code} );']) {
      const binary = themed.tokenizeLine2(line).tokens;
      for (const word of line.match(/\$!|\$|meta|native/g) || []) {
        const at = line.indexOf(word);
        let metadata;
        for (let i = 0; i < binary.length; i += 2)
          if (binary[i] <= at) metadata = binary[i + 1];
        assert.ok(((metadata >>> 11) & 15) & 2, `${line}: ${word} must be bold`);
      }
    }
    themeRegistry.dispose();
    for (const scope of [sigilScope, 'source.x2c punctuation.definition.interpolation',
      'storage.modifier.meta.x2c', 'storage.modifier.native.x2c']) {
      const rule = config.textMateRules.find(rule => [].concat(rule.scope).includes(scope));
      assert.equal(rule.settings.fontStyle, 'bold', scope);
      assert.ok(rule.settings.foreground);
    }
  }
});


test('class declarations and C expression forms from the source grammar have scopes', async () => {
  for (const line of ['class Value int;', 'static class Value int;'])
    await check(line, 'class', 'keyword.declaration.class.x2c');
  await check('int class = 0;', 'class', 'keyword.declaration.class.x2c', false);
  for (const name of ['_Generic', 'offsetof', 'va_arg'])
    await check(`int value = ${name}(value, int);`, name, `keyword.operator.${name}.x2c`);
});
