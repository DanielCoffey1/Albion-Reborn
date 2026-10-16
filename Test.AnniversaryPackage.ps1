param([Parameter(Mandatory)][string]$PackageDirectory,[Parameter(Mandatory)][string]$Source)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Installer.Core.ps1')
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
function Assert($value,$message){if(!$value){throw $message}}
$catalog=Get-AlbionRuntimeCatalog $PackageDirectory
$runtime=@($catalog.runtimes|Where-Object id -eq fable1)[0]
$null=Test-AlbionGameContent $Source $runtime
$root=Join-Path $PSScriptRoot ('work\anniversary-package-tests\'+[guid]::NewGuid().ToString('N'))
$library=Join-Path $root 'library'
$status=Join-Path $root 'install.json'
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-Game.ps1') -Id fable1 -Source $Source -StatusPath $status -PackageDirectory $PackageDirectory -LibraryRoot $library
$result=Get-Content $status -Raw|ConvertFrom-Json
Assert ($result.state -eq 'complete') "Anniversary installation failed: $($result.detail)"
$receipt=Get-Content $result.entry -Raw|ConvertFrom-Json
$contentFile=Join-Path $receipt.gameRoot 'WellingtonGame/CookedXbox360/AkAudio.xxx'
Assert (Test-Path $contentFile) 'Anniversary content was not extracted.'
$beforeContent=Get-AlbionFileHash $contentFile
$plan=Get-AlbionLaunchPlan fable1 $result.entry -Resolution 1440p -FrameLimit 120
Assert ($plan.Arguments.Contains('--anniversary_frame_limit=30') -and $plan.Arguments.Contains('--readback_resolve=full')) 'Managed rendering/pacing fixes missing.'
Assert ($plan.Arguments.Contains('--resolution=1440p') -and $plan.Arguments.Contains('--async_shader_compilation=false')) 'Display/shader settings lost.'
$sentinel=Join-Path $library 'fable1/runtime/saves/sentinel.txt'
[IO.Directory]::CreateDirectory((Split-Path $sentinel))|Out-Null
[IO.File]::WriteAllText($sentinel,'preserve this state')
$status=Join-Path $root 'update.json'
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-Game.ps1') -Id fable1 -Source $receipt.gameRoot -StatusPath $status -PackageDirectory $PackageDirectory -LibraryRoot $library
$updated=Get-Content $status -Raw|ConvertFrom-Json
Assert ($updated.state -eq 'complete') "Anniversary runtime update failed: $($updated.detail)"
Assert ([IO.File]::ReadAllText($sentinel) -eq 'preserve this state') 'Runtime update changed saved state.'
Assert ((Get-AlbionFileHash $contentFile) -eq $beforeContent) 'Runtime update modified game content.'
Write-Output "Passed: Anniversary content import, managed launch settings, runtime update and state/content preservation. Receipt: $($result.entry)"
