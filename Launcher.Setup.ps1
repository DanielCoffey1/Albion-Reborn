. (Join-Path $PSScriptRoot 'Installer.Core.ps1')
function Show-AlbionGameSetup([string]$Id) {
    if($script:updateState -and $script:updateState.applying){$status.Text='Wait for the launcher update to finish.';return}
    if($script:audioGameRunning -or $script:pendingLaunch){[Windows.MessageBox]::Show($window,'Close the running game before setting up or updating games.','Albion Reborn') | Out-Null;return}
    try {$catalog=Get-AlbionRuntimeCatalog;$runtime=@($catalog.runtimes | Where-Object id -eq $Id)[0]}
    catch {[Windows.MessageBox]::Show($window,$_.Exception.Message,'Albion Reborn') | Out-Null;return}
    [xml]$markup=Get-Content (Join-Path $PSScriptRoot 'Setup.xaml') -Raw -Encoding UTF8
    $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup));$dialog.Owner=$window
    $dialog.FindName('GameTitle').Text=$runtime.name+' setup'
    $dialog.FindName('RuntimeInfo').Text="Bundled runtime $($runtime.version) | $($runtime.edition). No Git account or build tools needed."
    $state=@{source='';worker=$null;status='';busy=$false;entry='';applied=$false;exitSeen=[datetime]::MinValue}
    $managed=Join-Path $env:LOCALAPPDATA ("AlbionReborn\games\$Id\installation.json")
    if(Test-Path -LiteralPath $managed) {
        $receipt=Get-Content $managed -Raw -Encoding UTF8 | ConvertFrom-Json
        $state.entry=$managed
        $dialog.FindName('RuntimeInfo').Text+=" Installed: $($receipt.version). Updates preserve runtime settings and saves."
        $dialog.FindName('UpdateRuntime').IsEnabled=$true
    }
    $dialog.FindName('ChooseIso').Add_Click({
        $picker=[Microsoft.Win32.OpenFileDialog]::new();$picker.Filter='Xbox 360 disc image (*.iso)|*.iso';$picker.Title='Choose your game ISO'
        if($picker.ShowDialog($dialog)){$state.source=$picker.FileName;$dialog.FindName('SourcePath').Text=$state.source;$dialog.FindName('Install').IsEnabled=$true}
    })
    $dialog.FindName('ChooseFolder').Add_Click({
        $picker=[Microsoft.Win32.OpenFileDialog]::new();$picker.Filter='Game executable (default.xex)|default.xex';$picker.Title='Choose default.xex inside your extracted game folder'
        if($picker.ShowDialog($dialog)){$state.source=$picker.FileName;$dialog.FindName('SourcePath').Text=$state.source;$dialog.FindName('Install').IsEnabled=$true}
    })
    $startWorker={
        $state.applied=$false;$state.exitSeen=[datetime]::MinValue
        $state.status=Join-Path $env:LOCALAPPDATA ('AlbionReborn\operations\'+[guid]::NewGuid().ToString('N')+'.json')
        [IO.Directory]::CreateDirectory((Split-Path -Parent $state.status)) | Out-Null
        $process=[Diagnostics.ProcessStartInfo]::new()
        $process.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $process.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Install-Game.ps1')+'" -Id '+$Id+' -Source "'+$state.source+'" -StatusPath "'+$state.status+'"'
        $process.UseShellExecute=$false;$process.CreateNoWindow=$true
        $process.EnvironmentVariables['PSModulePath']=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules')+';'+(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
        $state.worker=[Diagnostics.Process]::Start($process);$state.busy=$true
        foreach($control in @('Install','UpdateRuntime','ChooseIso','ChooseFolder')){$dialog.FindName($control).IsEnabled=$false}
        $dialog.FindName('Cancel').Content='Cancel setup';$dialog.FindName('Phase').Text='Starting setup...'
    }
    $dialog.FindName('Install').Add_Click($startWorker)
    $dialog.FindName('UpdateRuntime').Add_Click({$state.source=(Get-Content $state.entry -Raw -Encoding UTF8 | ConvertFrom-Json).gameRoot;& $startWorker})
    $dialog.FindName('Cancel').Add_Click({
        if($state.busy){[IO.File]::WriteAllText(($state.status+'.cancel'),'cancel');$dialog.FindName('Cancel').IsEnabled=$false;$dialog.FindName('Phase').Text='Cancelling safely...'}else{$dialog.Close()}
    })
    $dialog.Add_Closing({param($sender,$eventArgs)if($state.busy){$eventArgs.Cancel=$true;[IO.File]::WriteAllText(($state.status+'.cancel'),'cancel');$dialog.FindName('Phase').Text='Waiting for setup to stop safely...'}})
    $poll=[Windows.Threading.DispatcherTimer]::new();$poll.Interval=[timespan]::FromMilliseconds(250)
    $poll.Add_Tick({
        if(!$state.busy){return}
        $progress=$null
        if(Test-Path -LiteralPath $state.status){try{$progress=Get-Content $state.status -Raw -Encoding UTF8 | ConvertFrom-Json}catch{return}}
        if($progress) {
            $dialog.FindName('Phase').Text=$progress.phase;$dialog.FindName('Detail').Text=$progress.detail;$dialog.FindName('Progress').Value=$progress.percent
            if($progress.state -in @('complete','error')) {
                $state.busy=$false;$dialog.FindName('Cancel').Content='Close';$dialog.FindName('Cancel').IsEnabled=$true
                foreach($control in @('ChooseIso','ChooseFolder')){$dialog.FindName($control).IsEnabled=$true}
                $dialog.FindName('Install').IsEnabled=[bool]$state.source
                if($progress.state -eq 'complete' -and !$state.applied) {
                    try {
                        $updated=$settings.Clone();$updated[$Id]=$progress.entry
                        Save-AlbionSettings $updated $SettingsPath;$settings[$Id]=$progress.entry;$state.applied=$true;$state.entry=$progress.entry
                        $dialog.FindName('UpdateRuntime').IsEnabled=$true
                        $dialog.FindName('Phase').Text='Ready to play';$dialog.FindName('Detail').Text='Close this window and press Play.'
                        Update-AlbionView
                    } catch {$dialog.FindName('Phase').Text='Installed; location could not be saved';$dialog.FindName('Detail').Text=$_.Exception.Message}
                }
            }
        }
        if($state.busy -and $state.worker.HasExited) {
            if($state.exitSeen -eq [datetime]::MinValue){$state.exitSeen=[datetime]::Now;return}
            if(([datetime]::Now-$state.exitSeen).TotalSeconds -lt 2){return}
            $state.busy=$false;$dialog.FindName('Phase').Text='Setup stopped unexpectedly.';$dialog.FindName('Cancel').Content='Close';$dialog.FindName('Cancel').IsEnabled=$true
        }
    })
    $dialog.Add_Closed({$poll.Stop()});$poll.Start();$null=$dialog.ShowDialog()
}

foreach($game in Get-AlbionCatalog) {
    $button=$window.FindName($game.Id+'Setup')
    $button.Tag=$game.Id
    $button.Add_Click({param($sender,$eventArgs)Show-AlbionGameSetup ([string]$sender.Tag)})
}
