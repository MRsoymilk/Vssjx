"""Execute the exact, fixed Web preference expressions without exporting a game."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SoundPreferencesTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('node'), 'Node.js required for Web flag regression')
    def test_browser_sound_flag_expressions(self):
        source = (ROOT / 'client/scripts/interface/adapters/web/web_sound_preferences.gd').read_text('utf-8')
        expressions = re.findall(r'"(\(\(\) =>[^"\n]+)"', source)
        self.assertEqual(len(expressions), 3)
        script = r"""
const assert = require('node:assert/strict');
const vm = require('node:vm');
const [read, enable, disable] = EXPRESSIONS;
const key = 'vssjx.sound.enabled.v1';
const values = new Map([['player-save', 'sentinel'], ['account', 'untouched']]);
const storage = {getItem(k) { return values.get(k) ?? null; }, setItem(k, v) { values.set(k, v); }};
const run = (expression, localStorage = storage) => vm.runInNewContext(expression, {localStorage});
assert.equal(run(read), 'true');
assert.equal(run(disable), true);
assert.equal(run(read), 'false');
assert.equal(run(enable), true);
assert.equal(run(read), 'true');
values.set(key, 'invalid');
assert.equal(run(read), 'invalid');
assert.equal(values.get('player-save'), 'sentinel');
assert.equal(values.get('account'), 'untouched');
assert.equal(values.size, 3);
const denied = {getItem() { throw Error('SecurityError'); }, setItem() { throw Error('QuotaExceededError'); }};
assert.equal(run(read, denied), null);
assert.equal(run(enable, denied), false);
assert.equal(run(disable, denied), false);
const noWrite = {getItem() { return null; }, setItem() {}};
assert.equal(run(enable, noWrite), false);
assert.equal(run(disable, noWrite), false);
""".replace('EXPRESSIONS', json.dumps(expressions))
        result = subprocess.run(['node', '-e', script], text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
