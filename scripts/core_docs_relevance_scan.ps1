#requires -Version 7.0
<#
.SYNOPSIS
  Scan core docs for references to changed source files (read-only).
.DESCRIPTION
  Identifies core documentation files and flags those that cross-reference
  files in the current change set. Prints one JSON object. Never edits docs.
.PARAMETER repo
  Path to the repository. Defaults to the current location.
.PARAMETER defaultBranch
  Default branch name, used to compute the unpushed change set. Auto-detected if omitted.
.EXAMPLE
  pwsh -NoProfile -File scripts/core_docs_relevance_scan.ps1 --repo D:\code\myproj
#>
param(
  [string]$repo,
  [string]$defaultBranch,
  [switch]$help
)

if ($help) {
  Write-Host "Usage: pwsh -NoProfile -File core_docs_relevance_scan.ps1 [--repo <path>] [--defaultBranch <name>]"
  Write-Host "Read-only: list core docs, the change set, and docs that reference changed files."
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

$coreDocs = New-Object System.Collections.ArrayList
$tops = Get-ChildItem -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(README|CHANGELOG|CHANGES|HISTORY|CONTRIBUTING|LICENSE|AGENTS|CLAUDE)' }
foreach ($f in $tops) { $null = $coreDocs.Add($f.FullName) }
if (Test-Path 'docs') {
  $sub = Get-ChildItem -Path 'docs' -Recurse -File -Filter *.md -ErrorAction SilentlyContinue | Select-Object -First 50
  foreach ($f in $sub) { $null = $coreDocs.Add($f.FullName) }
}

$changedBasenames = @($changed | ForEach-Object { Split-Path -Leaf $_ } | Where-Object { $_ } | Select-Object -Unique)
$needUpdate = New-Object System.Collections.ArrayList
foreach ($doc in $coreDocs) {
  if (-not (Test-Path -LiteralPath $doc)) { continue }
  $content = Get-Content -Raw -LiteralPath $doc -ErrorAction SilentlyContinue
  if (-not $content) { continue }
  $refs = New-Object System.Collections.ArrayList
  foreach ($bn in $changedBasenames) {
    if ($bn -and $content -match [regex]::Escape($bn)) { $null = $refs.Add($bn) }
  }
  if ($refs.Count -gt 0) {
    $null = $needUpdate.Add([pscustomobject]@{ doc = $doc; references = @($refs) })
  }
}

$result = [ordered]@{
  is_git              = $true
  core_docs           = @($coreDocs | ForEach-Object { [pscustomobject]@{ file = $_; exists = (Test-Path -LiteralPath $_) } })
  changed_files       = $changed
  changed_basenames   = $changedBasenames
  docs_needing_update = @($needUpdate)
}
Write-Output (ConvertTo-Json -Depth 8 $result)