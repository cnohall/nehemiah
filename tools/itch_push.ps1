# Exports both itch.io demo builds and pushes them with butler (store/itch/README.md).
#   powershell -File tools/itch_push.ps1 0.9.1 [-NoExport]
# Windows from this checkout ("Windows Demo"), browser from the web-port worktree
# ("Itch Web Demo"): merge master into web-port first so both builds match.
# --if-changed: a channel whose files are unchanged isn't pushed again.
param([Parameter(Mandatory = $true)][string]$Version, [switch]$NoExport)
$godot = 'C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$butler = 'C:\Users\chris\.local\bin\butler\butler.exe'
$target = 'takikogames/nehemiah-the-wall'
$game = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$web = (Resolve-Path (Join-Path $game '..\nehemiah-web')).Path
$builds = @(
	@{ root = $game; preset = 'Windows Demo'; dir = 'build\demo-windows'; file = 'Nehemiah-Demo.exe'; channel = 'windows-demo' },
	@{ root = $web; preset = 'Itch Web Demo'; dir = 'build\itch-web'; file = 'index.html'; channel = 'html5' }
)
foreach ($b in $builds) {
	$dir = Join-Path $b.root $b.dir
	if (-not $NoExport) {
		if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
		New-Item -ItemType Directory -Force $dir | Out-Null
		& $godot --headless --path $b.root --export-release $b.preset (Join-Path $dir $b.file) 2>&1 | Select-String '^ERROR|SCRIPT ERROR'
		if (-not (Test-Path (Join-Path $dir $b.file))) { throw "export failed: $($b.preset)" }
	}
	& $butler push $dir "$($target):$($b.channel)" --userversion $Version --if-changed
	if ($LASTEXITCODE) { throw "push failed: $($b.channel)" }
}
& $butler status $target
