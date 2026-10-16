$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
function Assert($Value,[string]$Message){if(!$Value){throw $Message}}
$root=Join-Path $PSScriptRoot ('work\fps-tests\'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$preferences=Join-Path $root 'display-settings.json'
Assert ((Read-AlbionFrameLimit $preferences) -eq 60) 'Missing preferences must default to 60 FPS.'
[IO.File]::WriteAllText($preferences,'{"schemaVersion":1,"resolution":"1440p"}')
Assert ((Read-AlbionFrameLimit $preferences) -eq 60) 'Existing resolution-only preferences must default to 60 FPS.'
Save-AlbionFrameLimit 0 $preferences
Assert ((Read-AlbionFrameLimit $preferences) -eq 0 -and (Read-AlbionResolution $preferences) -eq '1440p') 'Unlimited must persist without changing resolution.'
Save-AlbionResolution '4k' $preferences
Assert ((Read-AlbionFrameLimit $preferences) -eq 0) 'Resolution changes must preserve Unlimited.'
$entries=@{}
foreach($id in @('fable2','fable3')){
    $installation=Join-Path $root $id;$runtime=Join-Path $installation 'runtime';$content=Join-Path $installation 'content'
    [IO.Directory]::CreateDirectory($runtime) | Out-Null;[IO.Directory]::CreateDirectory($content) | Out-Null
    $exe=if($id -eq 'fable2'){'fable_2.exe'}else{'fable_3.exe'}
    [IO.File]::WriteAllText((Join-Path $runtime $exe),'Fixture only; never executed.')
    [IO.File]::WriteAllText((Join-Path $content 'default.xex'),'Fixture only.')
    $entries[$id]=Join-Path $installation 'installation.json'
    @{schemaVersion=1;id=$id;gameRoot=$content} | ConvertTo-Json | Set-Content $entries[$id] -Encoding utf8
}
foreach($limit in @(0,30,60,90,120,144,165,240)){
    Save-AlbionFrameLimit $limit $preferences
    Assert ((Read-AlbionFrameLimit $preferences) -eq $limit -and (Read-AlbionResolution $preferences) -eq '4k') 'FPS persistence changed resolution.'
    foreach($id in $entries.Keys){
        $plan=Get-AlbionLaunchPlan $id $entries[$id] -Resolution '1440p' -FrameLimit $limit
        $flag=if($id -eq 'fable3'){'fable3_frame_limit'}else{'frame_limit'}
        Assert ($plan.Arguments.Contains("--${flag}=$limit") -and $plan.Arguments.Contains('--vsync=false')) 'Selected cap did not reach the managed game.'
        Assert ([regex]::Matches($plan.Arguments,'--(?:fable3_)?frame_limit=').Count -eq 1) 'Duplicate frame cap.'
        if($id -eq 'fable2'){
            Assert ($plan.Arguments.Contains('--guest_vblank_pacing=false')) 'Guest pacing must not override the selected host cap.'
            $direct=Get-AlbionLaunchPlan $id $plan.FileName -FrameLimit $limit
            Assert ($direct.Arguments.Contains("--frame_limit=$limit")) 'Direct Fable II cap missing.'
        }else{Assert ($plan.Arguments.Contains('--async_shader_compilation=false') -and $plan.Arguments.Contains('--fable3_mesh_occlusion_workaround=true')) 'Rendering fixes lost.'}
    }
}
$scriptDirectory=Join-Path $root 'legacy\tools';$binaryDirectory=Join-Path $root 'legacy\out\build\win-amd64-release'
[IO.Directory]::CreateDirectory($scriptDirectory) | Out-Null;[IO.Directory]::CreateDirectory($binaryDirectory) | Out-Null
$script=Join-Path $scriptDirectory 'run.ps1'
[IO.File]::WriteAllText($script,'# Fixture only.');[IO.File]::WriteAllText((Join-Path $binaryDirectory 'fable_3.exe'),'Fixture only.')
$legacy=Get-AlbionLaunchPlan 'fable3' $script -FrameLimit 120
Assert ($legacy.DisplayFrameLimit -eq 120) 'Development-script child preference missing.'
$future=Join-Path $root 'fable1.exe';[IO.File]::WriteAllText($future,'Fixture only.')
Assert ((Get-AlbionLaunchPlan 'fable1' $future -FrameLimit 120).Arguments -eq '') 'Future external Fable I must not receive unsupported flags.'
foreach($invalid in @('999','null','"garbage"')){
    [IO.File]::WriteAllText($preferences,('{"schemaVersion":1,"resolution":"1440p","frameLimit":'+$invalid+'}'))
    Assert ((Read-AlbionFrameLimit $preferences) -eq 60) 'Invalid FPS must fall back to 60.'
}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
[xml]$markup=Get-Content (Join-Path $PSScriptRoot 'Launcher.xaml') -Raw -Encoding UTF8
$view=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
Assert ($view.FindName('FpsChoice').Items.Count -eq 8) 'FPS selector choices missing.'
Write-Output 'Passed: 60 FPS default/migration, independent display preferences, all caps/Unlimited, managed/direct/development launch plans, rendering fixes, Fable I placeholder and WPF selector.'
