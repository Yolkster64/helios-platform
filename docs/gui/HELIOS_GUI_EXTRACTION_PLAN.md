# HELIOS GUI Extraction Plan

## Destination

`Yolkster64/helios-gui`

## Source

The active source is `src/gui/HELIOS.Shell.sln` and its WinUI 3 project under `src/gui/HELIOS.Shell` in the current Yolkster core repository.

## Binding target

```text
C# / .NET 10
WinUI 3
Windows App SDK
Microsoft.UI.Xaml
Microsoft.UI.Composition
single-project MSIX by default
```

## Extraction content

- active shell project and solution;
- XAML pages, view models, services, themes, and original assets;
- Composition-based visual primitives;
- WinUI contract validator and Windows-hosted build tests;
- accessibility, reduced-motion, crash recovery, and performance tests;
- MSIX packaging and unsigned development artifact generation;
- versioned core API/client contracts rather than copied AIHub or deployment logic;
- file-level source repository, commit, path, author/license, and destination receipt.

## Explicit exclusions

- root `HELIOS.Platform.csproj` WPF baseline;
- WPF/UWP dependencies or fallback shells;
- unported `src/gui/MonadoBlade.GUI` implementation;
- build output, caches, logs, partial downloads, credentials, and machine state;
- Azure deployment authority or Key Vault secret access;
- automatic Windows shell replacement.

## Gate sequence

1. Rename core repository and verify live identity/redirects.
2. Freeze the exact core source commit used for extraction.
3. Create private destination repository with default `main` and Actions enabled only after baseline policy is present.
4. Import active source with history-preserving tooling.
5. Add .NET 10 and reviewed Windows App SDK package versions.
6. Build/test on Windows x64.
7. Generate development MSIX and SBOM/checksums.
8. Verify core-client compatibility and no duplicated business logic.
9. Open a reviewed extraction PR and record both repository SHAs.
10. Keep workstation shell takeover disabled until signing, rollback, and local approval are independently proven.
