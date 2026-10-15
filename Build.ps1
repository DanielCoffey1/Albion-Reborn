param([switch]$DesktopShortcut, [switch]$SkipArtwork)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Make-Icon.ps1')
if (!$SkipArtwork) {
    try { & (Join-Path $PSScriptRoot 'Fetch-Art.ps1') }
    catch { Write-Warning "Artwork is unavailable; the launcher still works. $($_.Exception.Message)" }
}
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw 'The Windows .NET Framework C# compiler is required.' }
$automation=Get-ChildItem (Join-Path $env:SystemRoot 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation') -Recurse -Filter System.Management.Automation.dll | Select-Object -First 1
if (!$automation) { throw 'Windows PowerShell 5.1 is required.' }
$output=Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$executable=Join-Path $output 'AlbionReborn.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/win32icon:$PSScriptRoot\assets\AlbionReborn.ico" "/out:$executable" "/reference:$($automation.FullName)" /reference:System.Windows.Forms.dll (Join-Path $PSScriptRoot 'Host.cs')
if ($LASTEXITCODE -ne 0) { throw 'Launcher host build failed.' }
& $compiler /nologo /target:library /platform:x64 /optimize+ "/out:$output\Albion.Content.dll" (Join-Path $PSScriptRoot 'Content.cs')
if ($LASTEXITCODE -ne 0) { throw 'Game content helper build failed.' }
if ($DesktopShortcut) {
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Albion Reborn.lnk'))
    $shortcut.TargetPath=$executable
    $shortcut.WorkingDirectory=$PSScriptRoot
    $shortcut.Description='Choose Fable II or Fable III, and add Fable I later.'
    $shortcut.IconLocation="$(Join-Path $PSScriptRoot 'assets\AlbionReborn.ico'),0"
    $shortcut.Save()
}
Write-Output "Built $executable"
