param([Parameter(Mandatory)][string]$Distribution)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Update.Core.ps1')
$build=Get-Content (Join-Path $Distribution 'latest-build.json') -Raw | ConvertFrom-Json
$manifest=Get-Content (Join-Path $Distribution 'albion-update.json') -Raw | ConvertFrom-Json
Test-AlbionUpdateManifest $manifest
if((Get-AlbionFileHash $build.portable) -ne $manifest.sha256 -or (Get-Item $build.portable).Length -ne $manifest.bytes){throw 'Published bundle would fail updater integrity checks.'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($build.portable)
try {
    foreach($entry in $archive.Entries){if($entry.FullName -match '(?i)\.(iso|xex|bnk|wav|xma|pdb|dmp)$|(^|/)(saves|cache|game)/'){throw "Unexpected game content or state: $($entry.FullName)"}}
} finally {$archive.Dispose()}
$extracted=Join-Path $PSScriptRoot ('work\release-tests\'+[guid]::NewGuid().ToString('N'))
Expand-AlbionRuntime $build.portable $extracted
$catalog=Get-AlbionRuntimeCatalog (Join-Path $extracted 'packages')
foreach($runtime in $catalog.runtimes){
    $zip=Join-Path $extracted ('packages\'+$runtime.package)
    if((Get-AlbionFileHash $zip) -ne $runtime.sha256){throw 'Runtime catalog integrity check failed.'}
    $unpacked=Join-Path $extracted ('verify-'+$runtime.id)
    Expand-AlbionRuntime $zip $unpacked
    $package=Get-Content (Join-Path $unpacked 'package.json') -Raw | ConvertFrom-Json
    if($package.id -ne $runtime.id -or $package.version -ne $runtime.version){throw 'Runtime identity mismatch.'}
    foreach($file in Get-ChildItem $unpacked -Recurse -File){
        $relative=$file.FullName.Substring($unpacked.Length+1).Replace('\','/')
        if($relative -eq 'package.json'){continue}
        $listed=@($package.files | Where-Object {$_.path.Replace('\','/') -eq $relative})
        if($listed.Count -ne 1 -or (Get-AlbionFileHash $file.FullName) -ne $listed[0].sha256){throw 'Unlisted or corrupt runtime file.'}
        if($relative -match '(?i)\.(iso|xex|bnk|wav|xma|pdb|dmp)$|(^|/)(saves|cache|game)/'){throw 'Game content/state found in runtime package.'}
    }
}
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $ps -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $extracted 'AlbionReborn.ps1') -Check
if($LASTEXITCODE){throw 'Clean bundle launch validation failed.'}
Write-Output 'Passed: bundle/catalog/file integrity, runtime identity, content exclusion, and clean launcher check.'
