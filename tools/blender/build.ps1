# Rebuild a Blender figure from the rig: export (Godot) -> build (Blender) -> import (Godot).
#   powershell -File tools/blender/build.ps1 [-Slot 0] [-Name builder] [-Shots]
param([int]$Slot = 0, [string]$Name = "builder", [switch]$Shots)
$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot/../.."
$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" }
$blender = $env:BLENDER
if (-not $blender) { $blender = "C:\Users\chris\blender\blender-5.2.3-windows-x64\blender.exe" }
$json = "build/blender/${Name}_rig.json"
Push-Location $root
try {
	& $godot --headless --path . --script res://tools/blender/export_rig.gd -- "res://$json" $Slot
	& $blender -b --factory-startup -P tools/blender/build_figure.py -- $json "assets/models/figures/$Name.glb" "build/blender/preview_$Name"
	& $godot --headless --path . --import
	if ($Shots) {
		& $godot --path . --fixed-fps 30 --script res://tools/blender/compare_shots.gd -- res://build/blender/compare $Name
	}
} finally { Pop-Location }
