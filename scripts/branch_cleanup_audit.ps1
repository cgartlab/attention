#requires -Version 7.0
<#
.SYNOPSIS
  Audit branches for cleanup candidates (read-only).
.DESCRIPTION
  Read-only: prints one JSON object on stdout (contract: references/scan-recipes.md §2).
  Lists local merged branches, remote merged branches and stale unmerged branches as
  report-only. Never deletes anything.
  --repo must exist and be a directory; otherwise the script prints
  {"is_git":false,"error":"repo path not found"} and exits 0.
.PARAMETER repo
  Repository path (default: current directory).
.PARAMETER defaultBranch
  Override the auto-detected default branch.
.EXAMPLE
  pwsh -NoProfile -File scripts/branch_cleanup_audit.ps1 --repo D:\code\myproj
#>
$ErrorActionPreference = 'SilentlyContinue'
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_PAGER = 'cat'

$script:GitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $script:GitExe) { $script:GitExe = 'git' }

function GitOut { param([string[]]$a); return (& $script:GitExe -c color.ui=never @a 2>$null) }
function Git1 {
  param([string[]]$a)
  $o = @(GitOut $a)
  if ($o.Count -eq 0) { return $null }
  $s = ([string]$o[0]).TrimEnd("`r")
  if ($s -eq '') { return $null }
  return $s
}
function GitOk { param([string[]]$a); & $script:GitExe -c color.ui=never @a 2>$null | Out-Null; return ($LASTEXITCODE -eq 0) }
function UniqSort {
  param($Items)
  $hs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($i in @($Items)) {
    if ($null -eq $i) { continue }
    $s = ([string]$i).TrimEnd("`r")
    if ($s -eq '') { continue }
    [void]$hs.Add($s)
  }
  $arr = [string[]]@($hs)
  if ($arr.Count -gt 1) { [Array]::Sort($arr, [System.StringComparer]::Ordinal) }
  return ,$arr
}

# ---------- 入参 ----------
$RepoArg = $null; $HaveRepoArg = $false; $DefaultArg = $null; $Help = $false
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
  $a = [string]$argv[$i]
  if ($a -eq '--repo') { if ($i + 1 -lt $argv.Count) { $RepoArg = [string]$argv[$i + 1]; $i++ } else { $HaveRepoArg = $true } }
  elseif ($a -eq '--defaultBranch') { if ($i + 1 -lt $argv.Count) { $DefaultArg = [string]$argv[$i + 1]; $i++ } }
  elseif ($a -eq '--help' -or $a -eq '-h') { $Help = $true }
}

if ($Help) {
  Write-Host "Usage: pwsh -NoProfile -File branch_cleanup_audit.ps1 [--repo <path>] [--defaultBranch <name>] [--help]"
  Write-Host ""
  Write-Host "Read-only audit of branch cleanup candidates as a single JSON object. Lists only;"
  Write-Host "it never deletes anything."
  Write-Host ""
  Write-Host "  --repo <path>            Repository path (default: current directory). Must exist and"
  Write-Host "                           be a directory, otherwise prints"
  Write-Host "                           {""is_git"":false,""error"":""repo path not found""} and exits 0."
  Write-Host "  --defaultBranch <name>   Override the auto-detected default branch."
  Write-Host "  --help, -h               Print this usage and exit 0."
  Write-Host ""
  Write-Host "Fields: is_git, default_branch, default_branch_source, current_branch, remote_reachable,"
  Write-Host "protected, local_merged_candidates, local_stale_unmerged_report, remote_merged_candidates,"
  Write-Host "warnings."
  exit 0
}

if ($HaveRepoArg -or ($RepoArg -and -not (Test-Path -LiteralPath $RepoArg -PathType Container))) {
  Write-Output '{"is_git":false,"error":"repo path not found"}'
  exit 0
}
if ($RepoArg) { Set-Location -LiteralPath $RepoArg }

if (-not (GitOk @('rev-parse','--is-inside-work-tree'))) {
  Write-Output '{"is_git":false,"error":"not a git repository"}'
  exit 0
}
# 契约要求 JSON 内路径一律相对仓库根（--repo 指向子目录时同样成立）
$top = Git1 @('rev-parse','--show-toplevel')
if ($top) { Set-Location -LiteralPath $top }

$warns = New-Object System.Collections.Generic.List[string]
function Add-Warn([string]$w) { if ($w) { $warns.Add($w) } }

