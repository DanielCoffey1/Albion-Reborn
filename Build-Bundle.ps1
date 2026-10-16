param([string]$PackageDirectory='', [string]$DecoderDirectory='', [string]$Destination='', [string]$ReleaseTag='v0.3.1-preview', [string]$BuildId='')
$ErrorActionPreference='Stop'
if(!$PackageDirectory){$PackageDirectory=Join-Path $PSScriptRoot 'packages'}
if(!$DecoderDirectory){$DecoderDirectory=Join-Path $env:LOCALAPPDATA 'AlbionReborn\tools\vgmstream-r2117'}
if(!$Destination){$Destination=Join-Path $PSScriptRoot 'out\distribution'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stamp='0.3.1-preview-'+[datetime]::UtcNow.ToString('yyyyMMddHHmmss')
if($BuildId){if($BuildId -notmatch '^\d+\.\d+\.\d+-preview-\d{14}$'){throw 'Invalid build ID.'};$stamp=$BuildId}
$stage=Join-Path $PSScriptRoot ('work\bundles\'+$stamp)
New-Item -ItemType Directory -Path $stage,$Destination -Force | Out-Null
@{version=$stamp;channel='preview'} | ConvertTo-Json | Set-Content (Join-Path $stage 'build-info.json') -Encoding UTF8
$files=@('AlbionReborn.ps1','Launcher.Core.ps1','Launcher.Audio.ps1','Launcher.Setup.ps1','Launcher.Update.ps1','Update.Core.ps1','Update-Launcher.ps1','Installer.Core.ps1','Install-Game.ps1','Prepare-Audio.ps1','Launcher.xaml','Setup.xaml','Start.cmd','README.md','LICENSE')
foreach($file in $files){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $stage $file)}
foreach($folder in @('out','assets','packages')){New-Item -ItemType Directory -Path (Join-Path $stage $folder) -Force | Out-Null}
foreach($file in @('AlbionReborn.exe','Albion.Content.dll')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('out\'+$file)) -Destination (Join-Path $stage ('out\'+$file))}
foreach($file in @('AlbionReborn.ico','albion-landscape.png','README.md','background.md','art-sources.json')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('assets\'+$file)) -Destination (Join-Path $stage ('assets\'+$file))}
if(Test-Path (Join-Path $PSScriptRoot 'assets\covers')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'assets\covers') -Destination (Join-Path $stage 'assets\covers') -Recurse}
$catalog=Get-Content (Join-Path $PackageDirectory 'catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Copy-Item -LiteralPath (Join-Path $PackageDirectory 'catalog.json') -Destination (Join-Path $stage 'packages\catalog.json')
foreach($runtime in $catalog.runtimes){
    if([IO.Path]::GetFileName($runtime.package) -ne $runtime.package){throw 'Invalid runtime package path.'}
    $archive=Join-Path $PackageDirectory $runtime.package
    if((Get-FileHash $archive -Algorithm SHA256).Hash -ne $runtime.sha256){throw 'Runtime package does not match catalog.'}
    Copy-Item -LiteralPath $archive -Destination (Join-Path $stage ('packages\'+$runtime.package))
}
if(Test-Path (Join-Path $DecoderDirectory 'vgmstream-cli.exe')) {
    $decoderTarget=Join-Path $stage 'tools\vgmstream';New-Item -ItemType Directory -Path $decoderTarget -Force | Out-Null
    Get-ChildItem -LiteralPath $DecoderDirectory -File | Where-Object {$_.Extension -in @('.exe','.dll','.md') -or $_.Name -eq 'COPYING'} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $decoderTarget $_.Name)}
}
# The bundle includes current artwork and runtime binaries for local preview.
# No existing files are stripped or deleted, and this script never uploads.
$payload=Join-Path $Destination ('AlbionReborn-'+$stamp+'.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($stage,$payload,[IO.Compression.CompressionLevel]::Optimal,$false)
$hash=(Get-FileHash $payload -Algorithm SHA256).Hash
if($ReleaseTag -notmatch '^[A-Za-z0-9._-]+$'){throw 'Invalid release tag.'}
@{schemaVersion=1;version=$stamp;bytes=(Get-Item $payload).Length;sha256=$hash;url=('https://github.com/DanielCoffey1/Albion-Reborn/releases/download/'+$ReleaseTag+'/'+[IO.Path]::GetFileName($payload))} | ConvertTo-Json | Set-Content (Join-Path $Destination 'albion-update.json') -Encoding UTF8
$source=Get-Content (Join-Path $PSScriptRoot 'packaging\SetupHost.cs') -Raw
$source=$source.Replace('__BUILD_ID__',$stamp).Replace('__PAYLOAD_HASH__',$hash)
$generated=Join-Path $stage 'SetupHost.generated.cs'
[IO.File]::WriteAllText($generated,$source)
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$setup=Join-Path $Destination ('AlbionReborn-Setup-'+$stamp+'.exe')
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$setup" "/win32icon:$PSScriptRoot\assets\AlbionReborn.ico" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:Microsoft.CSharp.dll "/resource:$payload,AlbionPayload.zip" $generated
if($LASTEXITCODE){throw 'Installer build failed.'}
@{version=$stamp;setup=$setup;setupSha256=(Get-FileHash $setup -Algorithm SHA256).Hash;portable=$payload;portableSha256=$hash} | ConvertTo-Json | Set-Content (Join-Path $Destination 'latest-build.json') -Encoding UTF8
Write-Output "Built offline installer: $setup"
Write-Output "Built portable bundle: $payload"
Write-Output 'Preview artifacts remain local. No game dumps, content banks, saves, or caches were bundled; existing source installations were left intact.'
