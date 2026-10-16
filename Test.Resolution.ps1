$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
function Assert($Value,[string]$Message){if(!$Value){throw $Message}}
$root=Join-Path $PSScriptRoot ('work\resolution-tests\'+[guid]::NewGuid().ToString('N'))
$preferences=Join-Path $root 'display-settings.json'
Assert ((Read-AlbionResolution $preferences) -eq '1080p') 'Missing preferences must default to 1080p.'
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
foreach($resolution in @('1080p','1440p','4k')){
    Save-AlbionResolution $resolution $preferences
    Assert ((Read-AlbionResolution $preferences) -eq $resolution) 'Resolution did not persist.'
    foreach($id in $entries.Keys){
        $plan=Get-AlbionLaunchPlan $id $entries[$id] -Resolution $resolution -FrameLimit 60
        Assert ($plan.Arguments.Contains('--resolution='+$resolution) -and $plan.Arguments.Contains('--fullscreen=true')) 'Resolution did not reach a managed game.'
        Assert ($plan.Arguments.Contains('--resolution_scale=1')) 'Resolution and integer draw scaling must not stack.'
        if($id -eq 'fable3'){Assert ($plan.Arguments.Contains('--fable3_frame_limit=60') -and $plan.Arguments.Contains('--async_shader_compilation=false') -and $plan.Arguments.Contains('--fable3_mesh_occlusion_workaround=true')) 'Fable III compatibility defaults were lost.'}
    }
}
[IO.File]::WriteAllText($preferences,'{"schemaVersion":1,"resolution":"9999p"}')
Assert ((Read-AlbionResolution $preferences) -eq '1080p') 'Invalid resolution must fall back safely.'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
[xml]$markup=Get-Content (Join-Path $PSScriptRoot 'Launcher.xaml') -Raw -Encoding UTF8
$view=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
Assert ($view.FindName('ResolutionChoice').Items.Count -eq 3) 'Resolution choices missing from the launcher.'
Write-Output 'Passed: 1080p default, preference persistence/fallback, all resolution launch plans for both games, compatibility preservation, WPF selector.'
