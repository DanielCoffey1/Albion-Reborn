$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
$root=Join-Path $PSScriptRoot ('work\tests\' + [guid]::NewGuid().ToString('N'))
$installation=Join-Path $root ('install with spaces ' + [char]0x00e9)
$scriptDirectory=Join-Path $installation 'tools'
$binaryDirectory=Join-Path $installation 'out\build\win-amd64-release'
New-Item -ItemType Directory -Path $scriptDirectory,$binaryDirectory -Force | Out-Null
$scriptEntry=Join-Path $scriptDirectory 'run.ps1'
$executable=Join-Path $binaryDirectory 'fable_3.exe'
[IO.File]::WriteAllText($scriptEntry,'# Fixture only; never executed.')
[IO.File]::WriteAllText($executable,'Fixture only; never executed.')
$preferences=Join-Path $root 'games.json'
$settings=@{fable3=$scriptEntry;fable1=(Join-Path $installation 'future.exe')}
Save-AlbionSettings $settings $preferences
$loaded=Read-AlbionSettings $preferences
Assert ($loaded.fable3 -ceq $scriptEntry) 'Unicode/spaced path did not round-trip.'
$loaded.fable1=Join-Path $installation 'another.exe'
Save-AlbionSettings $loaded $preferences
Assert ((Read-AlbionSettings $preferences).fable1 -eq $loaded.fable1) 'Atomic preferences replacement failed.'
$plan=Get-AlbionLaunchPlan fable3 $scriptEntry
Assert ($plan.WorkingDirectory -eq $installation) 'Fable III working directory is incorrect.'
Assert ($plan.Arguments.Contains('"'+$scriptEntry+'"')) 'Script path is not quoted.'
Assert ($plan.ProcessPath -eq $executable) 'Fable III child process path is incorrect.'
Assert (@(Get-AlbionGameProcess $plan).Count -eq 0) 'An unrelated process was mistaken for this game.'
$manual=@{fable2='X:\disconnected\fable_2.exe'}
Find-AlbionInstallations $manual ([Environment]::GetFolderPath('MyDocuments'))
Assert ($manual.fable2 -eq 'X:\disconnected\fable_2.exe') 'Discovery overwrote a user-selected location.'
$rejected=$false
try { $null=Get-AlbionLaunchPlan fable3 (Join-Path $root 'missing.ps1') } catch { $rejected=$true }
Assert $rejected 'Missing installation should be rejected.'
$rejected=$false
try { $null=Get-AlbionLaunchPlan fable3 $executable } catch { $rejected=$true }
Assert $rejected 'Direct Fable III exe would lose the project launcher settings.'
$future=Join-Path $installation 'future.exe'
[IO.File]::WriteAllText($future,'Fixture only; never executed.')
$first=Get-AlbionLaunchPlan fable1 $future
Assert ($first.FileName -eq $future -and $first.Arguments -eq '') 'Fable I cannot be configured independently.'
Write-Output 'Passed: settings save/update, Unicode/spaces, launch quoting, process matching, discovery precedence, missing game, Fable III script requirement, future Fable I.'
Write-Output 'Fixtures remain under ignored work/tests; no game was launched or modified.'
