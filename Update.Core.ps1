. (Join-Path $PSScriptRoot 'Installer.Core.ps1')
function Test-AlbionUpdateManifest($Manifest) {
    if($Manifest.schemaVersion -ne 1 -or $Manifest.version -notmatch '^\d+\.\d+\.\d+-preview-\d{14}$' -or $Manifest.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $Manifest.bytes -le 0 -or $Manifest.bytes -gt 536870912){throw 'Invalid update manifest.'}
    if($Manifest.url -notmatch '^https://github\.com/DanielCoffey1/Albion-Reborn/releases/download/[A-Za-z0-9._-]+/AlbionReborn-[A-Za-z0-9._-]+\.zip$'){throw 'Update URL is outside the Albion Reborn release repository.'}
}
function Compare-AlbionBuild([string]$Left,[string]$Right) {
    foreach($value in @($Left,$Right)){if($value -notmatch '^\d+\.\d+\.\d+-preview-\d{14}$'){throw 'Invalid build version.'}}
    $a=$Left.Split('-');$b=$Right.Split('-');$compare=([version]$a[0]).CompareTo([version]$b[0])
    if($compare -ne 0){return $compare};return [string]::CompareOrdinal($a[2],$b[2])
}
function Read-AlbionUpdateJson([IO.Stream]$Stream) {
    $reader=[IO.StreamReader]::new($Stream,[Text.Encoding]::UTF8,$true,1024,$true)
    try{return ($reader.ReadToEnd() | ConvertFrom-Json)}finally{$reader.Dispose()}
}
function Get-AlbionOnlineUpdate {
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $headers=@{'User-Agent'='AlbionReborn-Updater';Accept='application/vnd.github+json'}
    $releases=Invoke-RestMethod -UseBasicParsing -Headers $headers -TimeoutSec 25 -Uri 'https://api.github.com/repos/DanielCoffey1/Albion-Reborn/releases?per_page=30'
    $best=$null
    foreach($release in $releases){
        if($release.draft){continue}
        $asset=@($release.assets | Where-Object {$_.name -eq 'albion-update.json' -and $_.state -eq 'uploaded'})
        if($asset.Count -ne 1){continue}
        $url=[string]$asset[0].browser_download_url
        if($url -notmatch '^https://github\.com/DanielCoffey1/Albion-Reborn/releases/download/[A-Za-z0-9._-]+/albion-update\.json$'){continue}
        if([long]$asset[0].size -gt 65536){throw 'Update manifest is too large.'}
        $response=Invoke-WebRequest -UseBasicParsing -Headers $headers -TimeoutSec 25 -Uri $url
        $response.RawContentStream.Position=0
        try{$manifest=Read-AlbionUpdateJson $response.RawContentStream}finally{$response.RawContentStream.Dispose()}
        Test-AlbionUpdateManifest $manifest
        $payload=@($release.assets | Where-Object {$_.browser_download_url -ceq $manifest.url -and $_.state -eq 'uploaded'})
        if($payload.Count -ne 1 -or [long]$payload[0].size -ne [long]$manifest.bytes){throw 'Release asset does not match its update manifest.'}
        if($payload[0].digest -and $payload[0].digest -ne ('sha256:'+([string]$manifest.sha256).ToLowerInvariant())){throw 'Release hash does not match update manifest.'}
        if(!$best -or (Compare-AlbionBuild $manifest.version $best.version) -gt 0){$best=$manifest}
    }
    return $best
}
function Install-AlbionUpdate {
    param($Manifest,[string]$Archive,[string]$AppParent,[string]$LibraryRoot,[switch]$NoShortcut,[switch]$NoLaunch)
    Test-AlbionUpdateManifest $Manifest
    if((Get-Item -LiteralPath $Archive).Length -ne [long]$Manifest.bytes -or (Get-AlbionFileHash $Archive) -ne $Manifest.sha256){throw 'Update download failed its SHA-256 check. The current installation is unchanged.'}
    if(@(Get-Process -Name fable_2,fable_3 -ErrorAction SilentlyContinue).Count){throw 'Close the running game before updating.'}
    $stage=Join-Path $AppParent ('.update-'+[guid]::NewGuid().ToString('N'))
    Expand-AlbionRuntime $Archive $stage
    $build=Get-Content (Join-Path $stage 'build-info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($build.version -ne $Manifest.version){throw 'The downloaded launcher has a different build version.'}
    foreach($file in @('out\AlbionReborn.exe','out\Albion.Content.dll','Install-Game.ps1','Launcher.Update.ps1','packages\catalog.json')){if(!(Test-Path -LiteralPath (Join-Path $stage $file))){throw "Update is missing $file"}}
    $catalog=Get-AlbionRuntimeCatalog (Join-Path $stage 'packages')
    foreach($runtime in $catalog.runtimes){
        if([IO.Path]::GetFileName($runtime.package) -ne $runtime.package){throw 'Invalid bundled package path.'}
        if((Get-AlbionFileHash (Join-Path $stage ('packages\'+$runtime.package))) -ne $runtime.sha256){throw 'A bundled runtime failed its integrity check.'}
    }
    $target=Join-Path $AppParent ($Manifest.version+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.Directory]::Move($stage,$target)
    foreach($runtime in $catalog.runtimes){
        $receiptPath=Join-Path $LibraryRoot ($runtime.id+'\installation.json')
        if(!(Test-Path -LiteralPath $receiptPath)){continue}
        $receipt=Get-Content $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($receipt.version -eq $runtime.version -and $receipt.packageSha256 -eq $runtime.sha256){continue}
        $result=Join-Path $target ('runtime-update-'+$runtime.id+'.json')
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $target 'Install-Game.ps1') -Id $runtime.id -Source $receipt.gameRoot -StatusPath $result -LibraryRoot $LibraryRoot
        if($LASTEXITCODE -ne 0){$failure=Get-Content $result -Raw | ConvertFrom-Json;throw ('Game runtime update failed: '+$failure.detail)}
    }
    $exe=Join-Path $target 'out\AlbionReborn.exe'
    if(!$NoShortcut){
        $shell=New-Object -ComObject WScript.Shell
        $link=$shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Albion Reborn.lnk'))
        $link.TargetPath=$exe;$link.WorkingDirectory=$target;$link.IconLocation=(Join-Path $target 'assets\AlbionReborn.ico')+',0';$link.Save()
    }
    if(!$NoLaunch){Start-Process -FilePath $exe -WorkingDirectory $target}
    return $target
}
