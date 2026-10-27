# Fundo branco -> transparente, recorta, quadra e reduz para 64x64. Saida: PNG + BGRA cru.
param($Src, $OutPng, $OutRaw, [int]$Size = 64)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic;
public static class Cut {
  public static void Run(int[] px, int w, int h) {
    var seen = new bool[w*h]; var q = new Stack<int>();
    Func<int,bool> white = p => { int c = px[p]; return ((c>>16)&255) > 225 && ((c>>8)&255) > 225 && (c&255) > 225; };
    for (int x=0;x<w;x++){ q.Push(x); q.Push((h-1)*w+x); }
    for (int y=0;y<h;y++){ q.Push(y*w); q.Push(y*w+w-1); }
    while (q.Count>0) { int p=q.Pop(); if (seen[p]||!white(p)) continue; seen[p]=true; px[p]=0;
      int x=p%w, y=p/w; if(x>0)q.Push(p-1); if(x<w-1)q.Push(p+1); if(y>0)q.Push(p-w); if(y<h-1)q.Push(p+w); }
  }
}
'@
$bmp = [System.Drawing.Bitmap]::FromFile($Src)
$w = $bmp.Width; $h = $bmp.Height
$r = New-Object System.Drawing.Rectangle 0, 0, $w, $h
$d = $bmp.LockBits($r, 'ReadWrite', 'Format32bppArgb')
$px = New-Object int[] ($w * $h)
[Runtime.InteropServices.Marshal]::Copy($d.Scan0, $px, 0, $px.Length)
[Cut]::Run($px, $w, $h)
$minx = $w; $miny = $h; $maxx = 0; $maxy = 0
# o PNG original ja e transparente: bbox so com alpha > 128 (ignora ruido quase invisivel que encolhia o icone)
for ($i = 0; $i -lt $px.Length; $i++) { if ((($px[$i] -shr 24) -band 255) -gt 128) {
  $x = $i % $w; $y = [int][math]::Floor($i / $w)
  if ($x -lt $minx) { $minx = $x }; if ($x -gt $maxx) { $maxx = $x }; if ($y -lt $miny) { $miny = $y }; if ($y -gt $maxy) { $maxy = $y } } }
[Runtime.InteropServices.Marshal]::Copy($px, 0, $d.Scan0, $px.Length)
$bmp.UnlockBits($d)
$cw = $maxx - $minx + 1; $ch = $maxy - $miny + 1; $side = [math]::Max($cw, $ch)
$out = New-Object System.Drawing.Bitmap $Size, $Size, 'Format32bppArgb'
$g = [System.Drawing.Graphics]::FromImage($out)
$g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
$margin = 0; $scale = ($Size - 2 * $margin) / $side
$dw = $cw * $scale; $dh = $ch * $scale
$g.DrawImage($bmp, (New-Object System.Drawing.RectangleF (($Size - $dw) / 2), (($Size - $dh) / 2), $dw, $dh),
  (New-Object System.Drawing.RectangleF $minx, $miny, $cw, $ch), 'Pixel')
$g.Dispose()
$out.Save($OutPng, [System.Drawing.Imaging.ImageFormat]::Png)
$od = $out.LockBits((New-Object System.Drawing.Rectangle 0, 0, $Size, $Size), 'ReadOnly', 'Format32bppArgb')
$raw = New-Object byte[] ($Size * $Size * 4)
[Runtime.InteropServices.Marshal]::Copy($od.Scan0, $raw, 0, $raw.Length)  # ordem B,G,R,A
$out.UnlockBits($od)
[IO.File]::WriteAllBytes($OutRaw, $raw)
$bmp.Dispose(); $out.Dispose()
"ok crop=${cw}x${ch}"
