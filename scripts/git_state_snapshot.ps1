#requires -Version 7.0
<#
.SYNOPSIS
  Snapshot the git working-tree state of a repository as JSON (read-only).
.DESCRIPTION
  Runs git plumbing commands only. Prints one JSON object. Never mutates the repo.
.PARAMETER repo
  Path to the repository. Defaults to the current location.
.PARAMETER defaultBranch
  Default branch name, used to compute divergence. Auto-detected if omitted.
.EXAMPLE
  pwsh -NoProfile -File scripts/git_state_snapshot.ps1 --repo D:\code\myproj
#>
param(
  [string]$repo,
  [string]$defaultBranch,
  [switch]$help
)

if ($help) {
  Write-Host "Usage: pwsh -NoProfile -File git_state_snapshot.ps1 [--repo <path>] [--defaultBranch <name>]"
  Write-Host "Read-only snapshot: branch, upstream, ahead/behind, staged/unstaged/untracked,"
  Write-Host "stash count, recent changed files, unpushed commits vs default branch."
  Write-Host "Prints one JSON object. Does not mutate the repository."
  exit 0
}

if ($repo) { Set-Location -LiteralPath $repo }
$ErrorActionPreference = 'SilentlyContinue'

function Test-GitOk { param([string[]]$a); & git @a 2>$null | Out-Null; $LASTEXITCODE -eq 0 }

$isGit = Test-GitOk 'rev-parse','--is-inside-work-tree'
if (-not $isGit) {
  Write-Output (ConvertTo-Json -Compress -Depth 4 ([ordered]@{ is_git = $false; error = "not a git repository" }))
  exit 0
}

$rootPath   = (git rev-parse --show-toplevel 2>$null)
$branch     = git symbolic-ref --quiet --short HEAD 2>$null
$detached   = [string]::IsNullOrEmpty($branch)
$headShort  = git rev-parse --short HEAD 2>$null
$upstream   = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
if ($upstream -eq 'HEAD') { $upstream = $null }

$ahead  = $null; $behind = $null
if ($upstream) {
  $counts = git rev-list --left-right --count '@{u}...HEAD' 2>$null
  if ($counts) {
    $p = $counts -split '\s+' | Where-Object { $_ -ne '' }
    if ($p.Count -ge 2) { $behind = [int]$p[0]; $ahead = [int]$p[1] }
  }
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

function Get-ZList([string[]]$a) {
  $raw = & git @a 2>$null
  if (-not $raw) { return ,@() }
  $joined = $raw -join "`0"
  return ,@($joined -split "`0" | Where-Object { $_ -ne '' })
}

$staged    = Get-ZList 'diff','--cached','--name-only','--no-renames','-z'
$unstaged  = Get-ZList 'diff','--name-only','--no-renames','-z'
$untracked = Get-ZList 'ls-files','--others','--exclude-standard','-z'

$stashCount = 0
$stashList  = git stash list 2>$null
if ($stashList) { $stashCount = @($stashList).Count }

$recent = @()
$commitCount = 0
$cc = git rev-list --count HEAD 2>$null
if ($cc) { [int]::TryParse($cc, [ref]$commitCount) | Out-Null }
$n = [Math]::Min(10, $commitCount)
if ($n -gt 0) {
  $raw = git diff --name-only --no-renames "HEAD~$n..HEAD" 2>$null
  if ($raw) { $recent = @($raw -split "`n" | Where-Object { $_ -ne '' }) }
}

$unpushed = @()
if ($defaultBranch) {
  $originDefault = "origin/$defaultBranch"
  $haveRemote = Test-GitOk 'rev-parse','--verify',"refs/remotes/$originDefault"
  $range = if ($haveRemote) { "$originDefault..HEAD" } elseif ($upstream) { "@{u}..HEAD" } else { $null }
  if ($range) {
    $raw = git log --oneline $range 2>$null
    if ($raw) { $unpushed = @($raw -split "`n" | Where-Object { $_ -ne '' }) }
  }
}

$result = [ordered]@{
  is_git              = $true
  repo_root           = $rootPath
  current_branch      = $branch
  detached            = $detached
  head_short          = $headShort
  upstream            = $upstream
  ahead               = $ahead
  behind              = $behind
  default_branch      = $defaultBranch
  staged              = $staged
  unstaged            = $unstaged
  untracked           = $untracked
  stash_count         = $stashCount
  recent_changed_files= $recent
  unpushed_commits    = $unpushed
}
Write-Output (ConvertTo-Json -Depth 8 $result)