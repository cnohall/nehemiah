# Re-renders the load cover's circuit maps (tools/load_maps.gd), then reimports them.
#   powershell -File tools/load_maps.ps1 [section ...]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Only)
$godot = 'C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$root = Join-Path $PSScriptRoot '..'
& $godot --path $root --script res://tools/load_maps.gd -- @Only 2>&1 | Select-String 'saved|ERROR'
& $godot --path $root --headless --import 2>&1 | Out-Null
