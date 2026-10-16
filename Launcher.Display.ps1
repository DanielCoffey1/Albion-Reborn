$resolutionChoice=$window.FindName('ResolutionChoice')
$resolutionState=@{value=(Read-AlbionResolution);changing=$false}
foreach($item in $resolutionChoice.Items){if([string]$item.Tag -eq $resolutionState.value){$resolutionChoice.SelectedItem=$item;break}}
$resolutionChoice.Add_SelectionChanged({
    if($resolutionState.changing -or !$resolutionChoice.SelectedItem){return}
    $selected=[string]$resolutionChoice.SelectedItem.Tag
    try{
        Save-AlbionResolution $selected
        $resolutionState.value=$selected
        $label=if($selected -eq '4k'){'4K'}else{$selected}
        $status.Text=$label+' saved. Applies on next launch.'
    }catch{
        $resolutionState.changing=$true
        try{foreach($item in $resolutionChoice.Items){if([string]$item.Tag -eq $resolutionState.value){$resolutionChoice.SelectedItem=$item;break}}}finally{$resolutionState.changing=$false}
        $status.Text='Resolution could not be saved: '+$_.Exception.Message
    }
})
