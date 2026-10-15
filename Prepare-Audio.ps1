param([string]$GameRoot, [string]$DecoderPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
if (!$GameRoot) {
    $settings=Read-AlbionSettings (Join-Path $env:LOCALAPPDATA 'AlbionReborn\games.json')
    Find-AlbionInstallations $settings ([Environment]::GetFolderPath('MyDocuments'))
    if (!$settings.ContainsKey('fable2')) { throw 'Locate Fable II first, or pass -GameRoot with its installation directory.' }
    $GameRoot=Split-Path -Parent $settings.fable2
}
$output=Join-Path $env:LOCALAPPDATA 'AlbionReborn\audio'
New-Item -ItemType Directory -Path $output -Force | Out-Null
if (!$DecoderPath) {
    $tools=Join-Path $env:LOCALAPPDATA 'AlbionReborn\tools\vgmstream-r2117'
    $DecoderPath=Join-Path $tools 'vgmstream-cli.exe'
    if (!(Test-Path -LiteralPath $DecoderPath)) {
        New-Item -ItemType Directory -Path $tools -Force | Out-Null
        $zip=Join-Path $tools 'vgmstream-win64.zip'
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing 'https://github.com/vgmstream/vgmstream/releases/download/r2117/vgmstream-win64.zip' -OutFile $zip
        if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne '6C4A8A3813864FEFED081BBD337DBC0AD93BF88E0B92F5DB98D7AB258B22DC6C') { throw 'Decoder archive hash mismatch.' }
        Expand-Archive -LiteralPath $zip -DestinationPath $tools -Force
    }
}
if (!(Test-Path -LiteralPath $DecoderPath)) { throw 'vgmstream-cli.exe was not found.' }

function Read-BigEndian32($Reader) {
    $bytes=$Reader.ReadBytes(4)
    if ($bytes.Length -ne 4) { throw 'Truncated bank.' }
    [array]::Reverse($bytes)
    [BitConverter]::ToUInt32($bytes,0)
}

function Export-BankWave([string]$Bank, [string]$Entry, [string]$Destination) {
    $stream=[IO.File]::OpenRead($Bank)
    $reader=[IO.BinaryReader]::new($stream)
    try {
        $baseOffset=Read-BigEndian32 $reader
        $version=Read-BigEndian32 $reader
        if ($version -ne 3 -or $reader.ReadByte() -ne 0) { throw 'Only uncompressed-payload Fable II v3 sound banks are supported.' }
        $compressed=[IO.MemoryStream]::new()
        try {
            while ($true) {
                $size=Read-BigEndian32 $reader
                $expanded=Read-BigEndian32 $reader
                if (!$size) { break }
                if ($size -gt 16777216 -or $expanded -gt 16777216) { throw 'Invalid sound-bank header chunk.' }
                $chunk=$reader.ReadBytes($size)
                if ($chunk.Length -ne $size) { throw 'Truncated header chunk.' }
                $compressed.Write($chunk,0,$chunk.Length)
            }
            # Header chunks form one zlib stream; DeflateStream consumes its raw body.
            $compressed.Position=2
            $deflate=[IO.Compression.DeflateStream]::new($compressed,[IO.Compression.CompressionMode]::Decompress,$true)
            $table=[IO.MemoryStream]::new()
            try { $deflate.CopyTo($table) } finally { $deflate.Dispose() }
            $table.Position=0
            $index=[IO.BinaryReader]::new($table)
            try {
                $count=Read-BigEndian32 $index
                if ($count -gt 100000) { throw 'Unexpected bank entry count.' }
                for ($i=0;$i -lt $count;$i++) {
                    $nameSize=Read-BigEndian32 $index
                    if ($nameSize -gt 4096) { throw 'Invalid entry name.' }
                    $name=[Text.Encoding]::UTF8.GetString($index.ReadBytes($nameSize)).TrimEnd([char]0)
                    $relative=Read-BigEndian32 $index
                    $length=Read-BigEndian32 $index
                    if ($name -ne $Entry) { continue }
                    $offset=[long]$baseOffset+[long]$relative
                    if ($length -gt 67108864 -or $offset+$length -gt $stream.Length) { throw 'Audio entry is out of bounds.' }
                    $stream.Position=$offset
                    $data=$reader.ReadBytes($length)
                    if ([Text.Encoding]::ASCII.GetString($data,0,8) -ne "xma`0RIFF") { throw 'Expected a wrapped XMA RIFF entry.' }
                    $wave=[byte[]]::new($data.Length-4)
                    [array]::Copy($data,4,$wave,0,$wave.Length)
                    [IO.File]::WriteAllBytes($Destination,$wave)
                    return
                }
                throw "Audio entry not found: $Entry"
            } finally { $index.Dispose() }
        } finally { $compressed.Dispose() }
    } finally { $reader.Dispose(); $stream.Dispose() }
}

$clips=@(
    @{ Bank='data\audio\music.bnk'; Entry='audio\music\menu_interlude.wav'; Name='menu' },
    @{ Bank='data\language\en-uk\speech\speech.bnk'; Entry='language\speech\TEXT\QUEST\QC010\FRONT\END\10\TEXT_QUEST_QC010_FRONT_END_10.wav'; Name='theresa' }
)
foreach ($clip in $clips) {
    $source=Join-Path $GameRoot $clip.Bank
    $xma=Join-Path $output ($clip.Name+'.xma')
    $wave=Join-Path $output ($clip.Name+'.wav')
    Export-BankWave $source $clip.Entry $xma
    & $DecoderPath -i -o $wave $xma
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $wave)) { throw "Audio decode failed: $($clip.Name)" }
    Write-Output "Prepared $wave"
}
Write-Output 'Audio remains local; no game files were changed.'
