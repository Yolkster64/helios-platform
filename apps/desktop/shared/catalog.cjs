const profiles = [
  { id: 'sysadmin', name: 'Sysadmin', accent: '#f6b86b' },
  { id: 'developer', name: 'Developer', accent: '#64e5ec' },
  { id: 'studio', name: 'Studio', accent: '#e68dce' },
  { id: 'gamer', name: 'Gamer', accent: '#b5e676' },
  { id: 'core', name: 'Core', accent: '#a8b7ce' },
  { id: 'ai-server', name: 'AI/Server', accent: '#b2a0ff' },
];

// Built-in workbench modules are declarative. Enabling one never runs downloaded code.
const plugins = [
  { id: 'connections', name: 'Connections', description: 'Service inventory and local AIHub health check.', enabled: true },
  { id: 'usb-planner', name: 'USB planner', description: 'Estimate a layout locally; no device access or disk writes.', enabled: true },
  { id: 'profile-lab', name: 'Profile lab', description: 'Profile colors, motion preferences, and Fiddle experiments.', enabled: true },
];

const connectors = [
  ['github', 'GitHub', 'delivery', ['repositories', 'pull requests', 'checks']],
  ['chatgpt', 'ChatGPT / Codex', 'assistant', ['MCP client', 'coding tasks']],
  ['openai', 'OpenAI API', 'provider', ['AIHub adapter']],
  ['claude', 'Claude', 'provider', ['AIHub adapter', 'MCP client']],
  ['copilot', 'GitHub Copilot', 'assistant', ['IDE', 'repository review']],
  ['slack', 'Slack', 'coordination', ['delivery receipts']],
  ['linear', 'Linear', 'coordination', ['issues', 'projects']],
  ['sharepoint', 'SharePoint / Microsoft 365', 'knowledge', ['Graph documents', 'evidence']],
  ['azure', 'Azure / Foundry', 'cloud', ['OIDC', 'managed identity']],
  ['hermes', 'Hermes', 'fleet', ['routing', 'planning']],
  ['xcore', 'XCore', 'fleet', ['evaluation']],
].map(([id, name, kind, capabilities]) => ({
  id, name, kind, capabilities, state: 'unavailable',
  detail: 'Desktop adapter pending. Connections in ChatGPT do not sign this app in.',
}));

const resources = Object.freeze({
  github: 'https://github.com/Yolkster64/helios-platform',
  chatgpt: 'https://chatgpt.com/',
  forge: 'https://www.electronforge.io/',
  fiddle: 'https://www.electronjs.org/fiddle',
});

module.exports = { profiles, plugins, connectors, resources };
