# Makes the in-game textures of the addon icon from docs\curseforge-icon.png.
# Output (32-bit uncompressed TGA with alpha, top-left origin; the WoW client does not load PNG):
#   AdventurersKit\Media\icon.tga        64x64  the whole icon (compass on the dark rounded square)
#   AdventurersKit\Media\icon-round.tga  64x64  only the round compass disc, transparent outside
#                                                (minimap button, under the round tracking border)
#   AdventurersKit_Bags\Media\icon.tga   64x64  the whole icon + a bag badge at the bottom left
#   AdventurersKit_Buffs\Media\icon.tga  64x64  the whole icon + a buff badge (glowing up arrow)
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
$full.Dispose(); $disc.Dispose()

# ---------------------------------------------------------------------------
# Module icons: the base icon with a round badge (~39% of the size) at the bottom left, drawn at 512 px
# ---------------------------------------------------------------------------
$BADGE_CX = 120; $BADGE_CY = 392; $BADGE_R = 100

function P([double]$x, [double]$y) { New-Object System.Drawing.PointF ([single]$x), ([single]$y) }
function Rgb([int]$r, [int]$g, [int]$b, [int]$a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }
function New-Pen($color, [double]$w) {
    $p = New-Object System.Drawing.Pen $color, ([single]$w)
    $p.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    return $p
}
function New-VGradient([double]$y0, [double]$y1, $c0, $c1) {
    New-Object System.Drawing.Drawing2D.LinearGradientBrush (P 0 $y0), (P 0 $y1), $c0, $c1
}

# Dark disc with the compass' gold rim, so the badge reads on top of the compass at small sizes
function Draw-BadgeBacking($g, $cx, $cy, $r) {
    $g.FillEllipse((New-Object System.Drawing.SolidBrush (Rgb 18 11 6)), $cx - $r - 6, $cy - $r - 6, 2 * $r + 12, 2 * $r + 12)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush (P 0 ($cy - $r)), (P 0 ($cy + $r)), (Rgb 70 46 26), (Rgb 34 21 12)
    $g.FillEllipse($bg, $cx - $r, $cy - $r, 2 * $r, 2 * $r)
    $g.DrawEllipse((New-Pen (Rgb 222 176 80) 11), $cx - $r + 6, $cy - $r + 6, 2 * $r - 12, 2 * $r - 12)
}

# Leather sack with a gold tie at the neck
function Draw-Bag($g, $cx, $cy) {
    $outline = New-Pen (Rgb 48 26 10) 8
    $body = New-Object System.Drawing.Drawing2D.GraphicsPath
    $body.AddBezier((P ($cx - 20) ($cy - 30)), (P ($cx - 78) ($cy - 6)), (P ($cx - 74) ($cy + 62)), (P $cx ($cy + 62)))
    $body.AddBezier((P $cx ($cy + 62)), (P ($cx + 74) ($cy + 62)), (P ($cx + 78) ($cy - 6)), (P ($cx + 20) ($cy - 30)))
    $body.CloseFigure()
    $g.FillPath((New-VGradient ($cy - 30) ($cy + 62) (Rgb 196 128 60) (Rgb 112 62 26)), $body)
    $g.DrawPath($outline, $body)
    # shine on the left side
    $g.FillEllipse((New-Object System.Drawing.SolidBrush (Rgb 255 220 160 90)), $cx - 50, $cy - 6, 18, 40)
    # ruffled top above the tie
    $top = New-Object System.Drawing.Drawing2D.GraphicsPath
    $top.AddPolygon([System.Drawing.PointF[]]@(
        (P ($cx - 20) ($cy - 34)), (P ($cx - 44) ($cy - 70)), (P ($cx - 14) ($cy - 58)), (P $cx ($cy - 76)),
        (P ($cx + 14) ($cy - 58)), (P ($cx + 44) ($cy - 70)), (P ($cx + 20) ($cy - 34))))
    $g.FillPath((New-VGradient ($cy - 76) ($cy - 34) (Rgb 214 150 76) (Rgb 150 90 40)), $top)
    $g.DrawPath($outline, $top)
    # gold tie
    $tie = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tie.AddRectangle((New-Object System.Drawing.RectangleF ([single]($cx - 30)), ([single]($cy - 44)), 60, 16))
    $g.FillPath((New-VGradient ($cy - 44) ($cy - 28) (Rgb 252 218 118) (Rgb 196 146 52)), $tie)
    $g.DrawPath((New-Pen (Rgb 48 26 10) 6), $tie)
    # tie ends hanging down on the right
    $g.DrawLine((New-Pen (Rgb 48 26 10) 12), ($cx + 22), ($cy - 30), ($cx + 36), ($cy - 2))
    $g.DrawLine((New-Pen (Rgb 236 192 92) 6), ($cx + 22), ($cy - 30), ($cx + 36), ($cy - 2))
}

