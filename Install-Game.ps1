param([Parameter(Mandatory)][ValidateSet('fable2','fable3')][string]$Id,
      [Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$StatusPath,
      [string]$PackageDirectory='',
      [string]$LibraryRoot=(Join-Path $env:LOCALAPPDATA 'AlbionReborn\games'))
$ErrorActionPreference='Stop'
if(!$PackageDirectory){$PackageDirectory=Join-Path $PSScriptRoot 'packages'}
. (Join-Path $PSScriptRoot 'Installer.Core.ps1')
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
$operation=[guid]::NewGuid().ToString('N')
$stage=Join-Path $LibraryRoot ('.setup\'+$operation)
$install=Join-Path $LibraryRoot $Id
$receiptPath=Join-Path $install 'installation.json'
$changed=@()
$committed=$false
function Report([string]$Phase,[int]$Percent,[string]$Detail='') {
    Write-AlbionJson @{state='working';phase=$Phase;percent=$Percent;detail=$Detail} $StatusPath
}
function Check-Cancel {if(Test-Path -LiteralPath ($StatusPath+'.cancel')){throw 'Setup cancelled. Original files and existing saves were left intact.'}}
try {
    Report 'Checking game version' 2
    $catalog=Get-AlbionRuntimeCatalog $PackageDirectory
    $runtime=@($catalog.runtimes | Where-Object id -eq $Id)[0]
    if(!$runtime){throw 'This game has no runtime package yet.'}
    $gameHash=Test-AlbionGameContent $Source $runtime
    Check-Cancel
    if(Test-Path -LiteralPath $receiptPath) {
        $old=Get-Content $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $oldPlan=Get-AlbionLaunchPlan $Id $receiptPath
        if(@(Get-AlbionGameProcess $oldPlan).Count){throw 'Close the game before installing or updating its runtime.'}
    }
    Report 'Verifying runtime package' 6
    if([IO.Path]::GetFileName($runtime.package) -ne $runtime.package){throw 'Invalid package filename.'}
    $archive=Join-Path $PackageDirectory $runtime.package
    if((Get-AlbionFileHash $archive) -ne $runtime.sha256){throw 'Runtime package integrity check failed.'}
    $runtimeStage=Join-Path $stage 'runtime'
    Expand-AlbionRuntime $archive $runtimeStage
    $manifest=Get-Content (Join-Path $runtimeStage 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($manifest.schemaVersion -ne 1 -or $manifest.id -ne $Id -or $manifest.version -ne $runtime.version){throw 'Runtime manifest does not match the catalog.'}
    foreach($file in $manifest.files) {
        $full=[IO.Path]::GetFullPath((Join-Path $runtimeStage $file.path))
        if(!$full.StartsWith([IO.Path]::GetFullPath($runtimeStage)+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid runtime manifest path.'}
        if((Get-AlbionFileHash $full) -ne $file.sha256){throw "Runtime file integrity check failed: $($file.path)"}
    }
    Check-Cancel
    if([IO.Path]::GetExtension($Source) -eq '.iso') {
        Report 'Extracting your game files' 10
        $contentStage=Join-Path $stage 'content'
        $script:lastProgress=[datetime]::MinValue
        $progress=[Action[long,long,string]]{
            param($done,$total,$name)
            if(([datetime]::Now-$script:lastProgress).TotalMilliseconds -gt 150) {
                Report 'Extracting your game files' (10+[int](75*$done/[double]$total)) $name
                $script:lastProgress=[datetime]::Now
            }
        }
        $cancel=[Func[bool]]{Test-Path -LiteralPath ($StatusPath+'.cancel')}
        [Albion.Content]::ExtractIso($Source,$contentStage,$gameHash,$progress,$cancel)
        # Keep every extraction as its own content revision; existing content stays intact.
        $gameRoot=Join-Path $install ('content\'+$operation)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $gameRoot)) | Out-Null
        [IO.Directory]::Move($contentStage,$gameRoot)
    } else {
        $gameRoot=if(Test-Path -LiteralPath $Source -PathType Leaf){Split-Path -Parent $Source}else{$Source}
        $gameRoot=[IO.Path]::GetFullPath($gameRoot)
    }
    Check-Cancel
    Report 'Installing the runtime' 88
    $runtimeRoot=Join-Path $install 'runtime'
    $backup=Join-Path $install ('backups\'+$operation)
    # Once commit begins it completes or restores replaced files. Cancellation is
    # accepted before this point, never halfway through a runtime transaction.
    foreach($file in $manifest.files) {
        $target=Join-Path $runtimeRoot $file.path
        if($file.seed -and (Test-Path -LiteralPath $target)){continue}
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        if(Test-Path -LiteralPath $target) {
            $saved=Join-Path $backup $file.path
            [IO.Directory]::CreateDirectory((Split-Path -Parent $saved)) | Out-Null
            [IO.File]::Copy($target,$saved,$false)
            $changed+=,@{target=$target;backup=$saved}
        }
        if(!(Test-Path -LiteralPath $target)){$changed+=,@{target=$target;backup=$null}}
        [IO.File]::Copy((Join-Path $runtimeStage $file.path),$target,$true)
    }
    $receipt=@{schemaVersion=1;id=$Id;version=$runtime.version;gameRoot=$gameRoot;xexSha256=$gameHash;installedUtc=[datetime]::UtcNow.ToString('o');packageSha256=$runtime.sha256}
    Write-AlbionJson $receipt $receiptPath
    $committed=$true
    if($Id -eq 'fable2') {
        $decoder=Join-Path $PSScriptRoot 'tools\vgmstream\vgmstream-cli.exe'
        $audioRoot=Join-Path $env:LOCALAPPDATA 'AlbionReborn\audio'
        $audioReady=(Test-Path -LiteralPath (Join-Path $audioRoot 'menu.wav')) -and (Test-Path -LiteralPath (Join-Path $audioRoot 'theresa.wav'))
        if((Test-Path -LiteralPath $decoder) -and !$audioReady) {
            Report 'Preparing launcher music' 96
            try {& (Join-Path $PSScriptRoot 'Prepare-Audio.ps1') -GameRoot $gameRoot -DecoderPath $decoder | Out-Null}catch{} # Optional audio never invalidates a working installation.
        }
    }
    Write-AlbionJson @{state='complete';phase='Ready to play';percent=100;detail=$runtime.name;entry=$receiptPath} $StatusPath
} catch {
    if(!$committed){foreach($item in $changed){try{if($item.backup){[IO.File]::Copy($item.backup,$item.target,$true)}elseif([IO.File]::Exists($item.target)){[IO.File]::Delete($item.target)}}catch{}}}
    Write-AlbionJson @{state='error';phase='Setup stopped';percent=0;detail=$_.Exception.Message} $StatusPath
    exit 1
}
