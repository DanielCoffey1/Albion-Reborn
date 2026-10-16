Set-StrictMode -Version Latest

function Read-AlbionResolution {
    param([string]$Path=(Join-Path $env:LOCALAPPDATA 'AlbionReborn\display-settings.json'))
    try{
        $value=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if($value.schemaVersion -eq 1 -and $value.resolution -in @('1080p','1440p','4k')){return [string]$value.resolution}
    }catch{}
    return '1080p'
}
function Read-AlbionFrameLimit {
    param([string]$Path=(Join-Path $env:LOCALAPPDATA 'AlbionReborn\display-settings.json'))
    try{
        $value=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if($value.schemaVersion -eq 1 -and [string]$value.frameLimit -in @('0','30','60','90','120','144','165','240')){return [int]$value.frameLimit}
    }catch{}
    return 60
}
function Save-AlbionDisplaySettings {
    param([ValidateSet('','1080p','1440p','4k')][string]$Resolution='',[ValidateSet(-1,0,30,60,90,120,144,165,240)][int]$FrameLimit=-1,[string]$Path=(Join-Path $env:LOCALAPPDATA 'AlbionReborn\display-settings.json'))
    $document=@{schemaVersion=1;resolution=(Read-AlbionResolution $Path);frameLimit=(Read-AlbionFrameLimit $Path)}
    if($Resolution){$document.resolution=$Resolution}
    if($FrameLimit -ge 0){$document.frameLimit=$FrameLimit}
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temporary,($document | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temporary,$Path,($Path+'.previous'))}else{[IO.File]::Move($temporary,$Path)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Save-AlbionResolution {
    param([ValidateSet('1080p','1440p','4k')][string]$Resolution,[string]$Path=(Join-Path $env:LOCALAPPDATA 'AlbionReborn\display-settings.json'))
    Save-AlbionDisplaySettings -Resolution $Resolution -Path $Path
}
function Save-AlbionFrameLimit {
    param([ValidateSet(0,30,60,90,120,144,165,240)][int]$FrameLimit,[string]$Path=(Join-Path $env:LOCALAPPDATA 'AlbionReborn\display-settings.json'))
    Save-AlbionDisplaySettings -FrameLimit $FrameLimit -Path $Path
}

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
        $managed=Join-Path $env:LOCALAPPDATA ("AlbionReborn\games\$id\installation.json")
        if (!$Settings.ContainsKey($id) -and (Test-Path -LiteralPath $managed)) { $Settings[$id]=$managed }
        # A user-selected location always wins, including a disconnected drive.
        if (!$Settings.ContainsKey($id) -and (Test-Path -LiteralPath $candidates[$id] -PathType Leaf)) {
            $Settings[$id] = $candidates[$id]
        }
    }
}

function Get-AlbionLaunchPlan {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Entry,[ValidateSet('','1080p','1440p','4k')][string]$Resolution='',[ValidateSet(-1,0,30,60,90,120,144,165,240)][int]$FrameLimit=-1)
    if(!$Resolution){$Resolution=Read-AlbionResolution}
    if($FrameLimit -lt 0){$FrameLimit=Read-AlbionFrameLimit}
    if ($Id -notin @('fable1','fable2','fable3')) { throw 'Unknown game.' }
    if (!(Test-Path -LiteralPath $Entry -PathType Leaf)) { throw 'Game not found. Choose Locate to select its launcher.' }
    $fullPath = (Get-Item -LiteralPath $Entry).FullName
    if ($fullPath.Contains('"')) { throw 'The launch path contains an unsupported quote.' }
    $extension = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    $directory = Split-Path -Parent $fullPath
    if ($extension -eq '.json' -and (Split-Path -Leaf $fullPath) -eq 'installation.json' -and $Id -in @('fable2','fable3')) {
        $receipt=Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($receipt.schemaVersion -ne 1 -or $receipt.id -ne $Id -or $receipt.gameRoot.Contains('"')){throw 'Invalid managed game installation.'}
        $exe=if($Id -eq 'fable2'){'fable_2.exe'}else{'fable_3.exe'}
        $runtimeDirectory=Join-Path $directory 'runtime'
        $processPath=Join-Path $runtimeDirectory $exe
        if(!(Test-Path -LiteralPath $processPath) -or !(Test-Path -LiteralPath (Join-Path $receipt.gameRoot 'default.xex'))){throw 'Managed installation needs repair. Choose Set up / update.'}
        $arguments='--game_data_root="'+$receipt.gameRoot+'" --fullscreen=true --resolution='+$Resolution+' --resolution_scale=1'
        if($Id -eq 'fable3') {
            $arguments+=" --gpu_plugin=fable3 --direct_host_resolve=false --readback_resolve=none --fable3_static_draw_distance_multiplier=1 --fable3_mesh_occlusion_workaround=true --vsync=false --fable3_frame_limit=$FrameLimit --async_shader_compilation=false"
        }else{$arguments+=" --vsync=false --guest_vblank_pacing=false --frame_limit=$FrameLimit"}
        return [pscustomobject]@{Id=$Id;FileName=$processPath;Arguments=$arguments;WorkingDirectory=$runtimeDirectory;ProcessPath=$processPath;Entry=$fullPath}
    }
    if ($extension -eq '.ps1' -and $Id -eq 'fable3') {
        if ((Split-Path -Leaf $fullPath) -ne 'run.ps1') { throw 'Choose Fable III-PC\tools\run.ps1 to retain its rendering fixes.' }
        $project = Split-Path -Parent $directory
        $processPath = Join-Path $project 'out\build\win-amd64-release\fable_3.exe'
        if (!(Test-Path -LiteralPath $processPath -PathType Leaf)) { throw 'Fable III needs a native build. Build it in its own project first.' }
        return [pscustomobject]@{
            Id=$Id; FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            Arguments=('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $fullPath + '"')
            WorkingDirectory=$project; ProcessPath=$processPath; Entry=$fullPath; DisplayResolution=$Resolution; DisplayFrameLimit=$FrameLimit
        }
    }
    if ($extension -ne '.exe') { throw 'Choose a Windows game executable (.exe), or Fable III tools\run.ps1.' }
    if ($Id -eq 'fable2' -and (Split-Path -Leaf $fullPath) -ne 'fable_2.exe') {
        throw 'Choose the playable fable_2.exe so your tested configuration is used.'
    }
    if ($Id -eq 'fable3') { throw 'Choose Fable III-PC\tools\run.ps1 to preserve the tested rendering settings.' }
    return [pscustomobject]@{
        Id=$Id; FileName=$fullPath; Arguments=$(if($Id -eq 'fable2'){"--fullscreen=true --resolution=$Resolution --resolution_scale=1 --vsync=false --guest_vblank_pacing=false --frame_limit=$FrameLimit"}else{''}); WorkingDirectory=$directory
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
    if($Plan.PSObject.Properties.Name -contains 'DisplayResolution'){$start.EnvironmentVariables['ALBION_RESOLUTION']=$Plan.DisplayResolution}
    if($Plan.PSObject.Properties.Name -contains 'DisplayFrameLimit'){$start.EnvironmentVariables['ALBION_FPS']=[string]$Plan.DisplayFrameLimit}
    # Leave the parent's environment alone; disable the old noisy FPS logger only in Fable II.
    if ($Plan.Id -eq 'fable2') { $start.EnvironmentVariables.Remove('FABLE2_FPS_METER') }
    return [Diagnostics.Process]::Start($start)
}
