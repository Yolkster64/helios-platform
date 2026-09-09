# USB setup

Open **USB setup** in the HELIOS desktop navigation, or use **Plan USB and profile
setup** on Home. Choose **Sysadmin, Developer, Studio, Gamer, Core or AI Server**,
enter the physical USB device details and installation-media sizes, then select
**Preview USB plan**. There is no Apply button or disk writer in this version.

The preview runs locally without an API server, login, administrator privilege or
provider key. Inputs are manually supplied inventory, not live device discovery.
Unchecked device confirmations remain unknown; the planner never interprets them
as proof that a disk is safe. Changing a field clears the previous proposal.

## What is planned

- **USB installation media:** a bounded FAT32 UEFI installer layout, 1 GiB content
  headroom and 8 MiB layout reserve. Additional capacity remains unassigned.
- **Installed computer:** profile requirements for recovery, vault storage,
  sandbox/quarantine, hardware/driver checks and specialist workspace storage.
  Developer includes a separate Dev Drive requirement. These are not USB partitions.
- **Missing prerequisites:** backup and image provenance checks, safe target data,
  sufficient capacity, compatible files and final boot validation.

The planner rejects unknown/current system or boot targets, non-removable/read-only
media, ambiguous drive-letter targets, unsupported firmware and invalid/overflowing
sizes. It accepts capacities from 8 GiB through 16 TiB. A 32 GiB installer-partition
cap is a conservative HELIOS policy, not the FAT32 filesystem's universal limit.
Enter positive whole MiB values; round the largest file size up.

FAT32 cannot hold files of 4 GiB or more. A large file blocks the proposal until a
supported image preparation step has resolved it and updated sizes are supplied.
For a supported Windows WIM, Microsoft's split-image process is an option; arbitrary
large files are not assumed splittable. See [Microsoft's USB installation-media
instructions](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/install-windows-from-a-usb-flash-drive?view=windows-11).
The installed-system Dev Drive requirement follows [Microsoft's Dev Drive setup
guide](https://learn.microsoft.com/en-us/windows/dev-drive/), including its 50 GB
minimum. These references were checked on 2026-09-09.

## One shared contract

`src/ai/HELIOS.AIHub/Setup/UsbSetupPlanner.cs` holds the pure `UsbSetupPlanner`,
`UsbSetupRequest` and result records. The native shell source-links that exact
file, keeping planning available offline without importing provider SDKs or legacy
disk code. The portable AIHub tests and shared MCP tool use the same implementation.

The stateless `helios_usb_plan_get` MCP tool accepts `requestJson` using this shape:

```json
{
  "profile": "Developer",
  "targetDisk": {
    "deviceId": "<physical-id>",
    "capacityMiB": 32768,
    "isRemovable": true,
    "isSystemDisk": false,
    "isBootDisk": false,
    "isReadOnly": false
  },
  "firmware": "Uefi",
  "mediaSizeMiB": 6000,
  "largestFileMiB": 3000,
  "backupConfirmed": false,
  "imageVerified": false
}
```

This is an illustrative request, not discovered hardware or an execution command.
Replace the placeholder with inventory data. `AiServer` is the API profile value
for the displayed **AI Server** profile. Supplying a boolean does not verify it
against live hardware. `isValid` means the supplied data and layout passed planning
checks; `status: review-only` is not execution readiness, and `canExecute` is always
false. `diagnostics` retains outstanding prerequisites even when geometry is valid.
The result includes no shell commands, provider calls, secret values or write plans.

## Develop and test independently

USB planning is part of the main repository's **usb** component; the native page
belongs to **desktop**. They share source but have separate verification lanes:

```bash
dotnet test tests/HELIOS.AIHub.Tests -c Release --filter FullyQualifiedName~UsbSetup
```

```powershell
# Windows, Developer PowerShell; see src/gui/README.md for native dependencies.
msbuild src/gui/HELIOS.Shell.sln /restore /p:Configuration=Release /p:Platform=x64
```

The shared planner is built and tested as .NET 10 in the portable solution. The
shell retains the existing Windows App SDK 1.6 / net8.0-windows target, built with
the .NET 10 SDK. Its target migration is a separate existing roadmap boundary;
this feature does not change that package baseline or add the GUI to the Linux
solution. A passing portable test does not validate native XAML compilation or
rendering. Before release, check the Windows CI result and exercise Home-to-USB
navigation, keyboard tab order, narrow windows and all contrast themes on Windows.

## Recovery sources and next boundary

This feature does not import or execute the uploaded WinRE scripts or old USB
builders. Their reference-only disposition is recorded in the [source audit](imports/recovery/SOURCE-AUDIT-2026-09-09.md).
The legacy recovery manager contains simulation and placeholder-image behavior;
it is not a backend for the new page.

A future executable wizard needs a reviewed Windows-only inventory/media adapter,
complete signed source media, current physical-target revalidation, backup evidence,
explicit authorization and real UEFI boot-test evidence. Installed-system partition,
WinRE, driver, BitLocker and firmware changes remain separate operations. They are
not inferred from selecting a profile or previewing this plan.
