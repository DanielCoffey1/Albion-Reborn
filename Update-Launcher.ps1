param([ValidateSet('Check','Apply')][string]$Mode='Check',[Parameter(Mandatory)][string]$StatusPath,[string]$CurrentVersion='', [int]$LauncherProcessId=0)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
$lock=$null
try {
    if($Mode -eq 'Check'){
        $update=Get-AlbionOnlineUpdate
        $available=$update -and (!$CurrentVersion -or (Compare-AlbionBuild $update.version $CurrentVersion) -gt 0)
        Write-AlbionJson @{state=if($available){'available'}else{'current'};manifest=$update} $StatusPath
        exit 0
    }
    $update=(Get-Content $StatusPath -Raw -Encoding UTF8 | ConvertFrom-Json).manifest
    Test-AlbionUpdateManifest $update
    $updates=Join-Path $env:LOCALAPPDATA 'AlbionReborn\updates'
    [IO.Directory]::CreateDirectory($updates) | Out-Null
    $lock=[IO.File]::Open((Join-Path $updates 'update.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    Write-AlbionJson @{state='downloading';manifest=$update} $StatusPath
    $archive=Join-Path $updates ([guid]::NewGuid().ToString('N')+'.zip')
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $ProgressPreference='SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing -Uri $update.url -OutFile $archive -TimeoutSec 300
    if((Get-Item $archive).Length -ne [long]$update.bytes -or (Get-AlbionFileHash $archive) -ne $update.sha256){throw 'Update download failed its SHA-256 check.'}
    Write-AlbionJson @{state='ready';manifest=$update} $StatusPath
    if($LauncherProcessId -gt 0){
        $launcher=Get-Process -Id $LauncherProcessId -ErrorAction SilentlyContinue
        if($launcher -and !$launcher.WaitForExit(60000)){throw 'The launcher did not close. Try updating again.'}
    }
    $target=Install-AlbionUpdate -Manifest $update -Archive $archive -AppParent (Join-Path $env:LOCALAPPDATA 'AlbionReborn\App') -LibraryRoot (Join-Path $env:LOCALAPPDATA 'AlbionReborn\games')
    Write-AlbionJson @{state='complete';version=$update.version;path=$target} $StatusPath
} catch {
    Write-AlbionJson @{state='error';detail=$_.Exception.Message} $StatusPath
    if($Mode -eq 'Apply'){
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($_.Exception.Message+' Your previous launcher and game files remain available.','Albion Reborn update') | Out-Null
        if($LauncherProcessId -le 0 -or !(Get-Process -Id $LauncherProcessId -ErrorAction SilentlyContinue)){
            Start-Process -FilePath (Join-Path $PSScriptRoot 'out\AlbionReborn.exe') -WorkingDirectory $PSScriptRoot
        }
    }
    exit 1
} finally {if($lock){$lock.Dispose()}}
