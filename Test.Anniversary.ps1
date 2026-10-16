$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
function Assert($value,$message){if(!$value){throw $message}}
$root=Join-Path $PSScriptRoot ('work\tests\anniversary-'+[guid]::NewGuid().ToString('N'))
$previousLocalAppData=$env:LOCALAPPDATA
$env:LOCALAPPDATA=Join-Path $root 'user-state'
try {
$project=Join-Path $root 'Fable Anniversary test\Fable-Anniversary-PC'
$script=Join-Path $project 'tools\run.ps1'
$exe=Join-Path $project 'out\build\win-amd64-release\fable_anniversary.exe'
[IO.Directory]::CreateDirectory((Split-Path $script))|Out-Null
[IO.Directory]::CreateDirectory((Split-Path $exe))|Out-Null
[IO.File]::WriteAllText($script,'# Fixture; not executed')
[IO.File]::WriteAllText($exe,'Fixture; not executed')
$settings=@{}
Find-AlbionInstallations $settings $root
Assert ($settings.fable1 -eq $script) 'Anniversary was not discovered.'
$plan=Get-AlbionLaunchPlan fable1 $script -Resolution 4k -FrameLimit 120
Assert ($plan.ProcessPath -eq $exe) 'Wrong game process.'
Assert ($plan.Arguments.Contains('"'+$script+'"')) 'Spaced script path must be quoted.'
Assert ($plan.Arguments.Contains('-Resolution 4k -FrameLimit 30 -ReadbackResolve full')) 'Tested Anniversary fixes were lost.'
Assert ($plan.WorkingDirectory -eq $project) 'Wrong working directory.'
$settings.fable1='X:\chosen\run.ps1'
Find-AlbionInstallations $settings $root
Assert ($settings.fable1 -eq 'X:\chosen\run.ps1') 'Discovery overwrote the chosen game.'
$rejected=$false
try{$null=Get-AlbionLaunchPlan fable1 $exe}catch{$rejected=$true}
Assert $rejected 'Direct Anniversary binary bypasses required fixes.'
Write-Output 'Passed: Anniversary discovery, path quoting, resolution, validated cap, rendering settings, process identity and discovery precedence.'
} finally { $env:LOCALAPPDATA=$previousLocalAppData }
