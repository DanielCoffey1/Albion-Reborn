# Keep network and installation work outside the WPF dispatcher.
$updateButton=$window.FindName('UpdateButton')
$updateState=@{busy=$false;applying=$false;worker=$null;manifest=$null;status='';version=''}
$buildPath=Join-Path $PSScriptRoot 'build-info.json'
if(Test-Path $buildPath){$updateState.version=(Get-Content $buildPath -Raw -Encoding UTF8 | ConvertFrom-Json).version}
function Start-AlbionUpdateWorker([string]$Mode){
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Update-Launcher.ps1')+'" -Mode '+$Mode+' -StatusPath "'+$updateState.status+'" -LauncherProcessId '+$PID
    if($updateState.version){$info.Arguments+=' -CurrentVersion "'+$updateState.version+'"'}
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.EnvironmentVariables['PSModulePath']=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules')+';'+(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
    $updateState.worker=[Diagnostics.Process]::Start($info);$updateState.busy=$true
    $updateButton.IsEnabled=$false
}
function Start-AlbionUpdateCheck {
    if($updateState.busy){return}
    $updateState.status=Join-Path $env:LOCALAPPDATA ('AlbionReborn\updates\check-'+[guid]::NewGuid().ToString('N')+'.json')
    $updateState.manifest=$null;$updateState.applying=$false
    $updateButton.Content='Checking updates...'
    Start-AlbionUpdateWorker 'Check'
}
$updateButton.Add_Click({
    if(!$updateState.manifest){Start-AlbionUpdateCheck;return}
    if($script:audioGameRunning -or $script:pendingLaunch){$status.Text='Close the running game before updating.';return}
    $updateState.applying=$true;$updateButton.Content='Downloading update...'
    Update-AlbionView
    Start-AlbionUpdateWorker 'Apply'
})
$updatePoll=[Windows.Threading.DispatcherTimer]::new();$updatePoll.Interval=[timespan]::FromMilliseconds(500)
$updatePoll.Add_Tick({
    if(!$updateState.busy){return}
    $result=$null
    if(Test-Path $updateState.status){try{$result=Get-Content $updateState.status -Raw -Encoding UTF8 | ConvertFrom-Json}catch{return}}
    if($result -and $result.state -eq 'ready'){$window.Close();return}
    if($result -and $result.state -in @('available','current','error')){
        if($updateState.applying -and $result.state -eq 'available'){return}
        $updateState.busy=$false;$updateState.applying=$false;$updateButton.IsEnabled=$true
        if($result.state -eq 'available'){$updateState.manifest=$result.manifest;$updateButton.Content='Update available - download & restart';$updateButton.ToolTip='Launcher '+$result.manifest.version+' and bundled game fixes. Saves and game files stay in place.'}
        elseif($result.state -eq 'current'){$updateButton.Content='Up to date';$updateButton.ToolTip='Click to check again.'}
        else{$updateState.manifest=$null;$updateButton.Content='Retry update check';$updateButton.ToolTip=$result.detail}
    } elseif($updateState.worker.HasExited){$updateState.busy=$false;$updateState.applying=$false;$updateButton.IsEnabled=$true;$updateButton.Content='Retry update check'}
})
$updatePoll.Start()
$window.Add_Loaded({Start-AlbionUpdateCheck})
$window.Add_Closed({$updatePoll.Stop()})
