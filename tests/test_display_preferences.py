"""Run the exact fixed browser display expressions without exporting the game."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DisplayPreferencesTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('node'), 'Node.js required')
    def test_fixed_browser_preferences(self):
        source = (ROOT / 'client/scripts/interface/adapters/web/web_display_preferences.gd').read_text('utf-8')
        expressions = re.findall(r'"(\(\(\) =>[^"\n]+)"', source)
        self.assertEqual(len(expressions), 4)
        script = r"""
const assert = require('node:assert/strict'), vm = require('node:vm');
const [read, ...writes] = EXPRESSIONS;
const values = new Map([['save', 'sentinel']]);
const storage = {getItem(k) {return values.get(k) ?? null;}, setItem(k,v) {values.set(k,v);}};
const run = (code, localStorage = storage) => vm.runInNewContext(code, {localStorage});
assert.equal(run(read), 'normal');
for (const [index, mode] of ['normal','faded','hidden'].entries()) {
  assert.equal(run(writes[index]), true); assert.equal(run(read), mode);
}
assert.equal(values.size, 2); assert.equal(values.get('save'), 'sentinel');
const denied = {getItem() {throw Error();}, setItem() {throw Error();}};
assert.equal(run(read, denied), null);
for (const code of writes) assert.equal(run(code, denied), false);
""".replace('EXPRESSIONS', json.dumps(expressions))
        result = subprocess.run(['node', '-e', script], text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
