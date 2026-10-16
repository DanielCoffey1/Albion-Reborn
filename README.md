# Albion Reborn

A Windows desktop launcher for Daniel's Fable collection: Fable Anniversary, Fable II, and Fable III. This source repository contains the launcher; release downloads also include prebuilt runtimes. Each game remains in its own installation and development repository.

## Download and install

Download the Windows installer from [GitHub Releases](https://github.com/DanielCoffey1/Albion-Reborn/releases), install Albion Reborn, then choose **Set up / update** and select your own supported game files. This is an unsigned Windows x64 preview. Fable II GOTY USA/Europe and Fable III USA/Europe revision 0.0.0.3 are supported. Game data and audio recordings are not included. Fable II setup prepares menu music and Theresa's introduction from your local English game files; Fable III alone does not provide those recordings.

The game development repositories can remain private. Release installers include prebuilt runtimes, so players do not need access to the source repositories or build tools.

## Run

Double-click `Start.cmd`, or use the **Albion Reborn** desktop shortcut. Requires Windows 10/11, Windows PowerShell 5.1 with WPF, and the Windows .NET Framework compiler. No separate runtime download is needed. `Start.cmd` builds the small windowed host automatically on first use; it has no console window while running.

The launcher discovers the existing Documents layouts for Fable II (`Fable 2/Recompiled/Fable 2 1.5.0/fable_2.exe`) and Fable III (`Fable 3/Fable-III-PC/tools/run.ps1`). Use **Locate game** or **Change location** for other locations. Fable III launches through its project script to preserve the tested lighting, mesh-visibility, shader, and pacing settings. Fable II uses its playable executable and existing configuration, with the working directory set to the installation and noisy legacy FPS logging disabled in the child environment.

Fable Anniversary discovers a built `Fable Anniversary*/Fable-Anniversary-PC/tools/run.ps1` project under Documents. You can also locate that script manually. It launches borderless at the selected resolution, with full resolve readback, the loading-audio and input fixes from its runtime, and the validated 30 FPS cap. The shared FPS selector continues to apply to Fable II/III; Anniversary retains 30 until higher rates are tested. Anniversary saves remain in its existing Documents/fable_anniversary user-data folder. This first integration uses an existing local project; Anniversary ISO setup and a bundled downloadable runtime are not included yet.

Selected locations are stored only on your PC in `%LOCALAPPDATA%/AlbionReborn/games.json`. Automatic discovery does not overwrite a manually chosen location. Legacy launches leave game configurations, saves, caches, and assets unchanged. Managed setup installs runtime files into its own library and preserves existing seed configuration files during updates. It detects already running configured games and prevents launching another game concurrently. Closing the launcher leaves the game running.

## Offline setup preview

The local preview installer includes the launcher and prebuilt Fable II / III runtime packages. Players do not need Git, Visual Studio, access to the private game repositories, or a source build. Install Albion Reborn, choose **Set up / update** on a game card, and select your own supported Xbox 360 ISO or the `default.xex` inside an extracted game folder. Setup checks the executable revision before installing. This preview supports Fable II GOTY USA/Europe and Fable III USA/Europe revision 0.0.0.3; other revisions are rejected. Fable I setup is reserved for later.

ISO setup extracts content into `%LOCALAPPDATA%/AlbionReborn/games/<id>/content/`. Folder setup uses the selected folder in place, so keep it available. Both install the native runtime under that game's `runtime/` directory and register an installation receipt. Managed saves and caches belong to this separate runtime installation; existing legacy saves are not automatically migrated. Original game folders and existing launcher assets are retained.

**Update installed runtime** uses the version bundled with this copy of Albion Reborn, checks package and file SHA-256 hashes, backs up replaced runtime files, and preserves existing seed configs and saves. This card action uses the bundled packages; online launcher updates are handled by the footer update control. Close games before setup. Cancellation is available before runtime installation begins. Failed or older content revisions are retained rather than automatically deleted.

Runtime packages and installer binaries stay in ignored local directories; publishing a GitHub release is a separate explicit step. The source repository alone does not include the playable runtimes. Private game source repositories can remain private: an offline installer needs their build outputs, not access to their GitHub repositories. Preview installers are available through GitHub Releases. They are unsigned and have not been validated on a second PC.

## Automatic update checks

Starting with 0.3.0, Albion Reborn checks this repository's published GitHub releases in the background each time the launcher opens. The preview channel includes preview releases. **Check for updates** checks again; **Update available - download & restart** downloads and applies the selected release. Offline use and games continue to work when GitHub is unavailable; the control offers a retry. No GitHub login is needed.

Updates download the full portable bundle, check its SHA-256 hash and size against the release manifest, validate archive paths and bundled runtime hashes, then install a new launcher version under `%LOCALAPPDATA%/AlbionReborn/App/`. The updater waits for the launcher to close, refreshes the desktop shortcut, and opens the new version. Older launcher versions remain available. All games must be closed before applying an update. A failed update reports its error and reopens the previous launcher.

Managed games whose runtime package changed are updated using their existing extracted content. Seed configuration files, saves, caches, audio, game locations, and original ISOs are retained; no content extraction or game reinstall is required. Legacy external installations are launched as before and are not rewritten by the updater. The two game runtime updates are independent: if one fails after the other succeeds, the completed update remains installed and the failure is reported.

The original 0.2.0 preview does not contain an updater. Install 0.3.0 once to receive future updates through the launcher. Existing game data and user preferences stay in place. SHA-256 protects against corrupt downloads; updates trust the GitHub release publisher and are not independently code-signed.

Publish each update with the portable ZIP and the `albion-update.json` emitted by `Build-Bundle.ps1 -ReleaseTag <tag>`. Upload both before publishing the release; drafts are ignored. The manifest binds the build ID, exact repository download URL, byte size, and SHA-256. If game code changes, rebuild its runtime package with a new version before bundling. `Test.Update.ps1 -Bundle` checks version ordering, origin rejection, bad hashes, side-by-side launcher replacement, and managed runtime/config preservation without changing the user's library or shortcut.

## Menu music and Theresa

The launcher can loop Fable II's `menu_interlude` quietly in the background. On Play, the music stops and the original front-end recording says **"And so our story begins..."** before the selected game starts. Music resumes after the game exits. **Audio: On / Off** mutes both the music and launch dialogue and remembers that preference. Minimizing pauses the music. The mute preference is stored separately in `%LOCALAPPDATA%/AlbionReborn/audio-settings.json`.

Prepare the recordings once from your own local English Fable II installation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Prepare-Audio.ps1
# For another installation location:
powershell -NoProfile -ExecutionPolicy Bypass -File .\Prepare-Audio.ps1 -GameRoot "D:\Games\Fable II"
```

The helper reads two specific entries without changing the source banks. It downloads a SHA-256-checked, pinned vgmstream r2117 decoder if needed and stores the decoder, its original license notices, and extracted recordings under `%LOCALAPPDATA%/AlbionReborn/`. An existing decoder can be selected with `-DecoderPath`. No audio is downloaded from soundtrack or video sites, synthesized, or uploaded to GitHub. The game's recordings retain their owners' rights and are not covered by the launcher's code license.

Without prepared audio the launcher remains usable and starts games immediately. A failed voice clip falls back to launching, with a five-second timeout so Play cannot hang. Closing the launcher during the voice introduction cancels the pending launch. `Test.Audio.ps1` exercises real media decoding and dialogue completion with a stubbed game launch; it also checks mute, missing-dialogue fallback, and music stop/resume without starting a game.

Format references: [Fable 2 Asset Browser's bank and text format implementations](https://github.com/adarec1994/Fable2AssetBrowser), [vgmstream decoder](https://github.com/vgmstream/vgmstream/releases/tag/r2117). The helper implements only the small v3 bank subset needed for these two local entries. Theresa's entry is `TEXT_QUEST_QC010_FRONT_END_10.wav`; the English text bank resolves its tag to the quoted line. Prepared durations are approximately 2:38.63 for music and 1.852 seconds for dialogue.

## Development

`Launcher.Core.ps1` handles discovery, local settings, launch validation, and child process startup. `AlbionReborn.ps1` connects that logic to the WPF interface in `Launcher.xaml`.

`Host.cs` hosts the interface in a native Windows application process using Windows PowerShell's managed API. Build it with `powershell -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -DesktopShortcut`; omit `-DesktopShortcut` to build without installing a shortcut. Generated binaries stay under ignored `out/`. Keep that directory beside the source files when running the launcher.

```powershell
powershell -NoProfile -STA -File .\AlbionReborn.ps1 -Check
powershell -NoProfile -STA -File .\AlbionReborn.ps1 -Launch fable2 -DryRun
powershell -NoProfile -STA -File .\AlbionReborn.ps1 -Launch fable3 -DryRun
powershell -NoProfile -STA -File .\Test.ps1
powershell -NoProfile -STA -File .\Test.Audio.ps1
```

`-Check` and `-DryRun` do not start games or write preferences. `-SettingsPath` selects a separate preferences file for testing. Paths with spaces are supported. Invalid locations show a recoverable error and can be changed with the file picker.

Initial local validation: both games launched successfully from the Play buttons, and Fable III's child command line retained the mesh visibility workaround, synchronous shaders, and 60 FPS submission cap. WPF markup loading and the windowed host build passed. Core tests exercise saved-location updates, Unicode/spaced paths, quoting, process matching, discovery precedence, missing installations, the Fable III script requirement, and future Fable I configuration without starting games. This verifies launcher integration, not full-game compatibility.

The storybook interface combines official Xbox promotional cover art with original vector ornament, a custom title bar, warm gold accents, and animated card hover states. Build.ps1 caches artwork from the Microsoft image CDN on first build; the cached images work offline. Use -SkipArtwork for an offline build, or run Fetch-Art.ps1 to fetch missing covers later. Promotional cover art is optional and is not uploaded to Git. The original AI-generated misty town-and-castle background is included in the repository and works offline. Slow mist, golden light, and subtle motes pause when the launcher loses focus or is minimized, and honor Windows' client-area animation preference. See [artwork provenance](assets/README.md); the code license does not cover third-party promotional images. Game names belong to their respective owners. No games, ROMs, disc images, saves, compiled game code, or runtime binaries are distributed here.

Game projects: [Fable II PC](https://github.com/DanielCoffey1/Fable-II-PC), [Fable III PC](https://github.com/DanielCoffey1/Fable-III-PC).

## Build a bundled preview

Build the launcher first with `Build.ps1 -SkipArtwork`. Use `Build-RuntimePackages.ps1 -Fable2Runtime <built-folder> -Fable3Runtime <built-folder> -CrtDirectory <VC143-CRT-folder>` to produce allowlisted runtime ZIPs and a hash catalog under ignored `out/packages/` (pass `-Destination .\packages` for the default bundle input). This requires the sibling game repositories for their license notices and the already-built native game runtimes. It excludes ISO content, default.xex, saves, shader caches, logs, and debug symbols. Runtime binaries contain recompiled game code and are not covered solely by the launcher's code license.

Run `Build-Bundle.ps1 -DecoderDirectory <vgmstream-folder>` to produce the portable ZIP and Windows installer in `out/distribution/`. Existing cover artwork is included in the local preview; no assets are stripped from the working installations. The optional decoder lets Fable II setup prepare music locally without a download. Installer extraction is per-user and requires no elevation. `--verify` checks the embedded payload; `--extract-to <parent-folder>` extracts without creating a shortcut or launching the app.

`Test.Setup.ps1` checks unsafe archive paths and unsupported content rejection. Add `-RealInstallations` for isolated installs of both local games, update preservation, managed launch arguments, and cancellation. A full Fable III ISO extraction was also compared against the existing installation: all 286 extracted files matched SHA-256. These checks validate setup integration, not every gameplay scenario.

## Automated build and release agent

The private Fable III repository runs the **Build and publish Albion Reborn** GitHub Actions workflow on main pushes, every 15 minutes, and on manual dispatch. Scheduled runs check the main revisions of all three repositories, so Fable II and launcher changes are picked up without cross-repository credentials in public workflows. GitHub schedules can be delayed; the build PC must be awake, online, and signed in. A startup shortcut reconnects its runner after sign-in.

The Windows runner is registered only to the private Fable III repository. It builds in separate agent checkouts, uses locally supplied game executables/content, and uses the owner's existing local GitHub CLI authentication to read private source and publish public releases. The public launcher repository has no self-hosted workflow, tokens, game files, or agent configuration. Do not add pull-request triggers to the private build-agent workflow.

`tools/Invoke-AutomatedRelease.ps1 -ConfigPath <local-config>` synchronizes main using fast-forward only, verifies the game executable hashes, regenerates guest code, builds both native runtimes (including their matched renderer fixes), packages allowlisted runtime/config files, builds the launcher, runs integration and artifact integrity/content-exclusion checks, verifies the installer, and publishes all assets through a draft release. The draft becomes visible to the updater only after all uploads succeed. Runtime versions carry the exact game source commit, and every release includes `source-revisions.json` and checksums. Unchanged source revisions do not publish again. Failures leave the previous public release available and the next run retries.

Use `-ValidateOnly` to build/test without publishing, or `-Force` to republish unchanged inputs under a fresh timestamp. Automated native builds do not perform full-game gameplay tests. The existing release-only update channel remains a preview channel.

Local config fields: `root` (agent directory), `fable2Content`, `fable3Content`, `decoderDirectory`, `pythonDirectory`, optional `llvmBin`, and `jobs`. Keep that JSON outside Git. Build roots contain game-derived generated code and credentials in the runner folder; never upload that directory. Stop `Runner.Listener` or disable its Startup shortcut to suspend the agent. Workflow status and failures are visible in the private Fable III repository's Actions tab.

## Shared resolution setting

The library header has one **Resolution** selector: **1080p (default)**, **1440p**, and **4K**. It saves to `%LOCALAPPDATA%/AlbionReborn/display-settings.json` and applies on the next launch to managed Fable II and III, direct Fable II installations, and the current Fable III development script. Changing it while playing takes effect after restarting the game. Save files and game configuration files are not rewritten.

The selection passes the SDK's guest video-mode/window resolution preset with draw scaling 1, avoiding stacking a 3x internal multiplier onto a 4K preset. Borderless output uses the desktop display; the game's own renderer determines which passes follow the requested video mode. Videos or fixed-resolution effects may retain their original resolution. Higher presets can reduce performance.

The preference is reserved for Fable I, but arbitrary external Fable I executables are launched without guessed command-line flags. Resolution integration will be added with that game's runtime. The old per-game `fable3-display.json` integer-scale preference is superseded by this shared setting. Expert development tests can still use `tools/run.ps1 -RenderScale 1/2/3` explicitly.

`Test.Resolution.ps1` validates defaults, persistence, safe fallback, launch plans for both supported games, preservation of Fable III's 60 FPS/rendering fixes, and the WPF selector.

## Shared FPS limit

The **FPS limit** selector offers 30, **60 (default)**, 90, 120, 144, 165, 240 FPS, and Unlimited. It saves alongside resolution in `display-settings.json`; changing either preference preserves the other. Existing profiles without an FPS preference use 60. Changes apply the next time you launch Fable II or III, including supported development installations. Fable I support will follow its runtime integration.

The selected value is a cap, not a performance guarantee. Limits above 60 and Unlimited are experimental: game timing and compatibility at those rates have not been validated. Fable II uses its host frame limiter with guest vblank pacing disabled; Fable III uses its existing submission limiter. The tested lighting, visibility, and synchronous shader settings remain enabled.

`Test.Fps.ps1` covers profile migration/fallback, independent preference persistence, all cap choices including Unlimited, supported launch paths, and preservation of rendering fixes. Automated releases run this gate before packaging.
