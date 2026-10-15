$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
$directory=Join-Path $env:LOCALAPPDATA 'AlbionReborn\audio'
if (!(Test-Path (Join-Path $directory 'theresa.wav')) -or !(Test-Path (Join-Path $directory 'menu.wav'))) {
    Write-Output 'Audio integration checks skipped: run Prepare-Audio.ps1 with your own Fable II installation first.'
    return
}
[xml]$markup=Get-Content (Join-Path $PSScriptRoot 'Launcher.xaml') -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
$status=$window.FindName('Status')
$launchingUntil=[datetime]::MinValue
$launchingId=''
$launchCalls=0
$mediaError=''
function Start-AlbionGame($Plan) { $script:launchCalls++; $script:launchElapsed=$clock.Elapsed.TotalSeconds }
function Update-AlbionView { Sync-AlbionMusic }
function Assert($Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Wait-AudioCondition([scriptblock]$Condition,[int]$Seconds=10) {
    $limit=[datetime]::Now.AddSeconds($Seconds)
    while (!( & $Condition) -and [datetime]::Now -lt $limit) {
        $frame=[Windows.Threading.DispatcherFrame]::new()
        $tick=[Windows.Threading.DispatcherTimer]::new()
        $tick.Interval=[timespan]::FromMilliseconds(25)
        $tick.Add_Tick({$frame.Continue=$false})
        $tick.Start()
        [Windows.Threading.Dispatcher]::PushFrame($frame)
        $tick.Stop()
    }
    Assert (& $Condition) 'Audio event timeout.'
}
. (Join-Path $PSScriptRoot 'Launcher.Audio.ps1')
try {
    $voice.Add_MediaFailed({param($sender,$eventArgs) $script:mediaError=$eventArgs.ErrorException.Message})
    Wait-AudioCondition { $voice.NaturalDuration.HasTimeSpan -or $script:mediaError }
    Assert (!$mediaError) $mediaError
    Assert ($voice.NaturalDuration.TimeSpan.TotalSeconds -gt 1 -and $voice.NaturalDuration.TimeSpan.TotalSeconds -lt 4) 'Unexpected dialogue duration.'
    $script:audioMuted=$false
    Sync-AlbionMusic
    Assert $script:musicPlaying 'Menu music should start.'
    $plan=[pscustomobject]@{Id='fable2'}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    Begin-AlbionAudioLaunch $plan
    Assert (!$script:musicPlaying) 'Music must stop before the launch voice.'
    Assert ($script:launchCalls -eq 0) 'Game started before the dialogue.'
    Wait-AudioCondition {$script:launchCalls -eq 1}
    Assert ($script:launchElapsed -gt 1 -and $script:launchElapsed -lt 4.5) 'Launch did not follow dialogue completion.'
    $voiceTimeout.Stop()
    $script:audioMuted=$true
    Begin-AlbionAudioLaunch $plan
    Assert ($script:launchCalls -eq 2 -and !$script:pendingLaunch) 'Muted launch should start immediately.'
    $script:audioMuted=$false; $script:voiceAvailable=$false
    Begin-AlbionAudioLaunch $plan
    Assert ($script:launchCalls -eq 3) 'Missing dialogue must not block launch.'
    $script:audioGameRunning=$true; $script:launchingUntil=[datetime]::MinValue
    Sync-AlbionMusic
    Assert (!$script:musicPlaying) 'Music must remain off while a game is running.'
    $script:audioGameRunning=$false
    Sync-AlbionMusic
    Assert $script:musicPlaying 'Music should resume when the game exits.'
    Write-Output 'Passed: media decoding, voice-before-launch ordering, music stop/resume, mute, and missing-dialogue fallback. No game process was started.'
} finally {
    $voiceTimeout.Stop(); $music.Close(); $voice.Close()
}
