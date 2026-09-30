#requires -Version 7.0
<#
.SYNOPSIS
  Gather signals for next-step development suggestions (read-only).
.DESCRIPTION
  Collects recent commits, open GitHub issues/PRs, TODO/FIXME hits, branch ages,
  detected test/lint/build commands, and divergence from default branch. Prints
  one JSON object of raw signals. The model reasons over these to suggest next steps.
.PARAMETER repo
  Path to the repository. Defaults to the current location.
.EXAMPLE
  pwsh -NoProfile -File scripts/next_steps_analysis.ps1 --repo D:\code\myproj
#>
param(
  [string]$repo,
  [switch]$help
)

if ($help) {
  Write-Host "Usage: pwsh -NoProfile -File next_steps_analysis.ps1 [--repo <path>]"
  Write-Host "Read-only signals: recent commits, open issues/PRs, TODO/FIXME hits,"
  Write-Host "branch ages, detected test/lint/build commands, divergence from default branch."
  exit 0
}

if ($repo) { Set-Location -LiteralPath $repo }
$ErrorActionPreference = 'SilentlyContinue'

function Test-GitOk { param([string[]]$a); & git @a 2>$null | Out-Null; $LASTEXITCODE -eq 0 }
if (-not (Test-GitOk 'rev-parse','--is-inside-work-tree')) {
  Write-Output (ConvertTo-Json -Compress -Depth 4 ([ordered]@{ is_git = $false; error = "not a git repository" }))
  exit 0
}

$recent = @()
$rl = git log --oneline -n 15 2>$null
if ($rl) { $recent = @($rl -split "`n" | Where-Object { $_ }) }

$remote = git remote -v 2>$null
$isGithub = $false
if ($remote -and ($remote -join "`n") -match 'github\.com') { $isGithub = $true }

$ghOk = $false
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
if ($ghCmd) {
  & gh auth status 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { $ghOk = $true }
}

$issues = @()
$prs = @()
if ($isGithub -and $ghOk) {
  $i = gh issue list --state open --limit 20 2>$null
  if ($i) { $issues = @($i -split "`n" | Where-Object { $_ }) }
  $p = gh pr list --state open --limit 20 2>$null
  if ($p) { $prs = @($p -split "`n" | Where-Object { $_ }) }
}

$todos = @()
$g = git grep -n -E 'TODO|FIXME|XXX|HACK' -- . ':(exclude)*.md' ':(exclude)*.markdown' ':(exclude)*.json' ':(exclude)*.txt' ':(exclude)*.rst' ':(exclude)scripts/next_steps_analysis.ps1' ':(exclude)scripts/next_steps_analysis.sh' 2>$null
if ($g) { $todos = @($g -split "`n" | Select-Object -First 30 | Where-Object { $_ }) }

$branches = @()
$ba = git for-each-ref --format='%(refname:short)%09%(committerdate:iso-strict)' refs/heads 2>$null
foreach ($line in $ba) {
  $p = $line -split "`t"
  if ($p.Count -ge 2 -and $p[0]) { $branches += [pscustomobject]@{ branch = $p[0]; last_commit = $p[1] } }
}

$testCmds = @()
if (Test-Path 'package.json') {
  try {
    $pj = Get-Content -Raw -LiteralPath 'package.json' | ConvertFrom-Json
    if ($pj.scripts) {
      foreach ($k in 'test','lint','build','check','typecheck','format') {
        if ($pj.scripts.$k) { $testCmds += [pscustomobject]@{ name = $k; script = $pj.scripts.$k } }
      }
    }
  } catch {}
}
if (Test-Path 'Makefile') {
  $mk = Get-Content -Raw -LiteralPath 'Makefile'
  foreach ($t in 'test','lint','build','check') {
    if ($mk -match "(?m)^$t\s*:") { $testCmds += [pscustomobject]@{ name = $t; script = "make $t" } }
  }
}
if (Test-Path 'pyproject.toml') {
  $py = Get-Content -Raw -LiteralPath 'pyproject.toml'
  foreach ($t in 'pytest','ruff','mypy') {
    if ($py -match $t) { $testCmds += [pscustomobject]@{ name = $t; script = $t } }
  }
}

$default = $null
$sym = git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
if ($sym) { $default = $sym -replace '^origin/', '' }
if (-not $default) {
  foreach ($b in 'main','master','develop','trunk') {
    if (Test-GitOk 'show-ref','--verify','--quiet',"refs/heads/$b") { $default = $b; break }
  }
}

$behind = $null
if ($default) {
  $od = "origin/$default"
  if (Test-GitOk 'rev-parse','--verify',"refs/remotes/$od") {
    $cnt = git rev-list --count "$od..HEAD" 2>$null
    if ($cnt) { $b0 = 0; if ([int]::TryParse($cnt.Trim(), [ref]$b0)) { $behind = $b0 } }
  }
}

$missing = @()
foreach ($e in 'README','CHANGELOG','LICENSE','AGENTS','CONTRIBUTING') {
  if (-not (Get-ChildItem -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$e*" })) { $missing += $e }
}
$result = [ordered]@{
  is_git          = $true
  default_branch  = $default
  behind_default  = $behind
  recent_commits  = $recent
  is_github       = $isGithub
  gh_authed       = $ghOk
  open_issues     = $issues
  open_prs        = $prs
  todo_fixme      = $todos
  branches        = $branches
  test_commands   = $testCmds
  missing_core_docs = $missing
}
Write-Output (ConvertTo-Json -Depth 8 $result)
