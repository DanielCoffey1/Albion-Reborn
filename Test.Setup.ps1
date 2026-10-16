param([switch]$RealInstallations)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
. (Join-Path $PSScriptRoot 'Installer.Core.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
function Assert($Value,[string]$Message){if(!$Value){throw $Message}}
$root=Join-Path $PSScriptRoot ('work\setup-tests\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$badZip=Join-Path $root 'unsafe.zip'
$zip=[IO.Compression.ZipFile]::Open($badZip,[IO.Compression.ZipArchiveMode]::Create)
$entry=$zip.CreateEntry('../escape.txt');$writer=[IO.StreamWriter]::new($entry.Open());$writer.Write('escape');$writer.Dispose();$zip.Dispose()
$rejected=$false
try{Expand-AlbionRuntime $badZip (Join-Path $root 'expanded')}catch{$rejected=$true}
Assert $rejected 'Archive path traversal was not rejected.'
Assert (!(Test-Path (Join-Path $root 'escape.txt'))) 'Archive escaped its destination.'
$fake=Join-Path $root 'unsupported';New-Item -ItemType Directory -Path (Join-Path $fake 'data') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $fake 'default.xex'),'Not a supported game executable')
$runtime=@((Get-AlbionRuntimeCatalog).runtimes | Where-Object id -eq 'fable3')[0]
$rejected=$false
try{$null=Test-AlbionGameContent $fake $runtime}catch{$rejected=$true}
Assert $rejected 'An unsupported game executable was accepted.'

if($RealInstallations) {
    $library=Join-Path $root 'library'
    $worker=Join-Path $PSScriptRoot 'Install-Game.ps1'
    $powershell="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sources=@{fable2=(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Fable 2\Recompiled\Fable 2 1.5.0');fable3=(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Fable 3\Fable-III-PC\game')}
    foreach($id in @('fable2','fable3')) {
        $status=Join-Path $root ($id+'.json')
        & $powershell -NoProfile -ExecutionPolicy Bypass -File $worker -Id $id -Source $sources[$id] -StatusPath $status -LibraryRoot $library
        $result=Get-Content $status -Raw | ConvertFrom-Json
        Assert ($result.state -eq 'complete') "Folder install failed: $($result.detail)"
        $plan=Get-AlbionLaunchPlan $id $result.entry
        Assert (Test-Path $plan.FileName) 'Managed launch executable is missing.'
        Assert ($plan.Arguments.Contains('--game_data_root="')) 'Managed launch lost its content path.'
        if($id -eq 'fable3'){
            Assert ($plan.Arguments.Contains('--fable3_mesh_occlusion_workaround=true') -and $plan.Arguments.Contains('--async_shader_compilation=false')) 'Fable III rendering fixes were lost.'
            Assert ($plan.Arguments.Contains('--fullscreen=true') -and $plan.Arguments.Contains('--fable3_frame_limit=60') -and $plan.Arguments -match '--resolution_scale=[123]( |$)') 'Fable III fullscreen/60 FPS/display profile was lost.'
        }
    }
    $config=Join-Path $library 'fable2\runtime\fable2_config.toml'
    [IO.File]::AppendAllText($config,"`n# preserve-this-setting`n")
    $before=(Get-FileHash $config -Algorithm SHA256).Hash
    $save=Join-Path $library 'fable2\runtime\saves\sentinel.txt';New-Item -ItemType Directory -Path (Split-Path -Parent $save) -Force | Out-Null
    [IO.File]::WriteAllText($save,'preserve-this-save')
    $status=Join-Path $root 'update.json'
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $worker -Id fable2 -Source $sources.fable2 -StatusPath $status -LibraryRoot $library
    Assert ((Get-Content $status -Raw | ConvertFrom-Json).state -eq 'complete') 'Runtime update failed.'
    Assert ((Get-FileHash $config -Algorithm SHA256).Hash -eq $before) 'An update overwrote existing settings.'
    Assert ([IO.File]::ReadAllText($save) -eq 'preserve-this-save') 'An update modified saves.'
    $status=Join-Path $root 'cancel.json';[IO.File]::WriteAllText(($status+'.cancel'),'cancel')
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $worker -Id fable3 -Source $sources.fable3 -StatusPath $status -LibraryRoot (Join-Path $root 'cancel-library')
    Assert ((Get-Content $status -Raw | ConvertFrom-Json).state -eq 'error') 'Cancellation was ignored.'
    Assert (!(Test-Path (Join-Path $root 'cancel-library\fable3\installation.json'))) 'Cancelled setup registered a partial game.'
    Write-Output "Real folder install/update checks passed. Isolated test library: $library"
}
Write-Output 'Passed: archive traversal rejection, unsupported-version gate, and selected setup checks. Existing installations were not modified.'
