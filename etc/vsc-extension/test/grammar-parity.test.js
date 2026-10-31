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

test('module and static preserve private declaration scopes', async () => {
  for (const modifier of ['static', 'module']) {
    for (const declaration of [
      'int counter;', 'inline int work(void) => 1;',
      'typedef int Count;', 'typedef struct Node { int value; } Node;',
      'typedef enum Color { red } Color;', 'struct Node { int value; };',
      'union Value { int value; };', 'enum Color { red };', 'class Count int;',
      'macro STMT $work(EXPR $value) { $value; }',
      'keyword work $work;', 'protocol Reading(Count);'
    ]) {
      const line = `${modifier} ${declaration}`;
      await check(line, modifier, 'storage.modifier.x2c');
      if (modifier === 'module')
        await check(line, modifier, 'storage.modifier.module.x2c');
      if (declaration.startsWith('typedef'))
        await check(line, 'typedef', 'keyword.other.typedef.x2c');
      if (declaration.startsWith('class'))
        await check(line, 'class', 'keyword.declaration.class.x2c');
      if (declaration.startsWith('macro')) {
        await check(line, 'macro', 'keyword.declaration.macro.x2c');
        await check(line, 'STMT', 'storage.type.macro.result.x2c');
        await check(line, 'EXPR', 'storage.type.macro.hole.x2c');
      }
      if (declaration.startsWith('keyword'))
        await check(line, 'keyword', 'keyword.declaration.macro.x2c');
      if (declaration.startsWith('protocol'))
        await check(line, 'protocol', 'keyword.declaration.protocol.x2c');
    }
  }
  await check('module {', 'module', 'keyword.declaration.module.x2c');
  for (const line of ['int module = 0;', 'module();', 'module = 1;',
    'object.module(value);', '// module int count;', 'char *s = "module int count;";'])
    await check(line, 'module', 'storage.modifier.x2c', false);
});

test('uppercase syntax kinds have built-in type colors outside macro signatures', async () => {
  for (const kind of new Set([...kinds('result-kind'), ...kinds('hole-kind')])) {
    const name = kind.toUpperCase();
    await check(`${name} value;`, name, typeScope);
    await check(`// ${name}`, name, typeScope, false);
    await check(`char *s = "${name}";`, name, typeScope, false);
  }
  for (const name of ['name', 'field', 'entry', 'statement', 'STMT_extra'])
    await check(`int ${name} = 0;`, name, typeScope, false);
});

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

