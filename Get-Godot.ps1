[CmdletBinding()]
param(
    [switch]$Build,
    [ValidateSet('editor', 'template_debug', 'template_release')]
    [string]$Target = 'editor',
    [ValidateRange(1, 64)]
    [int]$Jobs = 16,
    [string]$WorkDirectory = (Join-Path $PSScriptRoot '.work')
)

$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'upstream.json') -Raw | ConvertFrom-Json
$work = [IO.Path]::GetFullPath($WorkDirectory)
$source = Join-Path $work 'godot'
New-Item -ItemType Directory -Path $work -Force | Out-Null

function Check-Exit([string]$Operation) {
    if ($LASTEXITCODE -ne 0) { throw "$Operation failed with exit code $LASTEXITCODE." }
}

if (-not (Test-Path -LiteralPath $source)) {
    & git clone --depth 1 --branch $manifest.tag $manifest.repository $source
    Check-Exit 'Fetch upstream source'
}
$head = & git -C $source rev-parse HEAD
Check-Exit 'Read source revision'
if ($head -ne $manifest.commit) {
    throw "Expected upstream $($manifest.commit), found $head. The existing checkout was not reset."
}
foreach ($name in $manifest.patches) {
    $patch = Join-Path $PSScriptRoot "patches/$name"
    & git -C $source apply --reverse --check $patch 2>$null
    if ($LASTEXITCODE -ne 0) {
        & git -C $source apply --check $patch
        Check-Exit "Check $name"
        & git -C $source apply $patch
        Check-Exit "Apply $name"
    }
}
Write-Output "Pinned source with patches: $source"
if (-not $Build) { return }

$python = Join-Path $work 'python/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    & python -m venv (Join-Path $work 'python')
    Check-Exit 'Create local Python environment'
}
& $python -m pip install "scons==$($manifest.scons)"
Check-Exit 'Install SCons'

$dependencies = Join-Path $work 'dependencies'
New-Item -ItemType Directory -Path $dependencies -Force | Out-Null
$accesskit = Join-Path $dependencies "accesskit-c-$($manifest.accesskit)"
if (-not (Test-Path -LiteralPath (Join-Path $accesskit 'include'))) {
    $archive = Join-Path $dependencies "accesskit-c-$($manifest.accesskit).zip"
    Invoke-WebRequest "https://github.com/godotengine/godot-accesskit-c-static/releases/download/$($manifest.accesskit)/accesskit-c-$($manifest.accesskit).zip" -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $dependencies -Force
}

$previousBuildName = $env:BUILD_NAME
try {
    $env:BUILD_NAME = 'tlgl46'
    & $python -m SCons -C $source platform=windows "target=$Target" module_mono_enabled=yes `
        d3d12=no angle=no dev_build=no debug_symbols=no optimize=speed "accesskit_sdk_path=$accesskit" "-j$Jobs"
    Check-Exit 'Build native engine'
}
finally { $env:BUILD_NAME = $previousBuildName }

if ($Target -eq 'editor') {
    # All existing native signatures are unchanged. New calls are exposed via Call/ClassDB.
    $bundle = Join-Path $dependencies 'Godot_v4.7.2-stable_mono_win64'
    if (-not (Test-Path -LiteralPath (Join-Path $bundle 'GodotSharp'))) {
        $archive = Join-Path $dependencies 'Godot_v4.7.2-stable_mono_win64.zip'
        Invoke-WebRequest $manifest.managed_bundle -OutFile $archive
        Expand-Archive -LiteralPath $archive -DestinationPath $dependencies -Force
    }
    Copy-Item -LiteralPath (Join-Path $bundle 'GodotSharp') -Destination (Join-Path $source 'bin') -Recurse -Force
}
Write-Output "Built: $(Join-Path $source "bin/godot.windows.$Target.x86_64.mono.exe")"
