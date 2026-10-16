param([switch]$Bundle,[string]$Distribution='', [string]$PackageDirectory='', [string]$AnniversarySource='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
function Assert($Value,[string]$Message){if(!$Value){throw $Message}}
Assert ((Compare-AlbionBuild '0.10.0-preview-20261015000000' '0.3.0-preview-20261016000000') -gt 0) 'Numeric version ordering failed.'
Assert ((Compare-AlbionBuild '0.3.0-preview-20261016000000' '0.3.0-preview-20261015000000') -gt 0) 'Build ordering failed.'
$manifest=[pscustomobject]@{schemaVersion=1;version='0.3.0-preview-20261015000000';url='https://github.com/DanielCoffey1/Albion-Reborn/releases/download/v0.3.0-preview/AlbionReborn-test.zip';sha256=('A'*64);bytes=10}
Test-AlbionUpdateManifest $manifest
foreach($bom in @($true,$false)){
    $encoding=[Text.UTF8Encoding]::new($bom)
    $bytes=$encoding.GetPreamble()+$encoding.GetBytes(($manifest | ConvertTo-Json))
    $stream=[IO.MemoryStream]::new([byte[]]$bytes)
    try{$parsed=Read-AlbionUpdateJson $stream;Test-AlbionUpdateManifest $parsed}finally{$stream.Dispose()}
}
$manifest.url='https://example.com/AlbionReborn-test.zip';$rejected=$false
try{Test-AlbionUpdateManifest $manifest}catch{$rejected=$true}
Assert $rejected 'Foreign update origin was accepted.'
if($Bundle){
    if(!$Distribution){$Distribution=Join-Path $PSScriptRoot 'out\distribution'}
    if(!$PackageDirectory){$PackageDirectory=Join-Path $PSScriptRoot 'packages'}
    $build=Get-Content (Join-Path $Distribution 'latest-build.json') -Raw | ConvertFrom-Json
    $manifest=Get-Content (Join-Path $Distribution 'albion-update.json') -Raw | ConvertFrom-Json
    $root=Join-Path $PSScriptRoot ('work\update-tests\'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $old=Join-Path $root 'App\old-version';[IO.Directory]::CreateDirectory($old) | Out-Null
    [IO.File]::WriteAllText((Join-Path $old 'sentinel.txt'),'old launcher')
    $library=Join-Path $root 'games';[IO.Directory]::CreateDirectory($library) | Out-Null
    [IO.File]::WriteAllText((Join-Path $library 'save.sav'),'saved progress')
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $source=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Fable 2\Recompiled\Fable 2 1.5.0'
    if(Test-Path $source){
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-Game.ps1') -Id fable2 -Source $source -LibraryRoot $library -PackageDirectory $PackageDirectory -StatusPath (Join-Path $root 'install.json')
        if($LASTEXITCODE){throw 'Test game setup failed.'}
        $receiptPath=Join-Path $library 'fable2\installation.json'
        $receipt=Get-Content $receiptPath -Raw | ConvertFrom-Json;$receipt.version='older-test-version';Write-AlbionJson $receipt $receiptPath
        $config=Join-Path $library 'fable2\runtime\fable_2.toml'
        [IO.File]::AppendAllText($config,"`n# update preservation sentinel`n")
        $configHash=Get-AlbionFileHash $config
    }
    if($AnniversarySource){
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-Game.ps1') -Id fable1 -Source $AnniversarySource -LibraryRoot $library -PackageDirectory $PackageDirectory -StatusPath (Join-Path $root 'install-anniversary.json')
        if($LASTEXITCODE){throw 'Anniversary update-test setup failed.'}
        $receiptPath=Join-Path $library 'fable1\installation.json'
        $receipt=Get-Content $receiptPath -Raw|ConvertFrom-Json;$receipt.version='older-test-version';Write-AlbionJson $receipt $receiptPath
        $anniversarySave=Join-Path $library 'fable1\runtime\saves\sentinel.txt'
        [IO.Directory]::CreateDirectory((Split-Path $anniversarySave))|Out-Null
        [IO.File]::WriteAllText($anniversarySave,'Anniversary save sentinel')
    }
    $wrong=$manifest | ConvertTo-Json | ConvertFrom-Json;$wrong.sha256='0'*64
    $rejected=$false
    try{Install-AlbionUpdate -Manifest $wrong -Archive $build.portable -AppParent (Join-Path $root 'App') -LibraryRoot $library -NoShortcut -NoLaunch}catch{$rejected=$true}
    Assert $rejected 'Corrupt update was accepted.'
    Assert (@(Get-ChildItem (Join-Path $root 'App') -Directory).Count -eq 1) 'Failed verification changed the app installation.'
    $target=Install-AlbionUpdate -Manifest $manifest -Archive $build.portable -AppParent (Join-Path $root 'App') -LibraryRoot $library -NoShortcut -NoLaunch
    Assert (Test-Path (Join-Path $target 'out\AlbionReborn.exe')) 'Updated executable missing.'
    Assert ((Get-Content (Join-Path $old 'sentinel.txt') -Raw) -eq 'old launcher') 'Previous launcher changed.'
    Assert ((Get-Content (Join-Path $library 'save.sav') -Raw) -eq 'saved progress') 'Game library changed during launcher update.'
    if($AnniversarySource){
        Assert (Test-Path (Join-Path $target 'runtime-update-fable1.json')) 'Anniversary was omitted from automatic runtime updates.'
        Assert ([IO.File]::ReadAllText($anniversarySave) -eq 'Anniversary save sentinel') 'Automatic Anniversary update changed saved state.'
        $receipt=Get-Content (Join-Path $library 'fable1\installation.json') -Raw|ConvertFrom-Json
        Assert ($receipt.version -ne 'older-test-version') 'Anniversary runtime receipt was not updated.'
    }
    if($configHash){
        Assert ((Get-AlbionFileHash $config) -eq $configHash) 'Runtime update changed an existing seed config.'
        Assert (Test-Path (Join-Path $target 'runtime-update-fable2.json')) 'Installed game runtime was not updated.'
    }
    Write-Output "Clean bundle update and hash rejection passed: $target"
}
Write-Output 'Passed: update origin validation and version ordering.'
