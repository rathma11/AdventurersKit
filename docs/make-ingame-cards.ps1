Add-Type -AssemblyName System.Drawing
$SRC = "F:\Games\World of Warcraft\_forever_\Screenshots"
$out = "D:\progik\claude\wow\docs\screenshots"; New-Item -ItemType Directory -Force $out | Out-Null
$icon = [System.Drawing.Image]::FromFile("D:\progik\claude\wow\docs\curseforge-icon.png")
function C($a,$r,$g,$b){ [System.Drawing.Color]::FromArgb($a,$r,$g,$b) }
$W = 1920; $H = 1080
# bg = x,y,w (fractions; height follows 16:9); insets: src x1,y1,x2,y2 fractions, dest x,y, scale
$cards = @(
 @{ f="02-quest-panel"; img="WoWScrnShot_111726_130422.jpg"; bg=@(0.30,0.20,0.70)
    t="One key, the right mob"; b=@(
      "Focus a quest: the panel shows progress, time left and your kill pace.",
      "The AKit macro targets its mobs, and the mobs of quests nearby.",
      "A marker points to the nearest spot.")
    ins=@(,@(0.636,0.700,0.775,0.980, 760,250,1.75)) },
 @{ f="03-city-what-next"; img="WoWScrnShot_111826_025103.jpg"; bg=@(0.20,0.05,0.80)
    t="In town: what to do next"; b=@(
      "The city list shows the quests to pick up here, with XP, and errands like low ammo.",
      "What next? plans your route and the next zone, with travel time and the best way.",
      "The buff reminder lists what is missing.")
    ins=@(@(0.538,0.092,0.775,0.222, 690,360,1.18), @(0.636,0.515,0.778,0.850, 1440,200,1.25)) },
 @{ f="04-farm-session"; img="WoWScrnShot_111826_175117.jpg"; bg=@(0.25,0.05,0.75)
    t="Farm session"; b=@(
      "XP per hour, time to level, kills and looted gold, live while you farm.",
      "Items count at vendor or AH price (Auctionator / TSM).",
      "A summary with a gold breakdown when you stop.")
    ins=@(,@(0.378,0.163,0.731,0.510, 690,300,1.33)) },
 @{ f="05-auction-house"; img="WoWScrnShot_111826_122654.jpg"; bg=@(0.30,0.00,0.70)
    t="Quest items at the AH"; b=@(
      "A Quest items tab lists what your quests still need, with the cheapest price.",
      "Buy one or Buy all with one confirmation.",
      "Click a row to search it; prices come from Auctionator or your own scan.")
    ins=@(,@(0.396,0.080,0.568,0.425, 760,210,1.55)) },
 @{ f="06-dungeons"; img="WoWScrnShot_111826_105017.jpg"; bg=@(0.44,0.05,0.56)
    t="Dungeons for your level"; b=@(
      "Dungeons with their quests and level range, WoW: Forever's own included.",
      "Prep: the quests to pick up first, then an arrow to the entrance.",
      "Inside: every objective in boss order.")
    ins=@(@(0.465,0.142,0.678,0.487, 700,250,1.45), @(0.668,0.565,0.810,0.985, 1500,230,1.0)) }
)
$fT = New-Object System.Drawing.Font("Georgia", 56, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fB = New-Object System.Drawing.Font("Segoe UI", 29, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fF = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$gold = New-Object System.Drawing.SolidBrush (C 255 240 196 92); $cream = New-Object System.Drawing.SolidBrush (C 255 240 230 208); $muted = New-Object System.Drawing.SolidBrush (C 255 190 168 130)
$dot = [string][char]0xB7
foreach ($c in $cards) {
  $img = [System.Drawing.Image]::FromFile("$SRC\$($c.img)")
  $IW = $img.Width; $IH = $img.Height
  $bmp = New-Object System.Drawing.Bitmap $W, $H; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode='AntiAlias'; $g.TextRenderingHint='AntiAliasGridFit'; $g.InterpolationMode='HighQualityBicubic'
  $bw = $c.bg[2]*$IW; $bh = $bw*9/16
  $g.DrawImage($img, (New-Object System.Drawing.RectangleF 0,0,$W,$H), (New-Object System.Drawing.RectangleF ($c.bg[0]*$IW), ($c.bg[1]*$IH), $bw, $bh), [System.Drawing.GraphicsUnit]::Pixel)
  $g.FillRectangle((New-Object System.Drawing.SolidBrush (C 120 10 6 4)), 0, 0, $W, $H)
  $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0,0), (New-Object System.Drawing.Point 1000,0), (C 245 14 9 6), (C 0 14 9 6)
  $cb = New-Object System.Drawing.Drawing2D.ColorBlend 3; $cb.Colors = @((C 245 14 9 6), (C 230 14 9 6), (C 0 14 9 6)); $cb.Positions = @(0.0, 0.62, 1.0); $lg.InterpolationColors = $cb
  $g.FillRectangle($lg, 0, 0, 999, $H)
  foreach ($i in $c.ins) {
    $sw = ($i[2]-$i[0])*$IW; $sh = ($i[3]-$i[1])*$IH; $dw = $sw*$i[6]; $dh = $sh*$i[6]
    $dx = [math]::Min([double]$i[4], [double]($W-30-$dw)); $dy = [math]::Min([double]$i[5], [double]($H-80-$dh))
    $g.FillRectangle((New-Object System.Drawing.SolidBrush (C 140 0 0 0)), $dx+10, $dy+12, $dw, $dh)
    $g.DrawImage($img, (New-Object System.Drawing.RectangleF $dx, $dy, $dw, $dh), (New-Object System.Drawing.RectangleF ($i[0]*$IW), ($i[1]*$IH), $sw, $sh), [System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawRectangle((New-Object System.Drawing.Pen (C 255 214 160 60), 3), $dx-2, $dy-2, $dw+3, $dh+3)
  }
  $g.DrawImage($icon, 60, 56, 92, 92)
  $tb = New-Object System.Drawing.RectangleF 170, 58, 560, 140
  $g.DrawString($c.t, $fT, $gold, $tb)
  $ts = $g.MeasureString($c.t, $fT, 560)
  $y = [math]::Max(58 + $ts.Height + 30, 190)
  foreach ($l in $c.b) {
    $g.FillPolygon($gold, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 70, ($y+12)), (New-Object System.Drawing.PointF 80, ($y+22)), (New-Object System.Drawing.PointF 70, ($y+32)), (New-Object System.Drawing.PointF 60, ($y+22))))
    $sz = $g.MeasureString($l, $fB, 560); $g.DrawString($l, $fB, $cream, (New-Object System.Drawing.RectangleF 100, $y, 560, 300)); $y += $sz.Height + 20 }
  $g.FillRectangle((New-Object System.Drawing.SolidBrush (C 200 10 6 4)), 0, $H-56, $W, 56)
  $g.DrawString("Adventurer's Kit  $dot  WoW: Forever  $dot  in-game screenshot", $fF, $muted, [float]60, [float]($H-44))
  $g.Dispose(); $bmp.Save("$out\$($c.f).png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $img.Dispose()
}
$icon.Dispose(); "done"
