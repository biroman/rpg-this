#Requires -Version 5.1
<#
.SYNOPSIS
    Builds FlatWorld for Windows and publishes it as a GitHub release.

.DESCRIPTION
    Bumps the project version, exports the Windows build, zips it, commits,
    tags, pushes, and creates the GitHub release that the in-game updater
    (scenes/boot/boot.gd) polls on launch.

.EXAMPLE
    .\tools\release.ps1
    Bumps the patch version (0.1.0 -> 0.1.1) and ships it.

.EXAMPLE
    .\tools\release.ps1 0.2.0 -Notes "New rocket physics"

.EXAMPLE
    .\tools\release.ps1 -DryRun
    Shows what would be released without touching anything.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Version,
    [string]$Notes,
    [switch]$DryRun
)

# Native tools (git, gh, godot) all write progress to stderr, which would abort
# the script under 'Stop'. Exit codes are checked explicitly instead.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Root       = Split-Path -Parent $PSScriptRoot
$Repo       = 'biroman/rpg-this'
$AssetName  = 'FlatWorld-windows.zip'
$Preset     = 'Windows Desktop'
$StageDir   = Join-Path $Root 'build\windows'
$ZipPath    = Join-Path $Root "build\$AssetName"
$ProjectCfg = Join-Path $Root 'project.godot'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Note($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

function Resolve-Godot {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return (Resolve-Path $env:GODOT).Path }

    $onPath = Get-Command 'godot' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    foreach ($dir in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop",
                       "$env:LOCALAPPDATA\Programs", $env:ProgramFiles)) {
        if (-not $dir -or -not (Test-Path $dir)) { continue }
        $hit = Get-ChildItem -Path $dir -Filter 'Godot_v4*_win64.exe' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike '*console*' } |
               Sort-Object Name -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw "Could not find the Godot editor. Point `$env:GODOT at it, e.g.`n" +
          "  `$env:GODOT = 'C:\Tools\Godot_v4.7-stable_win64.exe'"
}

function Assert-ExportTemplates {
    $dir = Join-Path $env:APPDATA 'Godot\export_templates'
    $found = $null
    if (Test-Path $dir) {
        $found = Get-ChildItem -Path $dir -Filter 'windows_release_x86_64.exe' -Recurse -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
    }
    if (-not $found) {
        throw "Windows export templates are not installed.`n" +
              "  Open the project in Godot, then: Editor -> Manage Export Templates -> Download and Install."
    }
}

# --- preflight ----------------------------------------------------------------
Step 'Checking tools'
$Godot = Resolve-Godot
Note "godot: $Godot"
Assert-ExportTemplates

# Validates the *active* account. `gh auth status` also fails on unrelated
# stale accounts in the config, which would be a false alarm here.
$ghUser = gh api user --jq .login 2>$null
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated. Run: gh auth login' }
Note "github: $ghUser"

git -C $Root rev-parse --git-dir *>$null
if ($LASTEXITCODE -ne 0) { throw "$Root is not a git repository." }

# --- version ------------------------------------------------------------------
Step 'Resolving version'
$cfg = Get-Content $ProjectCfg -Raw -ErrorAction Stop
if ($cfg -notmatch '(?m)^config/version="([^"]*)"') {
    throw 'Could not find config/version in project.godot.'
}
$current = $Matches[1]

if (-not $Version) {
    $parts = $current.Split('.')
    if ($parts.Count -ne 3) { throw "Cannot auto-bump version '$current'. Pass one explicitly." }
    $Version = '{0}.{1}.{2}' -f $parts[0], $parts[1], ([int]$parts[2] + 1)
}
$Version = $Version.TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.2.3, got '$Version'." }
$tag = "v$Version"

git -C $Root rev-parse -q --verify "refs/tags/$tag" *>$null
if ($LASTEXITCODE -eq 0) { throw "Tag $tag already exists. Pick a higher version." }
Note "$current -> $Version"

$pending = @(git -C $Root status --porcelain)
if ($pending.Count -gt 0) {
    Note 'These changes get committed as part of the release:'
    $pending | ForEach-Object { Note "  $_" }
}
if ($DryRun) { Step 'Dry run - stopping before anything is changed'; exit 0 }

# --- build --------------------------------------------------------------------
Step 'Stamping version into project.godot'
$cfg = $cfg -replace '(?m)^config/version="[^"]*"', "config/version=`"$Version`""
[System.IO.File]::WriteAllText($ProjectCfg, $cfg, (New-Object System.Text.UTF8Encoding $false))

Step 'Exporting Windows build'
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force -ErrorAction Stop }
New-Item -ItemType Directory -Path $StageDir -Force -ErrorAction Stop | Out-Null

& $Godot --headless --path $Root --import *>$null
& $Godot --headless --path $Root --export-release $Preset (Join-Path $StageDir 'FlatWorld.exe') 2>&1 |
    Where-Object { $_ -match 'ERROR|SCRIPT ERROR' } | ForEach-Object { Note "$_" }

$exe = Join-Path $StageDir 'FlatWorld.exe'
if (-not (Test-Path $exe)) {
    throw 'Export produced no FlatWorld.exe. Open the project and check Project -> Export for details.'
}
Note ('FlatWorld.exe  {0:N1} MB' -f ((Get-Item $exe).Length / 1MB))

Copy-Item (Join-Path $PSScriptRoot 'PLAY-ME-FIRST.txt') $StageDir -ErrorAction Stop

Step 'Zipping'
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force -ErrorAction Stop }
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $StageDir, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Note ("$AssetName  {0:N1} MB" -f ((Get-Item $ZipPath).Length / 1MB))

# --- publish ------------------------------------------------------------------
Step 'Committing and tagging'
git -C $Root add -A
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }

git -C $Root diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    git -C $Root commit -q -m "Release $tag"
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
}

git -C $Root tag -a $tag -m "FlatWorld $tag"
if ($LASTEXITCODE -ne 0) { throw 'git tag failed.' }

Step 'Pushing'
git -C $Root push --follow-tags origin HEAD
if ($LASTEXITCODE -ne 0) { throw 'git push failed.' }

Step 'Creating GitHub release'
$ghArgs = @('release', 'create', $tag, $ZipPath, '--repo', $Repo, '--title', "FlatWorld $tag")
if ($Notes) { $ghArgs += @('--notes', $Notes) } else { $ghArgs += '--generate-notes' }
gh @ghArgs
if ($LASTEXITCODE -ne 0) { throw 'gh release create failed.' }

Write-Host ''
Write-Host "Released $tag" -ForegroundColor Green
Write-Host 'Players get it automatically the next time they launch FlatWorld.exe.'
Write-Host "https://github.com/$Repo/releases/tag/$tag"
