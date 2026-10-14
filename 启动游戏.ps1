param(
    [string]$GodotPath = 'E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe',
    [switch]$Editor
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) {
        throw '未找到 Godot 4.7，请使用 -GodotPath 指定引擎路径。'
    }
    $GodotPath = $godotCommand.Source
}

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.godot/imported') -PathType Container)) {
    & $GodotPath --headless --path $PSScriptRoot --editor --import --quit
}

$engineArguments = @('--path', $PSScriptRoot)
if ($Editor) { $engineArguments += '--editor' }
& $GodotPath @engineArguments