# Four-point sparkle
function Draw-Sparkle($g, $x, $y, $s, $color) {
    $k = $s * 0.28
    $pts = [System.Drawing.PointF[]]@((P $x ($y - $s)), (P ($x + $k) ($y - $k)), (P ($x + $s) $y), (P ($x + $k) ($y + $k)),
        (P $x ($y + $s)), (P ($x - $k) ($y + $k)), (P ($x - $s) $y), (P ($x - $k) ($y - $k)))
    $g.FillPolygon((New-Object System.Drawing.SolidBrush $color), $pts)
}

# Glowing green up arrow with sparkles (a buff)
function Draw-Buff($g, $cx, $cy, $r) {
    $glow = New-Object System.Drawing.Drawing2D.GraphicsPath
    $glow.AddEllipse($cx - $r + 10, $cy - $r + 10, 2 * $r - 20, 2 * $r - 20)
    $gb = New-Object System.Drawing.Drawing2D.PathGradientBrush $glow
    $gb.CenterColor = Rgb 200 255 150 170
    $gb.SurroundColors = [System.Drawing.Color[]]@((Rgb 60 120 30 0))
    $g.FillPath($gb, $glow)
    $arrow = New-Object System.Drawing.Drawing2D.GraphicsPath
    $arrow.AddPolygon([System.Drawing.PointF[]]@(
        (P $cx ($cy - 72)), (P ($cx + 54) ($cy - 10)), (P ($cx + 22) ($cy - 10)), (P ($cx + 22) ($cy + 62)),
        (P ($cx - 22) ($cy + 62)), (P ($cx - 22) ($cy - 10)), (P ($cx - 54) ($cy - 10))))
    $g.FillPath((New-VGradient ($cy - 72) ($cy + 62) (Rgb 214 255 140) (Rgb 34 140 36)), $arrow)
    $g.DrawPath((New-Pen (Rgb 12 46 12) 8), $arrow)
    Draw-Sparkle $g ($cx + 52) ($cy - 46) 22 (Rgb 255 246 190)
    Draw-Sparkle $g ($cx - 52) ($cy + 22) 15 (Rgb 255 246 190)
    Draw-Sparkle $g ($cx + 50) ($cy + 40) 11 (Rgb 255 246 190)
}

function Save-ModuleIcon([string]$kind, [string]$folder) {
    $big = New-Object System.Drawing.Bitmap $bmp.Width, $bmp.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($big)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.DrawImage($bmp, 0, 0, $bmp.Width, $bmp.Height)
    Draw-BadgeBacking $g $BADGE_CX $BADGE_CY $BADGE_R
    if ($kind -eq 'bag') {
        # a bit bigger than drawn, so it fills the badge and still reads at 64 px
        $g.TranslateTransform($BADGE_CX, $BADGE_CY + 4); $g.ScaleTransform(1.15, 1.15)
        Draw-Bag $g 0 0
        $g.ResetTransform()
    } else { Draw-Buff $g $BADGE_CX $BADGE_CY $BADGE_R }
    $g.Dispose()
    $dir = Join-Path $root "$folder\Media"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $small = Resize-Image $big (New-Object System.Drawing.Rectangle 0, 0, $big.Width, $big.Height) 64
    Save-Tga $small (Join-Path $dir 'icon.tga')
    if ($env:ICON_PREVIEW_DIR) {
        $big.Save((Join-Path $env:ICON_PREVIEW_DIR "icon-$kind-512.png"))
        $small.Save((Join-Path $env:ICON_PREVIEW_DIR "icon-$kind.png"))
    }
    $big.Dispose(); $small.Dispose()
}
Save-ModuleIcon 'bag' 'AdventurersKit_Bags'
Save-ModuleIcon 'buff' 'AdventurersKit_Buffs'
$bmp.Dispose()