test('quotation and unquote sigils survive code and data contexts', async () => {
  for (const line of ['Code x = $!{ $value; };', 'Code x = $!( $value );',
    'Code x = ${value};', 'Code x = $;', 'consume($);', 'Var x = %( $ );',
    'Var x = %[ $ ];']) {
    const word = line.includes('$!') ? '$!' : '$';
    await check(line, word, sigilScope);
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

test('managed declarations and acquired initializers highlight auto', async () => {
  for (const line of ['auto Scope work = NULL;', 'auto value = Buffer.new(0);',
    'auto Array left = [], right = [];',
    'auto const value = 1;', 'Buffer value = auto Buffer.new(0);',
    'void work() { auto value = 1; }']) {
    await check(line, 'auto', 'storage.modifier.auto.x2c');
  }
  for (const line of ['// auto value = 1;', 'char *s = "auto";',
    'int automatic = 1;', 'Buffer value = $auto(Buffer.new(0));'])
    await check(line, 'auto', 'storage.modifier.auto.x2c', false);
});

test('native auto regions retain modifier scope at each target', async () => {
  for (const source of ['auto { work(); }',
    'auto for (int i = 0; i < n; i++) work();',
    'auto int work(void) => 1;', 'auto (&slot) { work(); }',
    'auto (&slot) int work(void) { return 1; }']) {
    await check(source, 'auto', 'storage.modifier.auto.x2c');
    await check(source, 'auto', 'entity.name.function.call.x2c', false);
  }
});

test('module declarations can follow another declaration on the same line', async () => {
  for (const line of ['int first; module int second;',
    'int first; module inline int work(void) => 1;'])
    await check(line, 'module', 'storage.modifier.module.x2c');
  await check('struct module { int value; };', 'module', 'keyword.declaration.module.x2c', false);
});

test('macro using accepts retained names and fresh names', async () => {
  for (const line of ['using scale;', 'using scale, $temporary;',
    'macro Expression $scaled(Expr $value) using scale => $value * scale;'])
    await check(line, 'using', 'keyword.other.macro.using.x2c');
  for (const line of ['int using = 1;', '// using scale;', 'char *s = "using scale;";'])
    await check(line, 'using', 'keyword.other.macro.using.x2c', false);
});

test('meta declarations retain scopes across comments, lines and preceding declarations', async () => {
  for (const source of [
    'int first; meta int one(void) => 1;',
    'meta /* comment */ int two(void) => 2;',
    'meta\nint three(void) => 3;',
    'meta // comment\nstatic int four(void) => 4;',
    'meta /* comment\ncontinued */ native int five(void) { return 5; }',
    'meta\nnative\nstatic int six(void) { return 6; }',
    'int first; meta protocol Iter(List);',
    'meta\nprotocol Iter(List);'
  ]) {
    let state;
    for (const line of source.split('\n')) {
      const result = (await grammar).tokenizeLine(line, state);
      state = result.ruleStack;
      for (const word of ['meta', 'native']) {
        const at = line.indexOf(word);
        if (at < 0) continue;
        const token = result.tokens.find(t => t.startIndex <= at && at < t.endIndex);
        assert.ok(token.scopes.includes(`storage.modifier.${word}.x2c`), `${source}: ${word}`);
        assert.ok(token.scopes.includes(`keyword.other.${word}.x2c`), `${source}: visible ${word}`);
      }
    }
    const after = (await grammar).tokenizeLine('native(); int meta = 0;', state);
    assert.ok(after.tokens.every(t => !t.scopes.includes('storage.modifier.native.x2c') &&
      !t.scopes.includes('storage.modifier.meta.x2c')), source);
  }
});

test('meta and native receive keyword colors without x2c theme overrides', async () => {
  const themedRegistry = new Registry({ onigLib, loadGrammar: async () => grammarData,
    theme: { settings: [
      { settings: { foreground: '#D4D4D4', background: '#1E1E1E' } },
      { scope: 'keyword', settings: { foreground: '#C586C0' } }
    ] }
  });
  const themed = await themedRegistry.loadGrammar('source.x2c');
  const line = 'meta native int work(void);';
  const tokens = themed.tokenizeLine2(line).tokens;
  for (const word of ['meta', 'native']) {
    let metadata;
    for (let i = 0; i < tokens.length; i += 2)
      if (tokens[i] <= line.indexOf(word)) metadata = tokens[i + 1];
    assert.equal(themedRegistry.getColorMap()[(metadata >>> 15) & 511], '#C586C0');
  }
  themedRegistry.dispose();
  await check('meta int native(void);', 'native', 'storage.modifier.native.x2c', false);
});


test('symbol literals keep delimiters inside the literal', async () => {
  for (const spelling of ['(', ')', '[', ']', '{', '}', ';', ',', '/', '/*',
    '//', '+', '<', 'foo-bar', 'name', '*name', '?name']) {
    const literal = `<${spelling}>`;
    for (const line of [`c.expect(${literal});`,
      `List entries = c.peek(0) == ${literal} ? NULL : _parse_params(c);`,
      `List values = %( ${literal} after );`]) {
      await check(line, literal, 'meta.literal.symbol.simple.x2c');
      await check(line, spelling, 'constant.other.symbol.x2c.simple', true,
        line.indexOf(literal) + 1);
      const after = line.endsWith('after );') ? 'after' : ';';
      await check(line, after, 'meta.literal.symbol.simple.x2c', false,
        line.lastIndexOf(after));
    }
  }
  for (const line of ['int value = left < right;', 'int value = left << right;',
    'int value = left < right > other;', '// <(>', 'char *s = "<)>";'])
    await check(line, '<', 'meta.literal.symbol.simple.x2c', false);
});


test('symbol punctuation is excluded from editor bracket matching', async () => {
  const manifest = require('../package.json');
  const contribution = manifest.contributes.grammars.find(g => g.language === 'x2c');
  const types = { other: 0, comment: 1, string: 2, regex: 3 };
  const tokenTypes = Object.fromEntries(Object.entries(contribution.tokenTypes || {})
    .map(([scope, type]) => [scope, types[type]]));
  const configuredRegistry = new Registry({ onigLib, loadGrammar: async () => grammarData });
  const configured = await configuredRegistry.loadGrammarWithConfiguration(
    'source.x2c', 1, { tokenTypes });
  for (const literal of ['<(>', '<)>', '<[>', '<]>', '<{>', '<}>', '<"(">', '<")">',
    '%<( ) [ ] { }>', '%<red <(> blue>']) {
    const line = `c.expect(${literal});`;
    const tokens = configured.tokenizeLine2(line).tokens;
    function typeAt(at) {
      let metadata;
      for (let i = 0; i < tokens.length; i += 2)
        if (tokens[i] <= at) metadata = tokens[i + 1];
      return (metadata >>> 8) & 3;
    }
    const start = line.indexOf(literal);
    for (let at = start; at < start + literal.length; at++)
      assert.equal(typeAt(at), types.string, `${line}: ${at}`);
    assert.equal(typeAt(start - 1), types.other, line);
    assert.equal(typeAt(start + literal.length), types.other, line);
  }
  configuredRegistry.dispose();
});

test('List and Map rest parameters have splice sigils and parameter names', async () => {
  for (const type of ['List', 'Map']) {
    for (const source of [
      `int count(${type} @items);`,
      `int count(int fixed, ${type} @items) => items.len();`,
      `int Owner.count(Self self, ${type} @items) { return 0; }`,
      `typedef int (*Callback)(${type} @items);`,
      `meta int count(${type} /* tail */ @items) => 0;`
    ]) {
      await check(source, type, typeScope);
      await check(source, '@', 'punctuation.definition.macro.splice.x2c');
      await check(source, 'items', 'variable.parameter.rest.x2c');
      await check(source, 'items', 'variable.other.macro.hole.x2c', false);
    }
    await check(`typedef int (*Callback)(${type} @);`, '@',
      'punctuation.definition.macro.splice.x2c');
  }
  for (const source of ['consume(1, @items, @(make_items()));',
    'connect("a", @options, port: 8080, @(make_options()));']) {
    await check(source, '@', 'punctuation.definition.macro.splice.x2c');
    await check(source, '@(', 'meta.macro.hole.expression.x2c');
    await check(source, 'make_', 'constant.other.atom.x2c', false);
  }
  await check('macro Expr $m(Expr @items) => 0;', 'items', 'variable.parameter.macro.x2c');
  await check('int native(int fixed, ...);', '...', 'punctuation.vararg-ellipses.x2c');
});

test('name-first aliases scope only their separator', async () => {
  for (const source of ['alias settings to window.settings;',
    'static alias settings to window.settings;',
    'alias settings to window.settings { work(); }',
    'alias settings to window.settings:',
    'void work(void) { alias settings to window.settings; }']) {
    await check(source, 'alias', 'keyword.declaration.alias.x2c');
    await check(source, 'to', 'keyword.declaration.alias.x2c');
  }
  for (const source of ['int to = 0;', 'to(value);', 'object.to(value);',
    'alias object.to as local;', 'alias local to object.to;']) {
    await check(source, 'to', 'keyword.declaration.alias.x2c', false,
      source.lastIndexOf('to'));
  }
});

test('pattern conditions and typeof spellings use operator scopes', async () => {
  await check('if (row ~= %(pair ?(int a))) {}', '~=', 'keyword.operator.pattern-match.x2c');
  for (const word of ['typeof', 'typeof_unqual', '__typeof__', '__typeof']) {
    await check(`${word}(value) result;`, word, `keyword.operator.${word}.x2c`);
    await check(`object.${word}(value);`, word, `keyword.operator.${word}.x2c`, false);
  }
});

test('evaluated Maps keep code scopes inside quoted collections', async () => {
  for (const source of ['Map value = ${key: make_value()};',
    'List value = %(row ${key: make_value()} after);',
    'Array value = %[${key: make_value()}, after];',
    'Map value = %{entry: ${key: make_value()}, after: data};']) {
    await check(source, '${', 'meta.literal.map.evaluated.x2c');
    await check(source, 'key', 'constant.other.atom.x2c', false);
    await check(source, 'make_value', 'constant.other.atom.x2c', false);
    await check(source, ';', 'meta.literal.map.evaluated.x2c', false);
  }
});

test('single-angle SymbolSets end at the outer delimiter and preserve punctuation data', async () => {
  for (const literal of ['%<>', '%<red blue>', '%<red <blue>>', '%<">" \\>>',
    '%<( ) [ ] { }>', '%<red /* comment */ blue>']) {
    const source = `SymbolSet value = ${literal}; int after;`;
    await check(source, '%<', 'punctuation.definition.literal.symbol-set.begin.x2c');
    await check(source, '>', 'punctuation.definition.literal.symbol-set.end.x2c', true,
      source.lastIndexOf('>'));
    await check(source, '; int after;', 'meta.literal.symbol-set.x2c', false);
  }
  for (const source of ['int value = left << right;', 'int value = left %<red>;',
    '// %<red>', 'char *value = "%<red>";'])
    await check(source, '<', 'meta.literal.symbol-set.x2c', false);
});

test('rest parameter markers survive comments and line breaks without swallowing ordinary types', async () => {
  for (const type of ['List', 'Map']) {
    for (const tail of ['@items', '@']) {
      let state;
      for (const line of [`int count(${type} /* tail`, 'continued */', `  ${tail});`]) {
        const result = (await grammar).tokenizeLine(line, state);
        state = result.ruleStack;
        if (!line.includes('@')) continue;
        const sigil = result.tokens.find(token => token.startIndex <= line.indexOf('@') &&
          line.indexOf('@') < token.endIndex);
        assert.ok(sigil.scopes.includes('punctuation.definition.macro.splice.x2c'));
        if (tail === '@items') {
          const name = result.tokens.find(token => token.startIndex <= line.indexOf('items') &&
            line.indexOf('items') < token.endIndex);
          assert.ok(name.scopes.includes('variable.parameter.rest.x2c'));
        }
      }
      const after = (await grammar).tokenizeLine('int ordinary;', state);
      assert.ok(after.tokens.every(token => !token.scopes.includes('variable.parameter.rest.x2c')));
    }
    await check(`${type} ordinary;`, 'ordinary', 'variable.parameter.rest.x2c', false);
    await check(`${type}.new();`, 'new', 'entity.name.function.x2c');
  }
});
