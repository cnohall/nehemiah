# Build a crew figure authored in Blender (build_crew.py): export the rig's bones (Godot) ->
# model, paint, bake (Blender) -> import (Godot).
#   powershell -File tools/blender/build_crew.ps1 [-Slot 0] [-Name builder_v2] [-Shots <dir>]
param([int]$Slot = 0, [string]$Name = "builder_v2", [string]$Shots = "")
$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot/../.."
$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" }
$blender = $env:BLENDER
if (-not $blender) { $blender = "C:\Users\chris\blender\blender-5.2.3-windows-x64\blender.exe" }
$json = "build/blender/slot${Slot}_rig.json"
Push-Location $root
try {
	if (-not (Test-Path $json)) {
		& $godot --headless --path . --script res://tools/blender/export_rig.gd -- "res://$json" $Slot | Out-Null
	}
	& $blender -b --factory-startup -P tools/blender/build_crew.py -- $json "assets/models/figures/$Name.glb" $Slot |
		Select-String -Pattern "atlas|figure:|wrote|Error|Traceback|File |SystemExit|part "
	& $godot --headless --path . --import | Select-String -Pattern "ERROR"
	if ($Shots) {
		& $godot --path . --always-on-top --fixed-fps 30 --script res://tools/blender/compare_shots.gd -- $Shots $Name "res://assets/models/figures/$Name.glb" $Slot |
			Select-String -Pattern "ERROR"
	}
} finally { Pop-Location }
