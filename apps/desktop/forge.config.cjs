const { FusesPlugin } = require('@electron-forge/plugin-fuses');
const { FuseV1Options, FuseVersion } = require('@electron/fuses');

module.exports = {
  packagerConfig: {
    asar: true,
    executableName: 'helios-workbench',
    appBundleId: 'dev.helios.workbench',
    ignore: [/^\/test(?:\/|$)/, /^\/scripts(?:\/|$)/, /^\/README\.md$/],
  },
  rebuildConfig: {},
  makers: [
    { name: '@electron-forge/maker-squirrel', platforms: ['win32'], config: { name: 'helios_workbench' } },
    { name: '@electron-forge/maker-zip', platforms: ['darwin', 'linux'] },
  ],
  plugins: [new FusesPlugin({
    version: FuseVersion.V1,
    [FuseV1Options.RunAsNode]: false,
    [FuseV1Options.EnableCookieEncryption]: true,
    [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
    [FuseV1Options.EnableNodeCliInspectArguments]: false,
    [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
    [FuseV1Options.OnlyLoadAppFromAsar]: true,
  })],
};
