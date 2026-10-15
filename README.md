# Albion Reborn

A Windows desktop launcher for Daniel's Fable collection: Fable II and Fable III now, with a slot for Fable I when an installation is available. This repository contains the launcher only. Each game remains in its own installation and development repository.

## Run

Double-click `Start.cmd`, or use the **Albion Reborn** desktop shortcut. Requires Windows 10/11, Windows PowerShell 5.1 with WPF, and the Windows .NET Framework compiler. No separate runtime download is needed. `Start.cmd` builds the small windowed host automatically on first use; it has no console window while running.

The launcher discovers the existing Documents layouts for Fable II (`Fable 2/Recompiled/Fable 2 1.5.0/fable_2.exe`) and Fable III (`Fable 3/Fable-III-PC/tools/run.ps1`). Use **Locate game** or **Change location** for other locations. Fable III launches through its project script to preserve the tested lighting, mesh-visibility, shader, and pacing settings. Fable II uses its playable executable and existing configuration, with the working directory set to the installation and noisy legacy FPS logging disabled in the child environment.

Fable I starts as **Not installed**. Later, choose **Locate game** and select its Windows `.exe`; no launcher rebuild is needed. This slot does not implement or promise a Fable I port.

Selected locations are stored only on your PC in `%LOCALAPPDATA%/AlbionReborn/games.json`. Automatic discovery does not overwrite a manually chosen location. The launcher never edits game configurations, saves, caches, or assets. It detects already running configured games and prevents launching another game concurrently. Closing the launcher leaves the game running.

## Development

`Launcher.Core.ps1` handles discovery, local settings, launch validation, and child process startup. `AlbionReborn.ps1` connects that logic to the WPF interface in `Launcher.xaml`.

`Host.cs` hosts the interface in a native Windows application process using Windows PowerShell's managed API. Build it with `powershell -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -DesktopShortcut`; omit `-DesktopShortcut` to build without installing a shortcut. Generated binaries stay under ignored `out/`. Keep that directory beside the source files when running the launcher.

```powershell
powershell -NoProfile -STA -File .\AlbionReborn.ps1 -Check
powershell -NoProfile -STA -File .\AlbionReborn.ps1 -Launch fable2 -DryRun
powershell -NoProfile -STA -File .\AlbionReborn.ps1 -Launch fable3 -DryRun
powershell -NoProfile -STA -File .\Test.ps1
```

`-Check` and `-DryRun` do not start games or write preferences. `-SettingsPath` selects a separate preferences file for testing. Paths with spaces are supported. Invalid locations show a recoverable error and can be changed with the file picker.

Initial local validation: both games launched successfully from the Play buttons, and Fable III's child command line retained the mesh visibility workaround, synchronous shaders, and 60 FPS submission cap. WPF markup loading and the windowed host build passed. Core tests exercise saved-location updates, Unicode/spaced paths, quoting, process matching, discovery precedence, missing installations, the Fable III script requirement, and future Fable I configuration without starting games. This verifies launcher integration, not full-game compatibility.

The storybook interface combines official Xbox promotional cover art with original vector ornament, a custom title bar, warm gold accents, and animated card hover states. Build.ps1 caches artwork from the Microsoft image CDN on first build; the cached images work offline. Use -SkipArtwork for an offline build, or run Fetch-Art.ps1 to fetch missing covers later. Artwork is optional and is not uploaded to Git. See [artwork provenance](assets/README.md); the code license does not cover third-party promotional images. Game names belong to their respective owners. No games, ROMs, disc images, saves, compiled game code, or runtime binaries are distributed here.

Game projects: [Fable II PC](https://github.com/DanielCoffey1/Fable-II-PC), [Fable III PC](https://github.com/DanielCoffey1/Fable-III-PC).
