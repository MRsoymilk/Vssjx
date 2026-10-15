param([string]$GodotBin = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotBin) {
    $godotCommand = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($godotCommand) { $GodotBin = $godotCommand.Source }
}
if (-not $GodotBin) {
    throw '请通过 -GodotBin 或 GODOT_BIN 指定 Godot 4.7 可执行文件。'
}
& $GodotBin --path (Join-Path $projectRoot 'client') 'res://scenes/admin/data_browser.tscn'
exit $LASTEXITCODE
