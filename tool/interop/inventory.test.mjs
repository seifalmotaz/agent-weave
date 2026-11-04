import assert from 'node:assert/strict';
import test from 'node:test';
import { declarations, validateCoverage } from './inventory.mjs';

test('retains nested namespaces, optional fields, unions and inheritance', () => {
  const index = declarations(`
    export interface Base { value: string | number; 'quoted-key'?: Array<{ id: string }> }
    export namespace Base { export interface Inner extends Base { enabled?: boolean } }
    export type Input = Base | Base.Inner;
  `, 'fixture.ts');
  assert.deepEqual(index.Base.fields, [
    { name: 'value', optional: false, type: 'string | number' },
    { name: 'quoted-key', optional: true, type: 'Array<{\n    id: string;\n}>' },
  ]);
  assert.deepEqual(index['Base.Inner'].extends, ['Base']);
  assert.deepEqual(index['Base.Inner'].fields, [{ name: 'enabled', optional: true, type: 'boolean' }]);
  assert.equal(index.Input.type, 'Base | Base.Inner');
});

test('refuses malformed sources, unhandled index signatures and duplicate names', () => {
  assert.throws(() => declarations('export interface Bad { broken:', 'bad.ts'), /Invalid TypeScript/);
  assert.throws(() => declarations('export interface Bag { [key: string]: unknown }', 'bag.ts'), /Unsupported interface member/);
  assert.throws(() => declarations('interface A {} interface A {}', 'duplicate.ts'), /Duplicate interface/);
});


test('requires field dispositions and all executable typed options', () => {
  const fields = [{ name: 'model' }, { name: 'logprobs' }];
  const coverage = {
    model: { status: 'runtime-owned', api: 'model' },
    logprobs: { status: 'typed-option', api: 'logprobs' },
  };
  validateCoverage(fields, coverage, { logprobs: 5 });
  assert.throws(() => validateCoverage([...fields, { name: 'new_option' }], coverage), /explicit disposition/);
  assert.throws(() => validateCoverage(fields, { ...coverage, stale: coverage.model }), /stale entries/);
  assert.throws(() => validateCoverage(fields, coverage, {}), /every typed option/);
  assert.throws(() => validateCoverage(fields, { ...coverage, model: { status: 'assumed' } }), /Invalid coverage/);
});
