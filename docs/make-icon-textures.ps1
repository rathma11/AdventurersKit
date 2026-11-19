# Makes the in-game textures of the addon icon from docs\curseforge-icon.png.
# Output (32-bit uncompressed TGA with alpha, top-left origin; the WoW client does not load PNG):
#   AdventurersKit\Media\icon.tga        64x64  the whole icon (compass on the dark rounded square)
#   AdventurersKit\Media\icon-round.tga  64x64  only the round compass disc, transparent outside
#                                                (minimap button, under the round tracking border)
# Run: powershell -ExecutionPolicy Bypass -File docs\make-icon-textures.ps1
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'docs\curseforge-icon.png'
$outDir = Join-Path $root 'AdventurersKit\Media'
New-Item -ItemType Directory -Force $outDir | Out-Null

# The compass disc in the 512x512 source: centre (256, 256), outer outline radius ~203 px.
$DISC_CX = 256; $DISC_CY = 256; $DISC_R = 204

function Resize-Image($bmp, [System.Drawing.Rectangle]$srcRect, [int]$size) {
    $out = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $attr = New-Object System.Drawing.Imaging.ImageAttributes
    $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY) # no dark fringe at the edges
    $g.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, $size, $size),
        $srcRect.X, $srcRect.Y, $srcRect.Width, $srcRect.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    $g.Dispose()
    return $out
}

# Circular alpha mask with a 1px soft edge (radius in output pixels)
function Set-RoundMask($bmp) {
    $n = $bmp.Width; $c = ($n - 1) / 2.0; $r = $n / 2.0 - 0.5
    for ($y = 0; $y -lt $n; $y++) {
        for ($x = 0; $x -lt $n; $x++) {
            $d = [Math]::Sqrt(($x - $c) * ($x - $c) + ($y - $c) * ($y - $c))
            $k = [Math]::Max(0.0, [Math]::Min(1.0, $r - $d + 0.5))
            $p = $bmp.GetPixel($x, $y)
            $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb([int][Math]::Round($p.A * $k), $p.R, $p.G, $p.B))
        }
    }
}

function Save-Tga($bmp, [string]$path) {
    $w = $bmp.Width; $h = $bmp.Height
    $bytes = New-Object byte[] (18 + $w * $h * 4)
    $bytes[2] = 2                                  # uncompressed true-colour
    $bytes[12] = $w -band 0xFF; $bytes[13] = $w -shr 8
    $bytes[14] = $h -band 0xFF; $bytes[15] = $h -shr 8
    $bytes[16] = 32                                # bits per pixel
    $bytes[17] = 0x28                              # 8 alpha bits, top-left origin
    $i = 18
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $p = $bmp.GetPixel($x, $y)
            $bytes[$i] = $p.B; $bytes[$i + 1] = $p.G; $bytes[$i + 2] = $p.R; $bytes[$i + 3] = $p.A
            $i += 4
        }
    }
    [IO.File]::WriteAllBytes($path, $bytes)
    Write-Output "wrote $path (${w}x$h)"
}

$bmp = New-Object System.Drawing.Bitmap $src
$full = Resize-Image $bmp (New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height) 64
Save-Tga $full (Join-Path $outDir 'icon.tga')
$disc = Resize-Image $bmp (New-Object System.Drawing.Rectangle ($DISC_CX - $DISC_R), ($DISC_CY - $DISC_R), (2 * $DISC_R), (2 * $DISC_R)) 64
Set-RoundMask $disc
Save-Tga $disc (Join-Path $outDir 'icon-round.tga')
# PNG previews of the same pixels (scratch, not committed)
if ($env:ICON_PREVIEW_DIR) {
    $full.Save((Join-Path $env:ICON_PREVIEW_DIR 'icon.png'))
    $disc.Save((Join-Path $env:ICON_PREVIEW_DIR 'icon-round.png'))
}
$bmp.Dispose(); $full.Dispose(); $disc.Dispose()
