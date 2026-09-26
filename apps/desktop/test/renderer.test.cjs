const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');
const { profiles, plugins, connectors } = require('../shared/catalog.cjs');

const rendererRoot = path.join(__dirname, '../renderer');
const html = fs.readFileSync(path.join(rendererRoot, 'index.html'), 'utf8');
const source = fs.readFileSync(path.join(rendererRoot, 'app.js'), 'utf8');

function initialState() {
  return {
    app: { name: 'HELIOS', version: '0.1.0', platform: 'test' },
    profiles: structuredClone(profiles), connectors: structuredClone(connectors),
    plugins: structuredClone(plugins),
    preferences: { profile: 'developer', compact: false, reducedMotion: false },
    integration: { state: 'disabled', detail: 'Local service has not been checked.', checkedAt: null },
  };
}

async function until(predicate, message) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.fail(message || 'Renderer did not settle.');
}

async function mount(t, state = initialState(), options = {}) {
  const errors = [];
  const calls = { preferences: [], plugins: [], resources: [], health: 0 };
  const downloads = [];
  const blobs = new Map();
  let rejectPreference = false;
  const console = new VirtualConsole();
  console.on('jsdomError', (error) => errors.push(error));
  // Resources are not loaded. Evaluate the actual renderer JS against a DOM,
  // with only the documented preload contract replaced by an in-memory bridge.
  const dom = new JSDOM(html, {
    url: 'https://helios-renderer.test/index.html',
    runScripts: 'outside-only', virtualConsole: console,
  });
  const { window } = dom;
  window.structuredClone = structuredClone;
  window.Blob = Blob;
  window.URL.createObjectURL = (blob) => {
    const url = `blob:renderer-test-${blobs.size + 1}`;
    blobs.set(url, blob);
    return url;
  };
  window.URL.revokeObjectURL = () => {};
  window.HTMLAnchorElement.prototype.click = function clickDownload() {
    downloads.push({ filename: this.download, url: this.href });
  };
  if (!options.preview) {
    window.helios = {
      getSnapshot: async () => structuredClone(state),
      setPreferences: async (patch) => {
        calls.preferences.push(structuredClone(patch));
        if (rejectPreference) {
          rejectPreference = false;
          throw new Error('Preference write failed.');
        }
        state.preferences = { ...state.preferences, ...patch };
        return structuredClone(state.preferences);
      },
      setPluginEnabled: async ({ id, enabled }) => {
        calls.plugins.push({ id, enabled });
        state.plugins = state.plugins.map((plugin) => plugin.id === id ? { ...plugin, enabled } : plugin);
        return structuredClone(state.plugins);
      },
      checkHealth: async () => {
        calls.health += 1;
        state.integration = { state: 'ready', detail: 'Local test bridge responded.', checkedAt: '2026-09-26T04:00:00.000Z' };
        return structuredClone(state.integration);
      },
      openResource: async ({ id }) => { calls.resources.push(id); },
    };
  }
  window.eval(source);
  await until(() => window.document.getElementById('runtime-label').textContent !== 'Starting local workspace', 'Renderer initialization failed.');
  const $ = (selector) => window.document.querySelector(selector);
  t.after(() => {
    dom.window.close();
    assert.deepEqual(errors.map((error) => error.message), [], 'Renderer emitted an unhandled DOM error.');
  });
  return {
    dom, window, $, state, calls, downloads, blobs,
    rejectNextPreference() { rejectPreference = true; },
    change(selector, checked) {
      const control = $(selector);
      control.checked = checked;
      control.dispatchEvent(new window.Event('change', { bubbles: true }));
    },
  };
}

test('renderer uses the catalog and switches persisted profiles; Sysadmin blocks network controls', async (t) => {
  const fixture = await mount(t);
  const { $, state, calls } = fixture;
  assert.equal($('[data-profile="developer"]').getAttribute('aria-pressed'), 'true');
  assert.equal(fixture.window.document.querySelectorAll('[data-profile]').length, 6);
  assert.equal(fixture.window.document.querySelectorAll('.connector-card').length, connectors.length);
  assert.match($('#connection-summary').textContent, /Adapters pending/);

  $('#refresh-button').click();
  await until(() => $('#bridge-heading').textContent === 'Local bridge ready');
  assert.equal(calls.health, 1);

  $('[data-panel="workbench"]').click();
  $('[data-profile="sysadmin"]').click();
  await until(() => $('#sidebar-profile').textContent === 'Sysadmin');
  assert.equal(state.preferences.profile, 'sysadmin');
  assert.equal($('#refresh-button').disabled, true);
  assert.equal($('#bridge-heading').textContent, 'Sysadmin stays offline');
  fixture.window.document.querySelectorAll('[data-resource]').forEach((button) => {
    assert.equal(button.disabled, true);
    button.click();
  });
  $('#refresh-button').click();
  assert.equal(calls.health, 1);
  assert.deepEqual(calls.resources, []);

  fixture.dom.window.close();
  const reloaded = await mount(t, state);
  assert.equal(reloaded.$('#sidebar-profile').textContent, 'Sysadmin');
  assert.equal(reloaded.$('#refresh-button').disabled, true);
  reloaded.$('[data-profile="studio"]').click();
  await until(() => reloaded.$('#sidebar-profile').textContent === 'Studio');
  assert.equal(reloaded.$('[data-resource="forge"]').disabled, false);
  assert.equal(reloaded.$('#refresh-button').disabled, false);
});

