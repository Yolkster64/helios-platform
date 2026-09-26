'use strict';

(() => {
  const bridge = window.helios;
  const preview = !bridge || typeof bridge.getSnapshot !== 'function';
  const previewKey = 'helios.renderer.preview.v1';
  const profileDetails = {
    sysadmin: { glyph: '⌘', description: 'A quiet, offline workspace for system planning.' },
    developer: { glyph: '⌥', description: 'Code, modules, and the tools to build your next idea.' },
    studio: { glyph: '♫', description: 'A creative perspective for sound, visuals, and making.' },
    gamer: { glyph: '◈', description: 'A focused workspace for play and performance planning.' },
    core: { glyph: '◎', description: 'A clear view of the everyday essentials.' },
    'ai-server': { glyph: '⌁', description: 'A home for AIHub, Hermes, and XCore integration planning.' }
  };
  const panelLabels = { overview: 'Overview', connections: 'Connections', workbench: 'Workbench', usb: 'USB planner', lab: 'Lab' };
  const panelModules = { connections: 'connections', usb: 'usb-planner', lab: 'profile-lab' };
  const fallback = {
    app: { name: 'HELIOS', version: 'browser preview', platform: 'browser' },
    profiles: [
      { id: 'sysadmin', name: 'Sysadmin', accent: '#f6b86b' },
      { id: 'developer', name: 'Developer', accent: '#64e5ec' },
      { id: 'studio', name: 'Studio', accent: '#e68dce' },
      { id: 'gamer', name: 'Gamer', accent: '#b5e676' },
      { id: 'core', name: 'Core', accent: '#a8b7ce' },
      { id: 'ai-server', name: 'AI/Server', accent: '#b2a0ff' }
    ],
    connectors: [
      { id: 'github', name: 'GitHub', kind: 'Repository', state: 'unavailable', detail: 'Desktop adapter pending. A browser session does not authenticate this app.', capabilities: ['Repositories', 'Pull requests', 'Actions'] },
      { id: 'sharepoint', name: 'SharePoint', kind: 'Knowledge', state: 'unavailable', detail: 'Desktop adapter and tenant configuration are required.', capabilities: ['Documents', 'Knowledge'] },
      { id: 'slack', name: 'Slack', kind: 'Coordination', state: 'unavailable', detail: 'Desktop adapter and workspace authorization are required.', capabilities: ['Channels', 'Evidence links'] },
      { id: 'linear', name: 'Linear', kind: 'Planning', state: 'unavailable', detail: 'Desktop adapter and workspace authorization are required.', capabilities: ['Issues', 'Projects'] },
      { id: 'chatgpt', name: 'ChatGPT', kind: 'AI workspace', state: 'unavailable', detail: 'Opening ChatGPT does not connect it to HELIOS or grant API access.', capabilities: ['Browser reference'] }
    ],
    plugins: [
      { id: 'connections', name: 'Connections', description: 'Review adapter capabilities and inspect local integration configuration.', enabled: true },
      { id: 'usb-planner', name: 'USB planner', description: 'Explore a capacity sketch without performing disk operations.', enabled: true },
      { id: 'profile-lab', name: 'Profile Lab', description: 'Explore Electron Forge and Fiddle references.', enabled: true }
    ],
    integration: { state: 'unavailable', detail: 'Browser preview has no native integration bridge. Launch the desktop app to inspect its local configuration.', checkedAt: null },
    preferences: { profile: 'developer', compact: false, reducedMotion: false }
  };
  let snapshot = structuredClone(fallback);
  let activePanel = 'overview';
  let plan = null;
  let toastTimer;
  let preferenceBusy = false;
  let pluginBusy = false;
  const $ = (id) => document.getElementById(id);
  const escape = (value) => String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
  const color = (value) => /^#[0-9a-f]{6}$/i.test(String(value)) ? value : '#65e5d4';
  const humanize = (value) => String(value || 'unavailable').replace(/[-_]/g, ' ').replace(/^./, (character) => character.toUpperCase());
  const moduleEnabled = (id) => snapshot.plugins.find((plugin) => plugin.id === id)?.enabled === true;
  const panelEnabled = (id) => !panelModules[id] || moduleEnabled(panelModules[id]);
  const profile = () => snapshot.profiles.find((item) => item.id === snapshot.preferences.profile) || snapshot.profiles[0] || fallback.profiles[1];
  const isOfflineProfile = () => snapshot.preferences.profile === 'sysadmin';
  const connectorGlyph = (id) => ({ github: '⌘', sharepoint: 'S', slack: '#', linear: '◩', chatgpt: '✳', openai: '✳', azure: 'A', hermes: 'H', xcore: 'X' }[id] || '↗');

  function tell(message, error = false) {
    clearTimeout(toastTimer);
    $('toast').textContent = message;
    $('toast').dataset.error = String(error);
    $('toast').hidden = false;
    toastTimer = setTimeout(() => { $('toast').hidden = true; }, error ? 8000 : 4500);
  }

  function normalize(value) {
    if (!value || typeof value !== 'object') throw new Error('The desktop bridge returned an invalid workspace snapshot.');
    return {
      app: { ...fallback.app, ...value.app },
      profiles: Array.isArray(value.profiles) ? value.profiles : [],
      connectors: Array.isArray(value.connectors) ? value.connectors : [],
      plugins: Array.isArray(value.plugins) ? value.plugins : [],
      integration: { state: 'unavailable', detail: 'No integration status was supplied.', checkedAt: null, ...value.integration },
      preferences: { ...fallback.preferences, ...value.preferences }
    };
  }

  function savePreview() {
    try {
      localStorage.setItem(previewKey, JSON.stringify({ preferences: snapshot.preferences, plugins: snapshot.plugins.map(({ id, enabled }) => ({ id, enabled })) }));
    } catch {
      tell('Browser storage is unavailable. Your preview preferences will last for this session only.', true);
    }
  }

  function selectPanel(id, focus = false) {
    if (!Object.hasOwn(panelLabels, id)) id = 'overview';
    if (!panelEnabled(id)) {
      tell('This module is disabled. Enable it in Workbench to open it.');
      id = 'workbench';
    }
    activePanel = id;
    document.querySelectorAll('.panel').forEach((panel) => { panel.hidden = panel.id !== `panel-${id}`; });
    document.querySelectorAll('.nav-button').forEach((button) => {
      const active = button.dataset.panel === id;
      button.classList.toggle('active', active);
      if (active) button.setAttribute('aria-current', 'page');
      else button.removeAttribute('aria-current');
    });
    $('breadcrumb-title').textContent = panelLabels[id];
    document.title = `${panelLabels[id]} · HELIOS Workbench`;
    if (window.location.hash !== `#${id}`) history.replaceState(null, '', `#${id}`);
    if (focus) $('main-content').focus({ preventScroll: true });
  }

  function renderProfiles() {
    const selected = profile();
    document.documentElement.style.setProperty('--accent', color(selected.accent));
    document.body.classList.toggle('compact', Boolean(snapshot.preferences.compact));
    document.body.classList.toggle('reduced-motion', Boolean(snapshot.preferences.reducedMotion));
    $('sidebar-profile').textContent = selected.name;
    $('profile-avatar').textContent = selected.name.slice(0, 1);
    $('profile-summary').textContent = selected.name;
    $('hero-profile').textContent = `${selected.name} profile active`;
    $('compact-toggle').checked = Boolean(snapshot.preferences.compact);
    $('motion-toggle').checked = Boolean(snapshot.preferences.reducedMotion);
    $('profile-grid').innerHTML = snapshot.profiles.map((item) => {
      const detail = profileDetails[item.id] || { glyph: '◇', description: 'A HELIOS workspace profile.' };
      return `<button class="profile-card" data-profile="${escape(item.id)}" aria-pressed="${item.id === selected.id}"><span class="profile-glyph" aria-hidden="true">${escape(detail.glyph)}</span><strong>${escape(item.name)}</strong><p>${escape(detail.description)}</p><span class="profile-check" aria-hidden="true">✓</span></button>`;
    }).join('');
    document.querySelectorAll('[data-profile]').forEach((button) => {
      const entry = snapshot.profiles.find((item) => item.id === button.dataset.profile);
      button.style.setProperty('--profile-color', color(entry?.accent));
    });
    const selectedUsbProfile = $('usb-profile').value;
    $('usb-profile').innerHTML = snapshot.profiles.map((item) => `<option value="${escape(item.id)}">${escape(item.name)}</option>`).join('');
    $('usb-profile').value = snapshot.profiles.some((item) => item.id === selectedUsbProfile) ? selectedUsbProfile : selected.id;
  }

  function connectorState(connector) {
    return isOfflineProfile() ? 'offline' : connector.state || 'unavailable';
  }

  function renderConnectors() {
    const preferred = ['github', 'slack', 'linear', 'sharepoint'];
    const overviewConnectors = [...preferred.map((id) => snapshot.connectors.find((connector) => connector.id === id)).filter(Boolean), ...snapshot.connectors.filter((connector) => !preferred.includes(connector.id))].slice(0, 4);
    $('overview-connections').innerHTML = snapshot.connectors.length ? overviewConnectors.map((connector) => {
      const state = connectorState(connector);
      return `<div class="connection-row"><span class="connector-icon" data-kind="${escape(connector.id)}" aria-hidden="true">${escape(connectorGlyph(connector.id))}</span><strong>${escape(connector.name)}</strong><span class="state-pill" data-state="${escape(state)}">${escape(humanize(state))}</span></div>`;
    }).join('') : '<p class="empty-state">No connectors are registered in this desktop build.</p>';
    $('connection-grid').innerHTML = snapshot.connectors.length ? snapshot.connectors.map((connector) => {
      const state = connectorState(connector);
      const capabilities = Array.isArray(connector.capabilities) ? connector.capabilities : [];
      const detail = isOfflineProfile() ? `Sysadmin is an offline profile. ${connector.detail || ''}` : connector.detail || 'Configuration details are not available.';
      return `<article class="surface connector-card"><div class="connector-card-top"><span class="connector-icon" data-kind="${escape(connector.id)}" aria-hidden="true">${escape(connectorGlyph(connector.id))}</span><h2>${escape(connector.name)}</h2><span class="state-pill" data-state="${escape(state)}">${escape(humanize(state))}</span></div><p>${escape(detail)}</p><div class="capability-list" aria-label="Planned capabilities">${capabilities.map((capability) => `<span>${escape(capability)}</span>`).join('')}</div><div class="connector-kind">${escape(connector.kind || 'Service adapter')} · ${capabilities.length ? 'Capability inventory' : 'Adapter pending'}</div></article>`;
    }).join('') : '<p class="empty-state">No connectors are registered in this desktop build.</p>';
    const readyCount = snapshot.connectors.filter((connector) => ['ready', 'connected'].includes(connector.state)).length;
    $('connection-summary').textContent = !moduleEnabled('connections') ? 'Module disabled' : isOfflineProfile() ? 'Offline profile' : readyCount ? `${readyCount} ready` : 'Adapters pending';
  }

  function renderIntegration() {
    const integration = snapshot.integration;
    const titles = { ready: 'Local bridge ready', connected: 'Local bridge connected', configured: 'Configuration present', unavailable: 'Bridge unavailable', unconfigured: 'Configuration needed', 'not-configured': 'Configuration needed', error: 'Status check needs attention', disabled: 'Local bridge disabled', offline: 'Local bridge offline', degraded: 'Bridge needs attention' };
    $('bridge-heading').textContent = isOfflineProfile() ? 'Sysadmin stays offline' : titles[integration.state] || humanize(integration.state);
    $('bridge-detail').textContent = isOfflineProfile() ? 'Network checks and external browser links are disabled in this profile.' : integration.detail || 'No status details were supplied.';
    const checkedAt = integration.checkedAt ? new Date(integration.checkedAt) : null;
    $('bridge-meta').textContent = checkedAt && !Number.isNaN(checkedAt.valueOf()) ? `Last check · ${checkedAt.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}` : 'No check recorded';
  }

  function renderPlugins() {
    $('plugin-grid').innerHTML = snapshot.plugins.length ? snapshot.plugins.map((plugin) => `<label class="surface plugin-card"><div><h3>${escape(plugin.name)}</h3><p>${escape(plugin.description || 'Optional workspace module.')}</p></div><input class="switch" type="checkbox" data-plugin="${escape(plugin.id)}" aria-label="Enable ${escape(plugin.name)}" ${plugin.enabled ? 'checked' : ''}/></label>`).join('') : '<p class="empty-state">No optional modules are registered in this desktop build.</p>';
    document.querySelectorAll('[data-panel]').forEach((button) => {
      button.hidden = !panelEnabled(button.dataset.panel);
    });
    const connectionsAvailable = moduleEnabled('connections');
    $('overview-connections').closest('section').hidden = !connectionsAvailable;
    document.querySelector('.integration-surface').hidden = !connectionsAvailable;
    document.querySelector('.overview-bottom').hidden = !connectionsAvailable;
    $('refresh-button').disabled = !connectionsAvailable || isOfflineProfile() || preview;
    $('refresh-button').title = !connectionsAvailable ? 'Enable Connections in Workbench to check status.' : isOfflineProfile() ? 'Sysadmin is an offline profile.' : preview ? 'Launch the desktop app to inspect the local integration bridge.' : 'Check local integration status';
    document.querySelectorAll('[data-resource]').forEach((button) => {
      button.disabled = isOfflineProfile() || preview;
      button.title = isOfflineProfile() ? 'External links are disabled in Sysadmin.' : preview ? 'Open reference links from the desktop app.' : 'Open in your default browser';
    });
    if (!panelEnabled(activePanel)) selectPanel('workbench');
  }

  function render() {
    renderProfiles();
    renderConnectors();
    renderIntegration();
    renderPlugins();
    $('runtime-label').textContent = preview ? 'Browser preview · local only' : isOfflineProfile() ? 'Sysadmin · offline mode' : 'Desktop bridge · local';
    $('mode-label').textContent = preview ? 'Browser preview' : isOfflineProfile() ? 'Offline profile' : 'Local workspace';
    $('version-label').textContent = preview ? 'UI preview · no desktop bridge' : `v${snapshot.app.version} · ${snapshot.app.platform}`;
  }

  async function updatePreferences(patch) {
    if (preferenceBusy) return;
    preferenceBusy = true;
    document.querySelectorAll('[data-profile], #compact-toggle, #motion-toggle').forEach((control) => { control.disabled = true; });
    try {
      if (preview) {
        snapshot.preferences = { ...snapshot.preferences, ...patch };
        savePreview();
      } else {
        await bridge.setPreferences(patch);
        snapshot = normalize(await bridge.getSnapshot());
      }
      render();
      tell(patch.profile ? `${profile().name} profile selected${preview ? ' in browser preview' : ''}.` : `Workspace preferences saved${preview ? ' in browser preview' : ''}.`);
    } catch (error) {
      render();
      tell(error?.message || 'The preference could not be saved. Please try again.', true);
    } finally {
      preferenceBusy = false;
      document.querySelectorAll('[data-profile], #compact-toggle, #motion-toggle').forEach((control) => { control.disabled = false; });
    }
  }

  async function togglePlugin(input) {
    if (pluginBusy) return;
    const id = input.dataset.plugin;
    const enabled = input.checked;
    pluginBusy = true;
    document.querySelectorAll('[data-plugin]').forEach((control) => { control.disabled = true; });
    try {
      if (preview) {
        snapshot.plugins = snapshot.plugins.map((plugin) => plugin.id === id ? { ...plugin, enabled } : plugin);
        savePreview();
      } else {
        await bridge.setPluginEnabled({ id, enabled });
        snapshot = normalize(await bridge.getSnapshot());
      }
      render();
      const name = snapshot.plugins.find((plugin) => plugin.id === id)?.name || 'Module';
      tell(`${name} ${enabled ? 'enabled' : 'disabled'}${preview ? ' in browser preview' : ''}.`);
    } catch (error) {
      render();
      tell(error?.message || 'The module preference could not be saved. Please try again.', true);
    } finally {
      pluginBusy = false;
      document.querySelectorAll('[data-plugin]').forEach((control) => { control.disabled = false; });
    }
  }

  async function checkHealth() {
    if (!moduleEnabled('connections') || isOfflineProfile() || preview) return;
    const button = $('refresh-button');
    button.disabled = true;
    button.setAttribute('aria-busy', 'true');
    try {
      const integration = await bridge.checkHealth();
      snapshot = normalize(await bridge.getSnapshot());
      if (integration && typeof integration === 'object') snapshot.integration = integration;
      render();
      tell(`Status checked: ${humanize(snapshot.integration.state).toLowerCase()}.`);
    } catch (error) {
      tell(error?.message || 'The local bridge could not be checked.', true);
    } finally {
      button.removeAttribute('aria-busy');
      renderPlugins();
    }
  }

  async function openResource(button) {
    if (preview || isOfflineProfile()) return;
    const id = button.dataset.resource;
    if (!['github', 'chatgpt', 'forge', 'fiddle'].includes(id)) return;
    button.disabled = true;
    try {
      await bridge.openResource({ id });
      tell('Reference opened in your default browser. Account connection is configured separately.');
    } catch (error) {
      tell(error?.message || 'The reference could not be opened.', true);
    } finally {
      renderPlugins();
    }
  }

  function makePlan(announce = false) {
    const capacity = Number($('capacity').value);
    const vaultPercent = Number($('vault-share').value);
    const selected = snapshot.profiles.find((item) => item.id === $('usb-profile').value) || profile();
    if (![64, 128, 256, 512, 1024].includes(capacity) || !Number.isInteger(vaultPercent) || vaultPercent < 0 || vaultPercent > 50) {
      tell('Choose a valid capacity and vault allocation.', true);
      return;
    }
    const recovery = $('include-recovery').checked ? 8 : 0;
    const vault = Math.floor(capacity * vaultPercent / 100);
    const segments = [
      { name: 'Boot / setup placeholder', gib: 4, color: '#6fe0d0' },
      { name: 'Recovery files', gib: recovery, color: '#acbbf1' },
      { name: 'Vault placeholder', gib: vault, color: '#dfa4c1' },
      { name: 'Workspace / files', gib: capacity - 4 - recovery - vault, color: '#477b96' }
    ];
    plan = {
      kind: 'helios-capacity-sketch', schemaVersion: 1, planningOnly: true,
      description: 'Illustrative capacity allocation only. Not a bootable image, executable script, partition table, or validated OS installation layout.',
      profile: selected.id, nominalCapacityGiB: capacity,
      allocations: segments.map(({ name, gib }) => ({ label: name, sizeGiB: gib })),
      unallocatedGiB: 0, deviceSelected: false, executable: false
    };
    $('plan-capacity').textContent = `${capacity.toLocaleString()} GiB`;
    $('plan-profile').textContent = `${selected.name} workspace`;
    $('plan-unallocated').textContent = '0 GiB';
    $('plan-note').textContent = selected.id === 'sysadmin' ? 'Offline workspace planning. Encryption, recovery validity, and boot configuration need separate implementation and verification.' : 'Workspace allocation is a placeholder for files and tools. This sketch does not configure Dev Drive, encryption, boot, or an operating system.';
    $('capacity-bar').innerHTML = segments.filter((segment) => segment.gib > 0).map((segment) => `<span class="capacity-segment" data-allocation="${escape(segment.name)}" title="${escape(segment.name)}: ${segment.gib} GiB"></span>`).join('');
    document.querySelectorAll('.capacity-segment').forEach((element) => {
      const segment = segments.find((item) => item.name === element.dataset.allocation);
      element.style.width = `${segment.gib / capacity * 100}%`;
      element.style.setProperty('--segment-color', segment.color);
    });
    $('capacity-bar').setAttribute('aria-label', segments.map((segment) => `${segment.name}: ${segment.gib} GiB`).join('; '));
    $('plan-legend').innerHTML = segments.map((segment) => `<div class="legend-row"><span class="legend-dot" data-allocation="${escape(segment.name)}" aria-hidden="true"></span><span>${escape(segment.name)}</span><strong>${segment.gib.toLocaleString()} GiB</strong></div>`).join('');
    document.querySelectorAll('.legend-dot').forEach((element) => {
      element.style.setProperty('--segment-color', segments.find((segment) => segment.name === element.dataset.allocation).color);
    });
    if (announce) tell('Capacity sketch updated. No device operations were performed.');
  }

  function exportPlan() {
    if (!moduleEnabled('usb-planner')) return;
    makePlan();
    if (!plan) return;
    const blob = new Blob([`${JSON.stringify(plan, null, 2)}\n`], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `helios-capacity-sketch-${plan.profile}-${plan.nominalCapacityGiB}gib.json`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    tell('Planning JSON download requested.');
  }

  document.addEventListener('click', (event) => {
    const navigation = event.target.closest('[data-panel]');
    if (navigation) return selectPanel(navigation.dataset.panel, true);
    const profileButton = event.target.closest('[data-profile]');
    if (profileButton) return updatePreferences({ profile: profileButton.dataset.profile });
    const resourceButton = event.target.closest('[data-resource]');
    if (resourceButton) return openResource(resourceButton);
  });
  document.addEventListener('change', (event) => {
    if (event.target.matches('[data-plugin]')) togglePlugin(event.target);
  });
  $('compact-toggle').addEventListener('change', (event) => updatePreferences({ compact: event.target.checked }));
  $('motion-toggle').addEventListener('change', (event) => updatePreferences({ reducedMotion: event.target.checked }));
  $('refresh-button').addEventListener('click', checkHealth);
  $('planner-form').addEventListener('submit', (event) => { event.preventDefault(); if (moduleEnabled('usb-planner')) makePlan(true); });
  $('vault-share').addEventListener('input', (event) => { $('vault-output').textContent = `${event.target.value}%`; });
  $('export-plan').addEventListener('click', exportPlan);
  window.addEventListener('hashchange', () => selectPanel(window.location.hash.slice(1), true));

  async function initialize() {
    try {
      if (preview) {
        try {
          const saved = JSON.parse(localStorage.getItem(previewKey) || 'null');
          if (saved && typeof saved === 'object') {
            const selectedProfile = fallback.profiles.some((item) => item.id === saved.preferences?.profile) ? saved.preferences.profile : 'developer';
            snapshot.preferences = { profile: selectedProfile, compact: saved.preferences?.compact === true, reducedMotion: saved.preferences?.reducedMotion === true };
            if (Array.isArray(saved.plugins)) snapshot.plugins = snapshot.plugins.map((plugin) => ({ ...plugin, enabled: saved.plugins.find((item) => item.id === plugin.id)?.enabled !== false }));
          }
        } catch { /* An unavailable or old preview preference never blocks the interface. */ }
        $('notice').textContent = 'Browser preview · Preferences and module switches work locally. Native status checks and external links require the Electron desktop app.';
        $('notice').hidden = false;
      } else {
        snapshot = normalize(await bridge.getSnapshot());
      }
      render();
      makePlan();
      selectPanel(window.location.hash.slice(1));
    } catch (error) {
      snapshot.connectors = [];
      snapshot.plugins = [];
      snapshot.integration = { state: 'error', detail: 'The desktop bridge did not provide a workspace snapshot.', checkedAt: null };
      render();
      document.querySelectorAll('[data-profile], #compact-toggle, #motion-toggle').forEach((control) => { control.disabled = true; });
      $('notice').textContent = `Workspace could not be loaded. ${error?.message || 'Restart the desktop app to try again.'}`;
      $('notice').hidden = false;
      selectPanel('overview');
    }
  }

  initialize();
})();
