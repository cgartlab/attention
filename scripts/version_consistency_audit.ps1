#requires -Version 7.0
<#
.SYNOPSIS
  Audit version-bearing files for consistency (read-only).
.DESCRIPTION
  Detects version files across ecosystems, reads version strings, reports
  consistency and whether the change set involves a release. Prints one JSON object.
.PARAMETER repo
  Path to the repository. Defaults to the current location.
.PARAMETER defaultBranch
  Default branch name, used to compute the unpushed change set. Auto-detected if omitted.
.EXAMPLE
  pwsh -NoProfile -File scripts/version_consistency_audit.ps1 --repo D:\code\myproj
#>
param(
  [string]$repo,
  [string]$defaultBranch,
  [switch]$help
)

if ($help) {
  Write-Host "Usage: pwsh -NoProfile -File version_consistency_audit.ps1 [--repo <path>] [--defaultBranch <name>]"
  Write-Host "Read-only: detect version files (node/rust/python/jvm/dotnet/ruby), read versions,"
  Write-Host "check consistency, and whether the change set involves a release."
  exit 0
}

if ($repo) { Set-Location -LiteralPath $repo }
$ErrorActionPreference = 'SilentlyContinue'

function Test-GitOk { param([string[]]$a); & git @a 2>$null | Out-Null; $LASTEXITCODE -eq 0 }
if (-not (Test-GitOk 'rev-parse','--is-inside-work-tree')) {
  Write-Output (ConvertTo-Json -Compress -Depth 4 ([ordered]@{ is_git = $false; error = "not a git repository" }))
  exit 0
}

if (-not $defaultBranch) {
  $sym = git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
  if ($sym) { $defaultBranch = $sym -replace '^origin/', '' }
}
if (-not $defaultBranch) {
  foreach ($b in 'main','master','develop','trunk') {
    if (Test-GitOk 'show-ref','--verify','--quiet',"refs/heads/$b") { $defaultBranch = $b; break }
  }
}

function Get-Z([string[]]$a) {
  $raw = & git @a 2>$null
  if (-not $raw) { return ,@() }
  $j = $raw -join "`0"
  return ,@($j -split "`0" | Where-Object { $_ -ne '' })
}

$changed = @()
$changed += Get-Z 'diff','--cached','--name-only','--no-renames','-z'
$changed += Get-Z 'diff','--name-only','--no-renames','-z'
$changed += Get-Z 'ls-files','--others','--exclude-standard','-z'
if ($defaultBranch) {
  $od = "origin/$defaultBranch"
  if (Test-GitOk 'rev-parse','--verify',"refs/remotes/$od") {
    $raw = git diff --name-only --no-renames "$od..HEAD" 2>$null
    if ($raw) { $changed += @($raw -split "`n" | Where-Object { $_ -ne '' }) }
  }
}
$changed = @($changed | Where-Object { $_ } | Select-Object -Unique)

$excludeRe = 'node_modules|\\.git|\\target|\\dist|\\build|\\.venv|\\venv|__pycache__|\\obj|\\bin'
function Find-Files([string]$pattern) {
  $items = Get-ChildItem -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue
  return ,@($items | Where-Object { $_.FullName -notmatch $excludeRe } | ForEach-Object { $_.FullName })
}

$versionFiles = New-Object System.Collections.ArrayList
function Add-VF([string]$file, [string]$ecosystem, [string]$version) {
  if ($version) { $null = $versionFiles.Add([pscustomobject]@{ file = $file; ecosystem = $ecosystem; version = $version }) }
}

foreach ($f in (Find-Files 'package.json')) {
  try { $j = Get-Content -Raw -LiteralPath $f | ConvertFrom-Json; Add-VF $f 'node' $j.version } catch {}
}
foreach ($f in (Find-Files 'Cargo.toml')) {
  $t = Get-Content -Raw -LiteralPath $f
  $m = [regex]::Match($t, '(?m)^\s*version\s*=\s*"([^"]+)"')
  Add-VF $f 'rust' $m.Groups[1].Value
}
foreach ($f in (Find-Files 'pyproject.toml')) {
  $t = Get-Content -Raw -LiteralPath $f
  $m = [regex]::Match($t, '(?m)^\s*version\s*=\s*"([^"]+)"')
  Add-VF $f 'python' $m.Groups[1].Value
}
foreach ($f in (Find-Files 'setup.py')) {
  $t = Get-Content -Raw -LiteralPath $f
  $m = [regex]::Match($t, 'version\s*=\s*"([^"]+)"')
  Add-VF $f 'python' $m.Groups[1].Value
}
foreach ($f in (Find-Files 'pom.xml')) {
  $t = Get-Content -Raw -LiteralPath $f
  $m = [regex]::Match($t, '<version>([^<]+)</version>')
  Add-VF $f 'jvm' $m.Groups[1].Value
}
foreach ($f in (Find-Files 'gradle.properties')) {
  $t = Get-Content -Raw -LiteralPath $f
  $m = [regex]::Match($t, '(?m)^version\s*=\s*(.+)$')
  Add-VF $f 'jvm' $m.Groups[1].Value.Trim()
}
foreach ($f in (Find-Files '*.csproj')) {
  $t = Get-Content -Raw -LiteralPath $f
  $m = [regex]::Match($t, '<Version>([^<]+)</Version>')
  if (-not $m.Success) { $m = [regex]::Match($t, '<PackageVersion>([^<]+)</PackageVersion>') }
  Add-VF $f 'dotnet' $m.Groups[1].Value
}
foreach ($f in (Find-Files '*.gemspec')) {
  $t = Get-Content -Raw -LiteralPath $f
  $m = [regex]::Match($t, '\.version\s*=\s*"([^"]+)"')
  Add-VF $f 'ruby' $m.Groups[1].Value
}

$goMods = Find-Files 'go.mod'
$goPresent = @($goMods).Count -gt 0

$distinct = @($versionFiles | ForEach-Object { $_.version } | Select-Object -Unique)
$consistent = if ($distinct.Count -le 1) { $true } else { $false }

$changedRel = @($changed | ForEach-Object { ($_ -replace '\\','/') })
$vfRel = @($versionFiles | ForEach-Object { ($_ -replace '\\','/') })
$releaseInvolved = $false
foreach ($v in $vfRel) {
  foreach ($c in $changedRel) {
    if ($c -and ($v -like "*$c" -or $c -like "*$v")) { $releaseInvolved = $true; break }
  }
  if ($releaseInvolved) { break }
}
# also: release-involved if any changed file basename matches a version file basename
if (-not $releaseInvolved) {
  $vfBase = @($versionFiles | ForEach-Object { Split-Path -Leaf $_ })
  $chBase = @($changed | ForEach-Object { Split-Path -Leaf $_ })
  foreach ($vb in $vfBase) { if ($chBase -contains $vb) { $releaseInvolved = $true; break } }
}

$result = [ordered]@{
  is_git            = $true
  version_files     = @($versionFiles)
  distinct_versions = $distinct
  consistent        = $consistent
  go_mod_present    = $goPresent
  release_involved  = $releaseInvolved
  changed_files     = $changed
}
Write-Output (ConvertTo-Json -Depth 8 $result)