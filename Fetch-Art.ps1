param([switch]$Force)
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Drawing
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assets\art-sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$destination=Join-Path $PSScriptRoot 'assets\covers'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($art in $manifest.images) {
    if ($art.id -notin @('fable1','fable2','fable3') -or $art.file -ne ($art.id+'.jpg')) { throw 'Unexpected artwork manifest entry.' }
    $uri=[uri]$art.url
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'store-images.s-microsoft.com') { throw 'Artwork must come from the Xbox image CDN.' }
    $path=Join-Path $destination $art.file
    if ((Test-Path -LiteralPath $path) -and !$Force) { continue }
    $temporary=$path+'.download'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $temporary -TimeoutSec 30
        $image=[Drawing.Image]::FromFile($temporary)
        try { if ($image.Width -lt 300 -or $image.Height -lt 400) { throw 'Artwork is smaller than expected.' } }
        finally { $image.Dispose() }
        Move-Item -LiteralPath $temporary -Destination $path -Force
        Write-Output "Cached $($art.id) artwork."
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}
