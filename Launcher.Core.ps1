Set-StrictMode -Version Latest

function Get-AlbionCatalog {
    @(
        [pscustomobject]@{ Id='fable1'; Name='Fable I'; Numeral='I'; Tagline='Every hero has a beginning.'; Description='A place reserved for the first chapter. Add your installation whenever it is ready.' }
        [pscustomobject]@{ Id='fable2'; Name='Fable II'; Numeral='II'; Tagline='Your choices shape a kingdom.'; Description='Return to Albion and continue your story with your existing game settings.' }
        [pscustomobject]@{ Id='fable3'; Name='Fable III'; Numeral='III'; Tagline='The crown is only the beginning.'; Description='Lead a revolution with your current lighting and scenery fixes.' }
    )
}

function Read-AlbionSettings {
    param([Parameter(Mandatory)][string]$Path)
    $settings = @{}
    if (Test-Path -LiteralPath $Path) {
        $document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($document.schemaVersion -ne 1) { throw 'Unsupported launcher settings version.' }
        foreach ($game in $document.games) {
            if ($game.id -in @('fable1','fable2','fable3') -and $game.entry -is [string]) {
                $settings[$game.id] = $game.entry
            }
        }
    }
    return $settings
}

function Save-AlbionSettings {
    param([hashtable]$Settings, [string]$Path)
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $games = @(Get-AlbionCatalog | ForEach-Object {
        if ($Settings.ContainsKey($_.Id)) { @{ id=$_.Id; entry=$Settings[$_.Id] } }
    })
    $json = @{ schemaVersion=1; games=$games } | ConvertTo-Json -Depth 4
    # Replace only launcher preferences, using a same-directory temporary file.
    $temporary = Join-Path $directory ([IO.Path]::GetRandomFileName())
    try {
        [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, ($Path + '.previous')) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) }
    }
}

function Find-AlbionInstallations {
    param([hashtable]$Settings, [string]$Documents)
    $candidates = @{
        fable2 = Join-Path $Documents 'Fable 2\Recompiled\Fable 2 1.5.0\fable_2.exe'
        fable3 = Join-Path $Documents 'Fable 3\Fable-III-PC\tools\run.ps1'
    }
    foreach ($id in $candidates.Keys) {
        # A user-selected location always wins, including a disconnected drive.
        if (!$Settings.ContainsKey($id) -and (Test-Path -LiteralPath $candidates[$id] -PathType Leaf)) {
            $Settings[$id] = $candidates[$id]
        }
    }
}

function Get-AlbionLaunchPlan {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Entry)
    if ($Id -notin @('fable1','fable2','fable3')) { throw 'Unknown game.' }
    if (!(Test-Path -LiteralPath $Entry -PathType Leaf)) { throw 'Game not found. Choose Locate to select its launcher.' }
    $fullPath = (Get-Item -LiteralPath $Entry).FullName
    if ($fullPath.Contains('"')) { throw 'The launch path contains an unsupported quote.' }
    $extension = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    $directory = Split-Path -Parent $fullPath
    if ($extension -eq '.ps1' -and $Id -eq 'fable3') {
        if ((Split-Path -Leaf $fullPath) -ne 'run.ps1') { throw 'Choose Fable III-PC\tools\run.ps1 to retain its rendering fixes.' }
        $project = Split-Path -Parent $directory
        $processPath = Join-Path $project 'out\build\win-amd64-release\fable_3.exe'
        if (!(Test-Path -LiteralPath $processPath -PathType Leaf)) { throw 'Fable III needs a native build. Build it in its own project first.' }
        return [pscustomobject]@{
            Id=$Id; FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            Arguments=('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $fullPath + '"')
            WorkingDirectory=$project; ProcessPath=$processPath; Entry=$fullPath
        }
    }
    if ($extension -ne '.exe') { throw 'Choose a Windows game executable (.exe), or Fable III tools\run.ps1.' }
    if ($Id -eq 'fable2' -and (Split-Path -Leaf $fullPath) -ne 'fable_2.exe') {
        throw 'Choose the playable fable_2.exe so your tested configuration is used.'
    }
    if ($Id -eq 'fable3') { throw 'Choose Fable III-PC\tools\run.ps1 to preserve the tested rendering settings.' }
    return [pscustomobject]@{
        Id=$Id; FileName=$fullPath; Arguments=''; WorkingDirectory=$directory
        ProcessPath=$fullPath; Entry=$fullPath
    }
}

function Get-AlbionGameProcess {
    param($Plan)
    $name = [IO.Path]::GetFileNameWithoutExtension($Plan.ProcessPath)
    @([Diagnostics.Process]::GetProcessesByName($name) | Where-Object {
        try { $_.MainModule.FileName -eq $Plan.ProcessPath } catch { $false }
    })
}

function Start-AlbionGame {
    param($Plan)
    if (@(Get-AlbionGameProcess $Plan).Count) { throw 'This game is already running.' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Plan.FileName
    $start.Arguments=$Plan.Arguments
    $start.WorkingDirectory=$Plan.WorkingDirectory
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    # Leave the parent's environment alone; disable the old noisy FPS logger only in Fable II.
    if ($Plan.Id -eq 'fable2') { $start.EnvironmentVariables.Remove('FABLE2_FPS_METER') }
    return [Diagnostics.Process]::Start($start)
}
