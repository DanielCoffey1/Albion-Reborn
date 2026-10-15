param([Parameter(Mandatory)][string]$Fable2Runtime,[Parameter(Mandatory)][string]$Fable3Runtime,
      [Parameter(Mandatory)][string]$CrtDirectory,[string]$Destination='')
$ErrorActionPreference='Stop'
if(!$Destination){$Destination=Join-Path $PSScriptRoot 'out\packages'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$specs=Get-Content (Join-Path $PSScriptRoot 'packaging\runtime-specs.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$catalog=@()
foreach ($spec in $specs.runtimes) {
    $source=if($spec.id -eq 'fable2'){$Fable2Runtime}else{$Fable3Runtime}
    $stage=Join-Path $PSScriptRoot ('work\runtime-packages\'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $names=@($spec.runtimeFiles)+@($spec.seedFiles)
    foreach($name in $names) {
        if([IO.Path]::GetFileName($name) -ne $name){throw 'Runtime spec paths must be flat.'}
        Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $stage $name)
    }
    foreach($crt in Get-ChildItem -LiteralPath $CrtDirectory -Filter '*.dll') {
        Copy-Item -LiteralPath $crt.FullName -Destination (Join-Path $stage $crt.Name)
        $names+=,$crt.Name
    }
    $notices=Join-Path $stage 'licenses'
    New-Item -ItemType Directory -Path $notices -Force | Out-Null
    $sources=@(
        @{path=(Join-Path $PSScriptRoot '..\Fable 2\Fable-II-PC\LICENSE');name='Fable-II-upstream-LICENSE'},
        @{path=(Join-Path $PSScriptRoot '..\Fable 3\Fable-III-PC\third_party\licenses\ReXGlue-LICENSE');name='ReXGlue-LICENSE'},
        @{path=(Join-Path $PSScriptRoot '..\Fable 3\Fable-III-PC\third_party\licenses\Xenia-Canary-LICENSE');name='Xenia-Canary-LICENSE'}
    )
    foreach($notice in $sources) {
        if(!(Test-Path -LiteralPath $notice.path)){throw "Missing license notice: $($notice.name)"}
        Copy-Item -LiteralPath $notice.path -Destination (Join-Path $notices $notice.name)
        $names+=,('licenses/'+$notice.name)
    }
    $files=@(foreach($name in $names | Select-Object -Unique) {
        @{path=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $stage $name) -Algorithm SHA256).Hash;seed=($name -in $spec.seedFiles)}
    })
    $manifest=@{schemaVersion=1;id=$spec.id;version=$spec.version;files=$files}
    $manifest | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $stage 'package.json') -Encoding UTF8
    $filename=$spec.id+'-'+$spec.version+'.zip'
    $zip=Join-Path $Destination $filename
    if(Test-Path -LiteralPath $zip){throw "Package already exists: $zip. Choose a fresh output directory or increment the runtime version."}
    [IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
    $record=$spec | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $record | Add-Member package $filename
    $record | Add-Member sha256 (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $catalog+=,$record
    Write-Output "Built $zip"
}
@{schemaVersion=1;runtimes=$catalog} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Destination 'catalog.json') -Encoding UTF8
Write-Output 'Only explicitly listed runtime/configuration files and notices were packaged. Source content, dumps, saves, caches, logs, and PDBs were not included.'
