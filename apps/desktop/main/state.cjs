const fs = require('node:fs/promises');
const path = require('node:path');
const { plugins } = require('../shared/catalog.cjs');
const { preferencesPatch, pluginRequest } = require('../shared/validation.cjs');
const defaults = Object.freeze({ profile: 'developer', compact: false, reducedMotion: false });

class StateStore {
  constructor(directory) {
    this.file = path.join(directory, 'workbench-preferences.json');
    this.preferences = { ...defaults };
    this.plugins = plugins.map((plugin) => ({ ...plugin }));
    this.queue = Promise.resolve();
  }

  async load() {
    try {
      const stats = await fs.stat(this.file);
      if (stats.size > 16384) throw new Error('Oversized preferences');
      const saved = JSON.parse(await fs.readFile(this.file, 'utf8'));
      if (saved.version !== 1 || !Array.isArray(saved.plugins)) throw new Error('Invalid preferences');
      const preferences = { ...defaults, ...preferencesPatch(saved.preferences) };
      const restored = saved.plugins.map(pluginRequest);
      this.preferences = preferences;
      this.plugins = plugins.map((plugin) => ({ ...plugin, enabled: restored.find((item) => item.id === plugin.id)?.enabled ?? plugin.enabled }));
    } catch (error) {
      if (error.code !== 'ENOENT') console.warn('Preferences could not be loaded; using local defaults.');
    }
  }

  saveChange(change) {
    const operation = this.queue.then(async () => {
      const next = change();
      await fs.mkdir(path.dirname(this.file), { recursive: true });
      const data = { version: 1, preferences: next.preferences, plugins: next.plugins.map(({ id, enabled }) => ({ id, enabled })) };
      await fs.writeFile(`${this.file}.tmp`, JSON.stringify(data, null, 2), { mode: 0o600 });
      await fs.rename(`${this.file}.tmp`, this.file);
      this.preferences = next.preferences;
      this.plugins = next.plugins;
    });
    this.queue = operation.catch(() => {});
    return operation;
  }

  async updatePreferences(value) {
    const patch = preferencesPatch(value);
    await this.saveChange(() => ({ preferences: { ...this.preferences, ...patch }, plugins: this.plugins }));
    return { ...this.preferences };
  }

  async updatePlugin(value) {
    const update = pluginRequest(value);
    await this.saveChange(() => ({ preferences: this.preferences, plugins: this.plugins.map((plugin) => plugin.id === update.id ? { ...plugin, enabled: update.enabled } : plugin) }));
    return this.plugins.map((plugin) => ({ ...plugin }));
  }
}

module.exports = { StateStore };
