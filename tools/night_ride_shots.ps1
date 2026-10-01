# Frames of the night-ride POC walking the ring by itself (GDD 5.14)
param([string]$Out = "$env:TEMP\night_ride")
$godot = "C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
New-Item -ItemType Directory -Force $Out | Out-Null
& $godot --path (Split-Path $PSScriptRoot) --write-movie "$Out\f.png" --fixed-fps 10 --quit-after 420 res://scenes/night_ride/night_ride.tscn -- --demo
