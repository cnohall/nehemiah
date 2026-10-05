# Game trailer, v1 (~60 s, 1920x1080 MP4) - beat sheet in docs/steam/store_page.md.
#   powershell -File tools/trailer.ps1 [-Out build/trailer] [-Rerecord]
# 1. Records each gameplay beat with tools/trailer_shots.gd (bots play, clean camera) and
#    the finale map with tools/ending_shots.gd - skipped when <Out>/<beat>.avi exists.
# 2. Cuts the clips in $Cuts, captions them, adds the title card, lays the work music
#    under the game's own SFX and writes <Out>/nehemiah_trailer.mp4.
# No URLs on screen: Steam keeps offsite links out of store media.
# Needs Godot 4.7 (path in $Godot) and ffmpeg on PATH. Re-cut by editing $Cuts; the
# frame logs (<Out>/<beat>.log) say when phases change and the wall grows.
param(
    [string]$Out = "build/trailer",
    [switch]$Rerecord,
    # End-card ask: Steam store media can't carry URLs; a YouTube cut can point at the browser game
    [string]$Ask = "Wishlist on Steam",
    [string]$Godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot)
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path

# name -> trailer_shots.gd args (day picks the section and its twist)
$Beats = [ordered]@{
    valley  = "--day=25 --secs=150 --zoom=18"   # Valley Gate: raiders, horn, dusk at ~101 s
    fish    = "--day=6 --secs=100 --zoom=16"    # Fish Gate: scaffold and gate go up
    night   = "--day=38 --secs=100 --zoom=16"   # Water Gate: dark from ~25 s, torches
    ovens   = "--day=19 --secs=100 --zoom=16"   # Tower of the Ovens: raiders at the wall ~56 s
    miphkad = "--day=52 --secs=70 --zoom=19"    # the last day: raiders at the scaffolds ~17 s, a big push ~40 s (bots lose ~64 s)
}

# Godot writes to stderr; under Windows PowerShell 5.1 "Stop" would turn that into a failure
$ErrorActionPreference = "Continue"
foreach ($b in $Beats.Keys) {
    $avi = "$Out\$b.avi"
    if ((Test-Path $avi) -and -not $Rerecord) { continue }
    Write-Host "Recording $b ..."
    $a = @("--path", ".", "--write-movie", $avi, "--fixed-fps", "30", "--script", "res://tools/trailer_shots.gd", "--", "--nostory") + $Beats[$b].Split(" ")
    & $Godot @a 2>&1 | Where-Object { "$_" -match "frame |Done" } | Set-Content "$Out\$b.log"
}
if (-not (Test-Path "$Out\ending.avi") -or $Rerecord) {
    Write-Host "Recording ending ..."
    & $Godot --path . --resolution 1920x1080 --write-movie "$Out\ending.avi" --fixed-fps 30 --quit-after 330 --script res://tools/ending_shots.gd -- --scale=3 2>&1 | Out-Null
}
$ErrorActionPreference = "Stop"

# source, start s, length s, caption ("" = none)
$Cuts = @(
    @("valley",  30.0, 5.0, "Jerusalem, 455 BCE"),
    @("fish",    5.0,  4.0, "Carry stone and timber"),
    @("fish",    17.0, 4.5, "Build the wall"),
    @("miphkad", 17.0, 4.5, "Defend it"),
    @("fish",    41.0, 4.5, "Co-op for 2–4 builders"),
    @("night",   22.0, 6.0, "Work by torchlight"),
    @("miphkad", 40.0, 5.0, "Twelve stretches · fifty-two days"),
    @("valley",  104.0, 8.0, "The wall rises"),
    @("ending",  0.5, 9.5, "")
)
$Card = 6.5
$Fade = 0.25

$Cinzel   = "assets/fonts/Cinzel/static/Cinzel-Bold.ttf"
$Italic   = "assets/fonts/Spectral/Spectral-Italic.ttf"
$Medium   = "assets/fonts/Spectral/Spectral-Medium.ttf"
$Cream = "0xFAF6EE"; $Gold = "0xE0AE56"
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Run-Ffmpeg([string]$graph, [string[]]$pre, [string[]]$post) {
    $f = "$Out\graph.txt"
    [IO.File]::WriteAllText($f, $graph, $Utf8)
    & ffmpeg -loglevel error -y @pre -/filter_complex $f @post
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed" }
}

