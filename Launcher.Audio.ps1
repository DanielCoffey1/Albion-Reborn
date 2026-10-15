# Optional local game recordings; absence or media failure must never block Play.
$audioDirectory=Join-Path $env:LOCALAPPDATA 'AlbionReborn\audio'
$audioPreferences=Join-Path $env:LOCALAPPDATA 'AlbionReborn\audio-settings.json'
$audioMuted=$false
try {
    if (Test-Path -LiteralPath $audioPreferences) {
        $audioMuted=[bool](Get-Content $audioPreferences -Raw -Encoding UTF8 | ConvertFrom-Json).muted
    }
} catch { $audioMuted=$false }
$music=[Windows.Media.MediaPlayer]::new()
$voice=[Windows.Media.MediaPlayer]::new()
$music.Volume=0.22
$voice.Volume=0.9
$musicAvailable=Test-Path -LiteralPath (Join-Path $audioDirectory 'menu.wav')
$voiceAvailable=Test-Path -LiteralPath (Join-Path $audioDirectory 'theresa.wav')
$musicPlaying=$false
$audioGameRunning=$false
$pendingLaunch=$null
$voiceTimeout=[Windows.Threading.DispatcherTimer]::new()
$voiceTimeout.Interval=[timespan]::FromSeconds(5)

function Sync-AlbionMusic {
    $shouldPlay=$script:musicAvailable -and !$script:audioMuted -and !$script:audioGameRunning -and
        !$script:pendingLaunch -and [datetime]::Now -ge $script:launchingUntil -and $window.WindowState -ne 'Minimized'
    if ($shouldPlay -and !$script:musicPlaying) { $music.Play(); $script:musicPlaying=$true }
    elseif (!$shouldPlay -and $script:musicPlaying) { $music.Pause(); $script:musicPlaying=$false }
    $window.FindName('AudioToggle').Content=if ($script:audioMuted) { 'Audio: Off' } else { 'Audio: On' }
    $window.FindName('AudioToggle').ToolTip=if (!$script:musicAvailable) { 'Run Prepare-Audio.ps1 to add your local game audio.' } else { 'Toggle menu music and the launch voice line.' }
}

function Complete-AlbionLaunch {
    if (!$script:pendingLaunch) { return }
    $plan=$script:pendingLaunch
    $script:pendingLaunch=$null
    $voiceTimeout.Stop()
    $voice.Stop()
    try {
        $script:launchingUntil=[datetime]::Now.AddSeconds(15)
        $null=Start-AlbionGame $plan
        $status.Text='Launching ' + (@(Get-AlbionCatalog | Where-Object Id -eq $plan.Id)[0].Name) + '...'
    } catch {
        $script:launchingUntil=[datetime]::MinValue
        $script:launchingId=''
        $status.Text=$_.Exception.Message
        [Windows.MessageBox]::Show($window,$_.Exception.Message,'Albion Reborn','OK','Warning') | Out-Null
    }
    Update-AlbionView
}

function Begin-AlbionAudioLaunch($Plan) {
    if ($script:pendingLaunch) { return }
    $script:pendingLaunch=$Plan
    $script:launchingUntil=[datetime]::Now.AddSeconds(15)
    $script:launchingId=$Plan.Id
    $music.Stop()
    $script:musicPlaying=$false
    if ($script:voiceAvailable -and !$script:audioMuted) {
        $status.Text='And so our story begins...'
        $voice.Position=[timespan]::Zero
        $voiceTimeout.Start()
        $voice.Play()
        Update-AlbionView
    } else { Complete-AlbionLaunch }
}

$music.Add_MediaEnded({ $music.Position=[timespan]::Zero; $script:musicPlaying=$false; Sync-AlbionMusic })
$music.Add_MediaFailed({ $script:musicAvailable=$false; $script:musicPlaying=$false })
$voice.Add_MediaEnded({ Complete-AlbionLaunch })
$voice.Add_MediaFailed({ $script:voiceAvailable=$false; Complete-AlbionLaunch })
$voiceTimeout.Add_Tick({ Complete-AlbionLaunch })
if ($musicAvailable) { $music.Open([uri](Join-Path $audioDirectory 'menu.wav')) }
if ($voiceAvailable) { $voice.Open([uri](Join-Path $audioDirectory 'theresa.wav')) }
$window.FindName('AudioToggle').Add_Click({
    $script:audioMuted=!$script:audioMuted
    if ($script:audioMuted -and $script:pendingLaunch) { Complete-AlbionLaunch }
    Sync-AlbionMusic
    try {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $audioPreferences)) | Out-Null
        [IO.File]::WriteAllText($audioPreferences,(@{muted=$script:audioMuted} | ConvertTo-Json))
    } catch { } # A read-only preferences location must not break audio or Play.
})
$window.Add_StateChanged({ Sync-AlbionMusic })
$window.Add_Closed({
    $script:pendingLaunch=$null
    $voiceTimeout.Stop()
    $music.Close()
    $voice.Close()
})
