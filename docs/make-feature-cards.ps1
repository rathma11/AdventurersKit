Add-Type -AssemblyName System.Drawing
$out = "D:\progik\claude\wow\docs\screenshots"; New-Item -ItemType Directory -Force $out | Out-Null
$icon = [System.Drawing.Image]::FromFile("D:\progik\claude\wow\docs\curseforge-icon.png")
function C($a,$r,$g,$b){ [System.Drawing.Color]::FromArgb($a,$r,$g,$b) }
$W = 1280; $H = 720
$cards = @(
 @{ f="01-overview"; t="Adventurer's Kit"; s="A questing kit for WoW: Forever, built on Questie"; b=@(
   "Picks your next quest target and points the way",
   "Plans the route, the next zone and the boat ride",
   "Handles the errands: towns, dungeons, buffs, bags",
   "Tracks your pace, farming and auction house needs") },
 @{ f="02-targeting"; t="One key, the right mob"; s="The AKit macro and the quest panel"; b=@(
   "One key targets a living quest mob of your objectives, and of quests nearby",
   "With nameplates on it picks a mob nobody has tapped",
   "Escort quests: it targets whatever attacks your escort",
   "The panel shows objectives, progress, time left and your kill pace") },
 @{ f="03-route"; t="Know where to go"; s="Markers, route and travel planning"; b=@(
   "An arrow (built-in or TomTom) to the nearest spot of your objective",
   "Empty spawn points are skipped, the marker moves on",
   "Your quests in nearest-next order; step through them with the arrows",
   "Next zone and travel time with boats, zeppelins, the tram and your Hearthstone") },
 @{ f="04-towns-dungeons"; t="Towns and dungeons"; s="City list, dungeon prep and the inside view"; b=@(
   "In town: quests to pick up, plus repair, ammo, XP food and full-bag errands",
   "Directions to the bank, auction house, flight master, inn and trainers",
   "Dungeons for your level, WoW: Forever's own included, with a quest checklist",
   "Inside: every objective in boss order, and an offer to share quests") },
 @{ f="05-buffs-bags-farm"; t="Buffs, bags and farming"; s="Optional modules"; b=@(
   "Buff reminder: sleeping bag, XP food, weapon enchants, class buffs, tracking",
   "Quest items next to your bags (Bagnon), use buttons with a key binding",
   "Farm session: XP and gold per hour, time to level with rested XP, kills, loot value",
   "A summary when you stop, with AH or vendor prices") },
 @{ f="06-auction-settings"; t="Auction house and more"; s="Quest items tab, settings and commands"; b=@(
   "The items your quests still need, with the cheapest price; Buy or Buy all",
   "Per-character settings, profile export / import as text",
   "/ak for the panel, /ak options, /ak city, /ak dungeon, /ak farm",
   "Requires Questie. Optional: TomTom, Bagnon, Auctionator / TSM") }
)
$fTitle = New-Object System.Drawing.Font("Georgia", 50, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fSub = New-Object System.Drawing.Font("Georgia", 26, [System.Drawing.FontStyle]::Italic, [System.Drawing.GraphicsUnit]::Pixel)
$fBody = New-Object System.Drawing.Font("Segoe UI", 27, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fFoot = New-Object System.Drawing.Font("Segoe UI", 19, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$gold = New-Object System.Drawing.SolidBrush (C 255 240 196 92)
$cream = New-Object System.Drawing.SolidBrush (C 255 236 224 198)
$muted = New-Object System.Drawing.SolidBrush (C 255 168 146 112)
$i = 0
foreach ($c in $cards) {
  $i++
  $bmp = New-Object System.Drawing.Bitmap $W, $H
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
  $rect = New-Object System.Drawing.Rectangle 0,0,$W,$H
  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, (C 255 46 30 18), (C 255 16 10 7), 60.0
  $g.FillRectangle($bg, $rect)
  # faint big compass watermark on the right
  $cm = New-Object System.Drawing.Imaging.ColorMatrix; $cm.Matrix33 = 0.10
  $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($cm)
  $g.DrawImage($icon, (New-Object System.Drawing.Rectangle 820, 160, 620, 620), 0, 0, 512, 512, [System.Drawing.GraphicsUnit]::Pixel, $ia)
  # frame
  $g.DrawRectangle((New-Object System.Drawing.Pen (C 255 150 104 40), 4), 18, 18, $W-36, $H-36)
  $g.DrawRectangle((New-Object System.Drawing.Pen (C 120 240 196 92), 1), 28, 28, $W-56, $H-56)
  if ($i -eq 1) { $g.DrawImage($icon, 70, 70, 190, 190); $tx = 290 } else { $g.DrawImage($icon, 70, 74, 120, 120); $tx = 215 }
  $g.DrawString($c.t, $fTitle, $gold, [float]$tx, [float]84)
  $g.DrawString($c.s, $fSub, $muted, [float]($tx+4), [float]150)
  $y = 290.0
  if ($i -eq 1) { $y = 300.0 }
  foreach ($line in $c.b) {
    $cx = 100; $cy = $y + 17
    $pts = [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF $cx, ($cy-9)), (New-Object System.Drawing.PointF ($cx+9), $cy), (New-Object System.Drawing.PointF $cx, ($cy+9)), (New-Object System.Drawing.PointF ($cx-9), $cy))
    $g.FillPolygon($gold, $pts)
    $box = New-Object System.Drawing.RectangleF 130, $y, 900, 200
    $sz = $g.MeasureString($line, $fBody, 900)
    $g.DrawString($line, $fBody, $cream, $box)
    $y += $sz.Height + 22
  }
  $dot = [string][char]0xB7; $g.DrawString("Adventurer's Kit  $dot  WoW: Forever  $dot  requires Questie", $fFoot, $muted, [float]70, [float]($H-74))
  $pg = "$i / $($cards.Count)"; $ps = $g.MeasureString($pg, $fFoot)
  $g.DrawString($pg, $fFoot, $muted, [float]($W-70-$ps.Width), [float]($H-74))
  $g.Dispose(); $bmp.Save("$out\$($c.f).png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
$icon.Dispose(); "done"
