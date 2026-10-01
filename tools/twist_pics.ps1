# Re-shoots the in-game pictures for TwistCard (tools/twist_pics.gd), one run per twist.
#   powershell -File tools/twist_pics.ps1 [twist ...]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Only)
$godot = 'C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$days = [ordered]@{ doors = 1; beams = 5; salvage = 9; thick = 13; mixing = 18; horn = 24; haul = 30; spring = 34; night = 37; cramped = 42; schemes = 48 }
foreach ($t in $days.Keys) {
	if ($Only -and $Only -notcontains $t) { continue }
	& $godot --path (Join-Path $PSScriptRoot '..') --script res://tools/twist_pics.gd -- --nostory --day=$($days[$t]) $t 2>&1 | Select-String 'saved|ERROR'
}
& $godot --path (Join-Path $PSScriptRoot '..') --headless --import 2>&1 | Out-Null
