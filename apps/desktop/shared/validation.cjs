const { profiles, plugins, resources } = require('./catalog.cjs');

function objectWithKeys(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
      || !Object.keys(value).every((key) => keys.includes(key))) throw new Error('Invalid request');
}

function preferencesPatch(value) {
  objectWithKeys(value, ['profile', 'compact', 'reducedMotion']);
  if ('profile' in value && !profiles.some((profile) => profile.id === value.profile)) throw new Error('Unknown profile');
  for (const key of ['compact', 'reducedMotion']) {
    if (key in value && typeof value[key] !== 'boolean') throw new Error('Invalid preference');
  }
  return { ...value };
}

function pluginRequest(value) {
  objectWithKeys(value, ['id', 'enabled']);
  if (!plugins.some((plugin) => plugin.id === value.id) || typeof value.enabled !== 'boolean') throw new Error('Invalid module');
  return { id: value.id, enabled: value.enabled };
}

function resourceRequest(value) {
  objectWithKeys(value, ['id']);
  if (typeof value.id !== 'string' || !Object.hasOwn(resources, value.id)) throw new Error('Unknown resource');
  return resources[value.id];
}

function trustedSender(event, webContents, pageUrl) {
  if (!webContents || event.sender !== webContents || event.senderFrame !== webContents.mainFrame) return false;
  try {
    const senderUrl = new URL(event.senderFrame.url);
    senderUrl.hash = '';
    return senderUrl.href === pageUrl;
  } catch { return false; }
}

function canCheckHealth(preferences, modules) {
  return preferences.profile !== 'sysadmin' && modules.some((module) => module.id === 'connections' && module.enabled);
}

module.exports = { preferencesPatch, pluginRequest, resourceRequest, trustedSender, canCheckHealth };
