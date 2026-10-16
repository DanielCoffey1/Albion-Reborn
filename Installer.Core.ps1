function Get-AlbionRuntimeCatalog {
    param([string]$PackageDirectory=(Join-Path $PSScriptRoot 'packages'))
    $path=Join-Path $PackageDirectory 'catalog.json'
    if(!(Test-Path -LiteralPath $path)){throw 'This copy does not include runtime packages. Use the complete Albion Reborn installer bundle.'}
    $catalog=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if($catalog.schemaVersion -ne 1){throw 'Unsupported runtime catalog.'}
    return $catalog
}

function Expand-AlbionRuntime {
    param([string]$Archive,[string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root=[IO.Path]::GetFullPath($Destination).TrimEnd('\')+'\'
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $seen=@{};$total=[long]0
        foreach($entry in $zip.Entries) {
            $target=[IO.Path]::GetFullPath((Join-Path $root $entry.FullName))
            if(!$target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or $entry.FullName.Contains(':') -or $seen.ContainsKey($target)){throw 'Unsafe or duplicate runtime package path.'}
            $seen[$target]=$true;$total+=$entry.Length
            if($total -gt 2147483648 -or $seen.Count -gt 10000){throw 'Runtime package exceeds expected limits.'}
            if(!$entry.Name){[IO.Directory]::CreateDirectory($target) | Out-Null;continue}
            [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
        }
    } finally {$zip.Dispose()}
}

function Write-AlbionJson {
    param($Value,[string]$Path)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temporary,$Path,($Path+'.previous'))}
    else{[IO.File]::Move($temporary,$Path)}
}

function Test-AlbionGameContent {
    param([string]$Source,$Runtime)
    if([IO.Path]::GetExtension($Source) -eq '.iso') {
        Add-Type -Path (Join-Path $PSScriptRoot 'out\Albion.Content.dll')
        $info=[Albion.Content]::InspectIso($Source)
        $hash=$info.XexSha256
        foreach($required in $Runtime.requiredContent) {
            if($required -eq 'data'){continue}
            if(!@($info.Entries | Where-Object Path -eq $required).Count){throw "Incomplete game image: $required is missing."}
        }
        if($Runtime.id -eq 'fable2' -and @($info.Entries | Where-Object Path -eq 'data/tu1_data.bnk').Count -and @($info.Entries | Where-Object {$_.Path.StartsWith('data/language/de-de/',[StringComparison]::OrdinalIgnoreCase)}).Count){throw 'Mixed retail/TU1 files are not supported.'}
    } else {
        if(Test-Path -LiteralPath $Source -PathType Leaf){$Source=Split-Path -Parent $Source}
        if(!(Test-Path -LiteralPath (Join-Path $Source 'default.xex'))){throw 'Select the extracted folder containing default.xex and the game content.'}
        foreach($required in $Runtime.requiredContent){if(!(Test-Path -LiteralPath (Join-Path $Source $required))){throw "Incomplete game folder: $required is missing."}}
        if($Runtime.id -eq 'fable2' -and (Test-Path (Join-Path $Source 'data/tu1_data.bnk')) -and (Test-Path (Join-Path $Source 'data/language/de-de'))){throw 'Mixed retail/TU1 files are not supported.'}
        $hash=Get-AlbionFileHash (Join-Path $Source 'default.xex')
    }
    if($hash -ne $Runtime.xexSha256){throw "Unsupported game version. This package requires $($Runtime.edition). SHA-256: $hash"}
    return $hash
}
function Get-AlbionFileHash([string]$Path) {
    $stream=[IO.File]::OpenRead($Path);$hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','')}
    finally{$hash.Dispose();$stream.Dispose()}
}

