#requires -Version 7.0
<#
.SYNOPSIS
  Audit branches for cleanup candidates (read-only).
.DESCRIPTION
  Lists local merged branches, remote merged branches, and stale unmerged branches.
  Never deletes anything. Prints one JSON object.
.PARAMETER repo
  Path to the repository. Defaults to the current location.
.PARAMETER defaultBranch
  Default branch name. Auto-detected if omitted.
.EXAMPLE
  pwsh -File scripts/branch_cleanup_audit.ps1 --repo D:\code\myproj
#>
param(
  [string]$repo,
  [string]$defaultBranch,
  [switch]$help
)

if ($help) {
  Write-Host "Usage: pwsh -File branch_cleanup_audit.ps1 [--repo <path>] [--defaultBranch <name>]"
  Write-Host "Read-only audit: local merged branches, remote merged branches,"
  Write-Host "stale unmerged branches (>30 days, report only), protected list."
  Write-Host "Prints one JSON object. Does not delete anything."
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
if (-not $defaultBranch) { $defaultBranch = 'main' }

$current = git symbolic-ref --quiet --short HEAD 2>$null
$protected = @('main','master','develop','dev','trunk','prod','production','gh-pages','gh-readonly')
if ($current) { $protected += $current }
if ($defaultBranch) { $protected += $defaultBranch }

function Is-Protected([string]$n) {
  if ($protected -contains $n) { return $true }
  if ($n -like 'release/*') { return $true }
  return $false
}

$locals = @(git for-each-ref --format='%(refname:short)' refs/heads 2>$null)
$mergedRaw = @(git branch --merged $defaultBranch 2>$null | ForEach-Object { ($_ -replace '^[* ]+','').Trim() } | Where-Object { $_ })

$localMerged = @()
$localStale  = @()
$now = Get-Date
foreach ($b in $locals) {
  $isMerged = $mergedRaw -contains $b
  if ($isMerged) {
    if (-not (Is-Protected $b)) { $localMerged += $b }
  } else {
    $dateStr = git log -1 --format='%cI' $b 2>$null
    $ageDays = $null
    if ($dateStr) {
      try { $d = [datetimeoffset]$dateStr; $ageDays = ($now - $d.LocalDateTime).TotalDays } catch {}
    }
    if ($null -ne $ageDays -and $ageDays -gt 30 -and -not (Is-Protected $b) -and $b -ne $current) {
      $localStale += [pscustomobject]@{ branch = $b; last_commit = $dateStr; age_days = [int][Math]::Floor($ageDays) }
    }
  }
}

# remote heads
$remoteHeads = @{}
$lsOut = git ls-remote origin 2>$null
foreach ($line in $lsOut) {
  $p = $line -split '\s+'
  if ($p.Count -ge 2 -and $p[1] -like 'refs/heads/*') {
    $name = $p[1] -replace '^refs/heads/', ''
    $remoteHeads[$name] = $p[0]
  }
}

$remoteMerged = @()
$remoteRefs = @(git for-each-ref --format='%(refname:short)' refs/remotes 2>$null | Where-Object { $_ -like 'origin/*' -and $_ -ne 'origin/HEAD' })
foreach ($r in $remoteRefs) {
  $short = $r -replace '^origin/', ''
  if ($short -like 'HEAD ->*') { continue }
  if (Is-Protected $short) { continue }
  $isMerged = $false
  $mout = git branch -r --merged $defaultBranch 2>$null
  if ($mout -and ($mout | ForEach-Object { ($_ -replace '^[* ]+','').Trim() }) -contains "origin/$short") { $isMerged = $true }
  $exists = $remoteHeads.ContainsKey($short)
  if ($isMerged) {
    $remoteMerged += [pscustomobject]@{ branch = $short; tracking_ref = $r; remote_exists = $exists }
  }
}

$result = [ordered]@{
  is_git              = $true
  default_branch      = $defaultBranch
  current_branch      = $current
  protected           = $protected
  local_merged_candidates   = $localMerged
  local_stale_unmerged_report = $localStale
  remote_merged_candidates   = $remoteMerged
}
Write-Output (ConvertTo-Json -Depth 8 $result)