test('module switches hide their routes, persist across reloads, and can be re-enabled', async (t) => {
  const state = initialState();
  const fixture = await mount(t, state);
  const { $, change, window } = fixture;
  $('[data-panel="workbench"]').click();
  change('[data-plugin="connections"]', false);
  await until(() => $('.nav-button[data-panel="connections"]').hidden);
  assert.equal($('#refresh-button').disabled, true);
  assert.equal($('.overview-bottom').hidden, true);
  assert.equal(state.plugins.find((plugin) => plugin.id === 'connections').enabled, false);

  // A disabled module remains inaccessible even through a direct hash route.
  window.location.hash = '#connections';
  await until(() => window.location.hash === '#workbench' && $('#breadcrumb-title').textContent === 'Workbench');
  assert.equal($('#panel-connections').hidden, true);
  fixture.dom.window.close();

  const reloaded = await mount(t, state);
  assert.equal(reloaded.$('.nav-button[data-panel="connections"]').hidden, true);
  assert.equal(reloaded.$('[data-plugin="connections"]').checked, false);
  reloaded.change('[data-plugin="connections"]', true);
  await until(() => !reloaded.$('.nav-button[data-panel="connections"]').hidden);
  assert.equal(reloaded.$('#refresh-button').disabled, false);
  reloaded.$('.nav-button[data-panel="connections"]').click();
  assert.equal(reloaded.$('#panel-connections').hidden, false);

  reloaded.change('[data-plugin="usb-planner"]', false);
  await until(() => reloaded.$('.nav-button[data-panel="usb"]').hidden);
  reloaded.change('[data-plugin="profile-lab"]', false);
  await until(() => reloaded.$('.nav-button[data-panel="lab"]').hidden);
  assert.equal(reloaded.$('.nav-button[data-panel="workbench"]').hidden, false);
});

test('USB planner recomputes allocations and exports a non-executable capacity sketch', async (t) => {
  const fixture = await mount(t);
  const { $, window, downloads, blobs, calls } = fixture;
  $('.nav-button[data-panel="usb"]').click();
  $('#capacity').value = '256';
  $('#usb-profile').value = 'ai-server';
  $('#vault-share').value = '35';
  $('#vault-share').dispatchEvent(new window.Event('input', { bubbles: true }));
  $('#include-recovery').checked = false;
  $('#planner-form').dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
  assert.equal($('#vault-output').textContent, '35%');
  assert.equal($('#plan-capacity').textContent, '256 GiB');
  assert.equal($('#plan-profile').textContent, 'AI/Server workspace');
  assert.match($('#capacity-bar').getAttribute('aria-label'), /Recovery files: 0 GiB/);
  assert.match($('#capacity-bar').getAttribute('aria-label'), /Vault placeholder: 89 GiB/);
  assert.match($('#capacity-bar').getAttribute('aria-label'), /Workspace \/ files: 163 GiB/);

  $('#export-plan').click();
  assert.equal(downloads.length, 1);
  assert.equal(downloads[0].filename, 'helios-capacity-sketch-ai-server-256gib.json');
  const exported = JSON.parse(await blobs.get(downloads[0].url).text());
  assert.equal(exported.planningOnly, true);
  assert.equal(exported.deviceSelected, false);
  assert.equal(exported.executable, false);
  assert.equal(exported.profile, 'ai-server');
  assert.equal(exported.nominalCapacityGiB, 256);
  assert.equal(exported.allocations.reduce((total, allocation) => total + allocation.sizeGiB, 0), 256);
  assert.equal(exported.unallocatedGiB, 0);
  assert.deepEqual(calls, { preferences: [], plugins: [], resources: [], health: 0 }, 'Planning must not invoke native or provider actions.');
});

test('rejected preference saves restore prior selection and leave controls usable', async (t) => {
  const fixture = await mount(t);
  const { $, state } = fixture;
  fixture.rejectNextPreference();
  $('[data-profile="studio"]').click();
  await until(() => $('#toast').dataset.error === 'true');
  assert.equal($('#sidebar-profile').textContent, 'Developer');
  assert.equal(state.preferences.profile, 'developer');
  assert.equal($('[data-profile="developer"]').getAttribute('aria-pressed'), 'true');
  assert.equal($('[data-profile="studio"]').disabled, false);
  assert.match($('#toast').textContent, /Preference write failed/);

  fixture.rejectNextPreference();
  fixture.change('#compact-toggle', true);
  await until(() => !$('#compact-toggle').disabled);
  assert.equal($('#compact-toggle').checked, false);
  assert.equal(fixture.window.document.body.classList.contains('compact'), false);
  fixture.change('#compact-toggle', true);
  await until(() => fixture.window.document.body.classList.contains('compact'));
  assert.equal(state.preferences.compact, true);
});

test('browser preview identifies its limits and stores only local preferences', async (t) => {
  const fixture = await mount(t, initialState(), { preview: true });
  const { $, window } = fixture;
  assert.match($('#notice').textContent, /Browser preview/);
  assert.equal($('#refresh-button').disabled, true);
  assert.equal($('[data-resource="github"]').disabled, true);
  $('[data-profile="gamer"]').click();
  await until(() => $('#sidebar-profile').textContent === 'Gamer');
  fixture.change('#motion-toggle', true);
  await until(() => window.document.body.classList.contains('reduced-motion'));
  const saved = JSON.parse(window.localStorage.getItem('helios.renderer.preview.v1'));
  assert.equal(saved.preferences.profile, 'gamer');
  assert.equal(saved.preferences.reducedMotion, true);
  assert.equal(window.helios, undefined);
});
