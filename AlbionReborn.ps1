param(
    [switch]$Check,
    [ValidateSet('fable1','fable2','fable3')][string]$Launch,
    [switch]$DryRun,
    [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'AlbionReborn\games.json')
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
$startupWarning=''
try { $settings=Read-AlbionSettings $SettingsPath }
catch { $settings=@{}; $startupWarning='Saved locations could not be read. Locate your games again; the original settings file has been left alone.' }
Find-AlbionInstallations $settings ([Environment]::GetFolderPath('MyDocuments'))

if ($Check) {
    Get-AlbionCatalog | ForEach-Object {
        $game=$_
        $entry=$settings[$_.Id]; $ready=$false; $problem='Not installed'
        if ($entry) {
            try { $null=Get-AlbionLaunchPlan $_.Id $entry; $ready=$true; $problem='' }
            catch { $problem=$_.Exception.Message }
        }
        [pscustomobject]@{ Game=$game.Name; Ready=$ready; Entry=$entry; Problem=$problem }
    }
    return
}
if ($Launch) {
    if (!$settings.ContainsKey($Launch)) { throw 'No installation selected for this game.' }
    $plan=Get-AlbionLaunchPlan $Launch $settings[$Launch]
    if ($DryRun) { $plan | ConvertTo-Json; return }
    $null=Start-AlbionGame $plan
    return
}
if ($DryRun) { throw 'Use -DryRun with -Launch.' }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Launch with Windows PowerShell -STA.' }
[xml]$xaml=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Launcher.xaml') -Raw -Encoding UTF8
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$window.FindName('Close').Add_Click({ $window.Close() })
$window.FindName('Minimize').Add_Click({ $window.WindowState='Minimized' })
$window.FindName('Maximize').Add_Click({
    $window.WindowState=if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
})
$window.FindName('TitleBar').Add_MouseLeftButtonDown({
    param($sender,$eventArgs)
    if ($eventArgs.ClickCount -eq 2) {
        $window.WindowState=if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
    } else { $window.DragMove() }
})
foreach ($game in Get-AlbionCatalog) {
    $cover=Join-Path $PSScriptRoot ('assets\covers\'+$game.Id+'.jpg')
    if (Test-Path -LiteralPath $cover) {
        try {
            $bitmap=[Windows.Media.Imaging.BitmapImage]::new()
            $bitmap.BeginInit()
            $bitmap.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.UriSource=[uri]$cover
            $bitmap.EndInit()
            $bitmap.Freeze()
            $window.FindName($game.Id+'Art').Fill.ImageSource=$bitmap
        } catch { } # Artwork is optional; game launch remains available offline.
    }
}
$cards=@{}
$status=$window.FindName('Status')
$launchingUntil=[datetime]::MinValue
$launchingId=''
$lastRunningName=''

function Update-AlbionView {
    $runningName=''
    $readyCount=0
    foreach ($game in Get-AlbionCatalog) {
        $card=$cards[$game.Id]
        $plan=$null; $message='Add an installation'; $ready=$false
        if ($settings.ContainsKey($game.Id)) {
            try {
                $plan=Get-AlbionLaunchPlan $game.Id $settings[$game.Id]
                $ready=$true; $message='Ready to play'
                $readyCount++
                if (@(Get-AlbionGameProcess $plan).Count) { $message='Running'; $runningName=$game.Name }
            } catch { $message='Location needs attention' }
        }
        $card.Badge.Text=$message
        $card.Play.IsEnabled=$ready -and $message -ne 'Running' -and [datetime]::Now -ge $script:launchingUntil
        $card.Play.Content=if ($message -eq 'Running') { 'Running' } elseif (!$ready) { 'Not installed' } else { 'Play' }
        $card.Play.ToolTip=if ($plan) { $plan.Entry } else { 'Use Locate to add this game.' }
        $card.Locate.Content=if ($settings.ContainsKey($game.Id)) { 'Change location' } else { 'Locate game' }
    }
    if ($runningName) { $status.Text="$runningName is running. Your saves and settings stay with the game." }
    elseif ($script:lastRunningName) { $status.Text='Choose your next story.' }
    $script:lastRunningName=$runningName
    $window.FindName('CollectionCount').Text="$readyCount of 3 ready"
}

foreach ($game in Get-AlbionCatalog) {
    $id=$game.Id
    $cards[$id]=@{ Play=$window.FindName($id+'Play'); Locate=$window.FindName($id+'Locate'); Badge=$window.FindName($id+'Badge') }
    $cards[$id].Play.Tag=$id
    $cards[$id].Locate.Tag=$id
    $cards[$id].Play.Add_Click({
        param($sender,$eventArgs)
        try {
            $selected=[string]$sender.Tag
            $plan=Get-AlbionLaunchPlan $selected $settings[$selected]
            foreach ($other in Get-AlbionCatalog) {
                if ($settings.ContainsKey($other.Id)) {
                    try { $otherPlan=Get-AlbionLaunchPlan $other.Id $settings[$other.Id] } catch { continue }
                    if (@(Get-AlbionGameProcess $otherPlan).Count) { throw "Close $($other.Name) before launching another game." }
                }
            }
            $script:launchingUntil=[datetime]::Now.AddSeconds(15)
            $script:launchingId=$selected
            $null=Start-AlbionGame $plan
            $status.Text='Launching ' + (@(Get-AlbionCatalog | Where-Object Id -eq $selected)[0].Name) + '...'
            Update-AlbionView
        } catch {
            $script:launchingUntil=[datetime]::MinValue
            $status.Text=$_.Exception.Message
            [Windows.MessageBox]::Show($window,$_.Exception.Message,'Albion Reborn','OK','Warning') | Out-Null
        }
    })
    $cards[$id].Locate.Add_Click({
        param($sender,$eventArgs)
        $selected=[string]$sender.Tag
        $picker=[Microsoft.Win32.OpenFileDialog]::new()
        $picker.Title=if ($selected -eq 'fable3') { 'Locate Fable III-PC\tools\run.ps1' } else { 'Locate the game executable' }
        $picker.Filter=if ($selected -eq 'fable3') { 'Fable III launch script (run.ps1)|run.ps1' } else { 'Game executable (*.exe)|*.exe' }
        if ($picker.ShowDialog($window)) {
            try {
                $null=Get-AlbionLaunchPlan $selected $picker.FileName
                $updated=$settings.Clone(); $updated[$selected]=$picker.FileName
                Save-AlbionSettings $updated $SettingsPath
                $settings[$selected]=$picker.FileName
                $status.Text='Game location saved.'
                Update-AlbionView
            } catch { [Windows.MessageBox]::Show($window,$_.Exception.Message,'Albion Reborn','OK','Warning') | Out-Null }
        }
    })
}
$timer=[Windows.Threading.DispatcherTimer]::new()
$timer.Interval=[timespan]::FromSeconds(2)
$timer.Add_Tick({
    if ($script:launchingId -and [datetime]::Now -ge $script:launchingUntil) {
        $script:launchingId=''
        $status.Text='Choose your next story.'
    }
    Update-AlbionView
})
$window.Add_Closed({ $timer.Stop() })
Update-AlbionView
if ($startupWarning) { $status.Text=$startupWarning }
$timer.Start()
$null=$window.ShowDialog()