# Each cut → a normalised segment: 1080p30, captioned, dipped in and out of black
$list = @()
for ($i = 0; $i -lt $Cuts.Count; $i++) {
    $c = $Cuts[$i]; $d = $c[2]
    $v = "[0:v]trim=start=$($c[1]):duration=$d,setpts=PTS-STARTPTS,scale=1920:1080,fps=30"
    if ($c[3]) {
        $alpha = "if(lt(t,0.5),0,if(lt(t,0.9),(t-0.5)/0.4,if(lt(t,$d-0.5),1,max(0,($d-0.1-t)/0.4))))"
        $v += ",drawtext=fontfile=$($Cinzel):text='$($c[3])':fontsize=64:fontcolor=$($Cream):x=110:y=h-190:borderw=3:bordercolor=0x1B110B@0.55:shadowcolor=0x1B110B@0.6:shadowx=4:shadowy=4:alpha='$alpha'"
    }
    $v += ",fade=in:d=$($Fade),fade=out:st=$($d - $Fade):d=$($Fade),format=yuv420p[v]"
    $a = "[0:a]atrim=start=$($c[1]):duration=$d,asetpts=PTS-STARTPTS,aformat=sample_rates=48000:channel_layouts=stereo,afade=in:d=$($Fade),afade=out:st=$($d - $Fade):d=$($Fade)[a]"
    $seg = "$Out\seg$i.mp4"
    Run-Ffmpeg "$v;$a" @("-i", "$Out\$($c[0]).avi") @("-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-c:a", "aac", "-b:a", "192k", $seg)
    $list += "file '$seg'"
}

# End card: the title painting, dimmed and blurred, under the name and the ask
$v = "[0:v]boxblur=6,colorchannelmixer=rr=0.45:gg=0.42:bb=0.40,scale=1920:1080,fps=30," +
    "drawtext=fontfile=$($Cinzel):text='NEHEMIAH':fontsize=170:fontcolor=$($Cream):x=(w-tw)/2:y=330," +
    "drawtext=fontfile=$($Italic):text='Rebuild the wall of Jerusalem in 52 days':fontsize=52:fontcolor=$($Gold):x=(w-tw)/2:y=560," +
    "drawtext=fontfile=$($Medium):text='Co-op for 2–4 builders   ·   $($Ask)':fontsize=44:fontcolor=$($Cream):x=(w-tw)/2:y=700," +
    "drawtext=fontfile=$($Italic):text='Music\: Caryil, The Desert of Dreams - insydnis (CC-BY 3.0)':fontsize=24:fontcolor=$($Cream)@0.6:x=(w-tw)/2:y=1020," +
    "fade=in:d=0.6,fade=out:st=$($Card - 0.8):d=0.8,format=yuv420p[v]"
$seg = "$Out\seg_card.mp4"
Run-Ffmpeg "$v;anullsrc=r=48000:cl=stereo[a]" @("-loop", "1", "-t", "$Card", "-i", "assets/ui/menu_bg.jpg") @("-map", "[v]", "-map", "[a]", "-t", "$Card", "-c:v", "libx264", "-crf", "16", "-c:a", "aac", "-b:a", "192k", $seg)
$list += "file '$seg'"
[IO.File]::WriteAllText("$Out\list.txt", ($list -join "`n"), $Utf8)
& ffmpeg -loglevel error -y -f concat -safe 0 -i "$Out\list.txt" -c copy "$Out\cut.mp4"
if ($LASTEXITCODE -ne 0) { throw "concat failed" }

# Music under the game's SFX, out with the end card
$total = [double](& ffprobe -v error -show_entries format=duration -of csv=p=0 "$Out\cut.mp4")
$graph = "[1:a]atrim=duration=$total,volume=0.8,afade=in:d=0.8,afade=out:st=$($total - 2.5):d=2.5[m];" +
    "[0:a]volume=0.9[s];[m][s]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]"
Run-Ffmpeg $graph @("-i", "$Out\cut.mp4", "-i", "assets/audio/music/work_desert_of_dreams.ogg") @("-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "$Out\nehemiah_trailer.mp4")
Remove-Item "$Out\seg*.mp4", "$Out\cut.mp4", "$Out\list.txt", "$Out\graph.txt"
Write-Host ("Trailer: $Out\nehemiah_trailer.mp4 ({0:N1} s)" -f $total)
