const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('web/flutter_bootstrap.js', 'utf8')
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');

async function run({ worker = false, migrated = false, failure = false } = {}) {
  const result = { loaded: 0, reloaded: 0, removed: [], caches: [] };
  const values = new Map(migrated ? [['watermark-worker-migrated', '1']] : []);
  const context = {
    URL, console: { warn() {} }, window: { caches: true },
    caches: { delete: async name => result.caches.push(name) },
    location: { href: 'https://watermark.juba-tech.store/', reload() { result.reloaded++; } },
    sessionStorage: { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value) },
    _flutter: { loader: { load() { result.loaded++; } } },
    navigator: worker ? { serviceWorker: {
      controller: {},
      async getRegistrations() {
        if (failure) throw new Error('Storage unavailable');
        return ['https://watermark.juba-tech.store/', 'https://watermark.juba-tech.store/other/']
          .map(scope => ({ scope, async unregister() { result.removed.push(scope); } }));
      },
    } } : {},
  };
  await vm.runInNewContext(source, context);
  return result;
}
(async () => {
  assert.equal((await run()).loaded, 1);
  const old = await run({ worker: true });
  assert.equal(old.loaded, 0);
  assert.equal(old.reloaded, 1);
  assert.deepEqual(old.removed, ['https://watermark.juba-tech.store/']);
  assert.deepEqual(old.caches, ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']);
  const repeat = await run({ worker: true, migrated: true });
  assert.equal(repeat.loaded, 1);
  assert.equal(repeat.reloaded, 0);
  assert.equal((await run({ worker: true, failure: true })).loaded, 1);
  console.log('4 web bootstrap migration scenarios passed');
})();