# 默认分支探测
$defaultSource = 'unavailable'
$default = $null
if ($DefaultArg) {
  $default = $DefaultArg
  $defaultSource = 'explicit'
} else {
  $sym = Git1 @('symbolic-ref','--quiet','--short','refs/remotes/origin/HEAD')
  if ($sym) { $default = ($sym -replace '^origin/',''); $defaultSource = 'origin-head' }
  if (-not $default) {
    $lr = Git1 @('ls-remote','--symref','origin','HEAD')
    if ($lr -and $lr -match '^ref:\s+(\S+)') {
      $default = ($Matches[1] -replace '^refs/heads/','')
      $defaultSource = 'ls-remote'
    }
  }
  if (-not $default) {
    foreach ($b in 'main','master','develop','trunk') {
      if (GitOk @('show-ref','--verify','--quiet',"refs/heads/$b")) { $default = $b; $defaultSource = 'local-ref'; break }
    }
  }
}

$current = Git1 @('symbolic-ref','--quiet','--short','HEAD')

$protAll = New-Object System.Collections.Generic.List[string]
foreach ($p in 'main','master','develop','dev','trunk','prod','production','gh-pages','gh-readonly','release/*') { $protAll.Add($p) }
if ($current) { $protAll.Add($current) }
if ($default) { $protAll.Add($default) }
$protected = UniqSort $protAll

function Is-Protected([string]$n) {
  if ($n -like 'release/*') { return $true }
  return ($protected -ccontains $n)
}

$locals = UniqSort @(GitOut @('for-each-ref','--format=%(refname:short)','refs/heads'))

# 合并基准：优先 origin/<default>，回退本地 <default>；都取不到 -> 跳过合并判定并告警
$mergedBase = $null
if ($default) {
  if (GitOk @('rev-parse','--verify',"refs/remotes/origin/$default")) { $mergedBase = "origin/$default" }
  elseif (GitOk @('rev-parse','--verify',"refs/heads/$default")) { $mergedBase = $default }
}
if (-not $mergedBase) { Add-Warn 'default-branch-unavailable' }

$merged = @(); $rmerged = @()
if ($mergedBase) {
  $merged = @(GitOut @('branch','--merged',$mergedBase) | ForEach-Object { ($_ -replace '^[* ]+','').Trim() } | Where-Object { $_ })
  $rmerged = @(GitOut @('branch','-r','--merged',$mergedBase) | ForEach-Object { ($_ -replace '^[* ]+','').Trim() } | Where-Object { $_ })
}

$nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$localMerged = @()
$localStale = @()
foreach ($b in $locals) {
  $isMerged = ($merged -ccontains $b)
  if ($isMerged) {
    if (-not (Is-Protected $b)) { $localMerged += $b }
  } else {
    $dateStr = Git1 @('log','-1','--format=%cI',$b)
    if ($dateStr) {
      $cid = $null
      try { $cid = [DateTimeOffset]::Parse($dateStr).ToUnixTimeSeconds() } catch { $cid = $null }
      if ($null -ne $cid) {
        $ageDays = [int][Math]::Floor(($nowEpoch - $cid) / 86400)
        if ($ageDays -gt 30 -and -not (Is-Protected $b) -and $b -ne $current) {
          $localStale += [pscustomobject]@{ branch = $b; last_commit = $dateStr; age_days = $ageDays }
        }
      }
    }
  }
}

# 远端可达性：一次调用同时取输出与退出码；失败 -> remote_reachable=false + 告警
$remoteHeadsRaw = @(GitOut @('ls-remote','origin'))
$remoteReachable = ($LASTEXITCODE -eq 0)
if (-not $remoteReachable) { Add-Warn 'remote-unreachable' }
$remoteNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($line in $remoteHeadsRaw) {
  if (-not $line) { continue }
  $m = [regex]::Match([string]$line, '^(\S+)\s+refs/heads/(.+)$')
  if ($m.Success) { [void]$remoteNames.Add($m.Groups[2].Value) }
}

$rrefs = UniqSort @(GitOut @('for-each-ref','--format=%(refname:short)','refs/remotes') | Where-Object { $_ -like 'origin/*' -and $_ -ne 'origin/HEAD' })
$remoteMerged = @()
foreach ($r in $rrefs) {
  $short = $r -replace '^origin/',''
  if (Is-Protected $short) { continue }
  if ($rmerged -ccontains $r) {
    $remoteMerged += [pscustomobject]@{ branch = $short; tracking_ref = $r; remote_exists = $remoteNames.Contains($short) }
  }
}

$result = [ordered]@{
  is_git                       = $true
  default_branch               = $default
  default_branch_source        = $defaultSource
  current_branch               = $current
  remote_reachable             = $remoteReachable
  protected                    = $protected
  local_merged_candidates      = @($localMerged)
  local_stale_unmerged_report  = @($localStale)
  remote_merged_candidates     = @($remoteMerged)
  warnings                     = @($warns)
}
Write-Output (ConvertTo-Json -Depth 8 $result)
