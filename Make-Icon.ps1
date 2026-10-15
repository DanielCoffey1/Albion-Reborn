$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
[xml]$source=Get-Content (Join-Path $PSScriptRoot 'assets\AlbionMark.xaml') -Raw
$drawing=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($source))
$sizes=@(16,24,32,48,64,128,256)
$frames=@()
foreach ($size in $sizes) {
    $visual=[Windows.Media.DrawingVisual]::new()
    $context=$visual.RenderOpen()
    $context.PushTransform([Windows.Media.ScaleTransform]::new($size/256.0,$size/256.0))
    $context.DrawDrawing($drawing)
    $context.Pop()
    $context.Close()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($size,$size,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $buffer=[IO.MemoryStream]::new()
    $encoder.Save($buffer)
    $bytes=$buffer.ToArray()
    $buffer.Dispose()
    $frames+=,@{Size=$size;Data=$bytes}
    if ($size -eq 256) { [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'assets\AlbionReborn.png'),$bytes) }
}
$icon=[IO.MemoryStream]::new()
$writer=[IO.BinaryWriter]::new($icon)
try {
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$frames.Count)
    $offset=6+16*$frames.Count
    foreach ($frame in $frames) {
        $dimension=if ($frame.Size -eq 256) {0} else {$frame.Size}
        $writer.Write([byte]$dimension);$writer.Write([byte]$dimension)
        $writer.Write([byte]0);$writer.Write([byte]0)
        $writer.Write([uint16]1);$writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Data.Length);$writer.Write([uint32]$offset)
        $offset+=$frame.Data.Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Data) }
    $writer.Flush()
    [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'assets\AlbionReborn.ico'),$icon.ToArray())
} finally { $writer.Dispose();$icon.Dispose() }
Write-Output 'Generated original Albion Reborn icon: 16, 24, 32, 48, 64, 128, 256 px.'
