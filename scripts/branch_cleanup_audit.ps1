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
function HostOfUrl([string]$u) {
  if (-not $u) { return $null }
  if ($u -like '*://*') {
    $rest = $u.Substring($u.IndexOf('://') + 3)
    $slash = $rest.IndexOf('/')
    if ($slash -ge 0) {
      $head = $rest.Substring(0, $slash)
      $at = $head.LastIndexOf('@')
      if ($at -ge 0) { $rest = $rest.Substring($at + 1) }
    }
    $slash = $rest.IndexOf('/')
    if ($slash -ge 0) { $rest = $rest.Substring(0, $slash) }
    $colon = $rest.IndexOf(':')
    if ($colon -ge 0) { $rest = $rest.Substring(0, $colon) }
    if ($rest) { return $rest }
    return $null
  }
  if ($u -like '*@*:*') {
    $rest = $u.Substring($u.IndexOf('@') + 1)
    $colon = $rest.IndexOf(':')
    if ($colon -ge 0) { $rest = $rest.Substring(0, $colon) }
    if ($rest) { return $rest }
  }
  return $null
}
function Test-GithubHost([string]$h) {
  if (-not $h) { return $false }
  if ($h -eq 'github.com') { return $true }
  return $h.EndsWith('.github.com', [System.StringComparison]::OrdinalIgnoreCase)
}
# GitHub URL -> owner/repo（仅在宿主判定为 GitHub 后才用得上）
function Get-RemoteSlug([string]$u) {
  if (-not $u) { return $null }
  $u = $u -replace '/+$', ''
  $u = $u -replace '\.git$', ''
  if ($u -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
    $rest = $u.Substring($u.IndexOf('://') + 3)
    $at = $rest.IndexOf('@')
    if ($at -ge 0) { $rest = $rest.Substring($at + 1) }
    $slash = $rest.IndexOf('/')
    if ($slash -lt 0) { return $null }
    return $rest.Substring($slash + 1)
  }
  $m = [regex]::Match($u, '^[^/]*@[^/]*:(.+)$')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
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
  Write-Host "protected_from_rulesets, local_merge_base, remote_merge_base, remote_base_unverified,"
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

# ---------- 静态受保护名单 ----------
$protAll = New-Object System.Collections.Generic.List[string]
foreach ($p in 'main','master','develop','dev','trunk','prod','production','gh-pages','gh-readonly','release/*') { $protAll.Add($p) }
if ($current) { $protAll.Add($current) }
if ($default) { $protAll.Add($default) }

# 持久化保护名单：必须用 --get-all（--get 只回最后一个值，多值会静默丢）。
# 退出码 1 = 该键不存在 —— 正常情况，不算错误（静默忽略）；>=2 才是真读取失败，
# 记 protect-config-unreadable 后继续（绝不因此失败、也绝不因此漏掉静态名单）。
$protCfg = @(GitOut @('config','--get-all','cleanup.protect'))
$protRc = $LASTEXITCODE
if ($protRc -eq 0) { foreach ($c in $protCfg) { if ($null -ne $c) { $protAll.Add([string]$c) } } }
elseif ($protRc -gt 1) { Add-Warn 'protect-config-unreadable' }

$protected = UniqSort $protAll

$locals = UniqSort @(GitOut @('for-each-ref','--format=%(refname:short)','refs/heads'))

# 静态判定：用于 protected 字段与 local_stale_unmerged_report（后者是报告、不是删除候选，
# 且规则集只对"候选分支 ∪ 默认分支"求值，见下）。
function Is-ProtectedStatic([string]$n) {
  if ($n -like 'release/*') { return $true }
  return ($protected -ccontains $n)
}

# ---------- 合并基准 ----------
# 本地合并必须用**本地默认分支**：本地已合并但尚未推送时用 origin/<default> 会把
# 可安全删除的分支漏报（假阴性）；删本地分支不丢内容，因为提交已在本地默认分支里。
# 远程合并必须用 **origin/<default>**：用本地分支作基准会在「本地已合并、远程尚未
# 收到」时误判为已合并，删远程分支就丢数据。
$localMergeBase = $null; $remoteMergeBase = $null; $remoteBaseUnverified = $true
if ($default -and (GitOk @('rev-parse','--verify','--quiet',"refs/heads/$default"))) {
  $localMergeBase = $default
}
# 基准守卫：用 origin/<default> 前先验证该 ref 存在；不存在 → 远程候选一律为空 + 警告
if ($default -and (GitOk @('rev-parse','--verify','--quiet',"refs/remotes/origin/$default"))) {
  $remoteMergeBase = "origin/$default"
  $remoteBaseUnverified = $false
} else {
  Add-Warn 'remote-base-unverified'
}
if (-not $localMergeBase -and -not $remoteMergeBase) { Add-Warn 'default-branch-unavailable' }

$merged = @(); $rmerged = @()
if ($localMergeBase) {
  $merged = @(GitOut @('branch','--merged',$localMergeBase) | ForEach-Object { ($_ -replace '^[* ]+','').Trim() } | Where-Object { $_ })
}
if ($remoteMergeBase) {
  $rmerged = @(GitOut @('branch','-r','--merged',$remoteMergeBase) | ForEach-Object { ($_ -replace '^[* ]+','').Trim() } | Where-Object { $_ })
}

# ---------- 本地候选（按静态名单；规则集结果回来后统一过滤）----------
$nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$localMergedPre = @()
$localStale = @()
foreach ($b in $locals) {
  $isMerged = ($merged -ccontains $b)
  if ($isMerged) {
    if (-not (Is-ProtectedStatic $b)) { $localMergedPre += $b }
  } else {
    $dateStr = Git1 @('log','-1','--format=%cI',$b)
    if ($dateStr) {
      $cid = $null
      try { $cid = [DateTimeOffset]::Parse($dateStr).ToUnixTimeSeconds() } catch { $cid = $null }
      if ($null -ne $cid) {
        $ageDays = [int][Math]::Floor(($nowEpoch - $cid) / 86400)
        if ($ageDays -gt 30 -and -not (Is-ProtectedStatic $b) -and $b -ne $current) {
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

# ---------- 远程候选（按静态名单）----------
$rrefs = UniqSort @(GitOut @('for-each-ref','--format=%(refname:short)','refs/remotes') | Where-Object { $_ -like 'origin/*' -and $_ -ne 'origin/HEAD' })
$remotePre = @()
foreach ($r in $rrefs) {
  $short = $r -replace '^origin/',''
  if (Is-ProtectedStatic $short) { continue }
  # 远程基准未验证时 rmerged 恒为空 → 远程候选一律为空（宁可不删）
  if ($remoteMergeBase -and ($rmerged -ccontains $r)) {
    # tip_sha：删除时必须作为 --force-with-lease 的期望值，否则确认窗口内他人推的提交会被静默删掉
    $tip = Git1 @('rev-parse',"refs/remotes/origin/$short")
    $remotePre += [pscustomobject]@{ branch = $short; tracking_ref = $r; remote_exists = $remoteNames.Contains($short); tip_sha = $tip }
  }
}

# ---------- 仓库侧保护分支（gh rules/branches） ----------
# 只对「候选分支 ∪ 默认分支」逐个查 rules/branches/<branch>：该端点返回该分支**实际生效**
# 的 active 规则（含 org 级），已过滤 enforcement（active/evaluate/disabled）并已展开
# ref 匹配（~DEFAULT_BRANCH、refs/heads/*/**/* 等）。含 .type=="deletion" 即视为受保护。
#   · 列表端点 /rulesets 不返回 rules/conditions（实测），故不用它；
#   · 陷阱：分支不存在时该端点返回 200 + []（不是 404），所以必须先验证分支真的存在，
#     否则「分支名拼错/已被删」会被当成「没有保护」。
# 任何失败都静默降级：protected_from_rulesets=[] + rulesets-unavailable 警告，绝不整体失败，
# 也绝不把「查不到」当成「没有保护分支」——protected 的静态部分只是下界。
$rname = $null
if (GitOk @('remote','get-url','origin')) { $rname = 'origin' }
else { $rname = @(GitOut @('remote')) | Where-Object { $_ } | Select-Object -First 1 }
$rurl = $null
if ($rname) { $rurl = Git1 @('remote','get-url',$rname) }
$rhost = HostOfUrl $rurl

$rulesetsOk = $false
$protectedRulesets = @()
if ((Get-Command gh -ErrorAction SilentlyContinue) -and (Test-GithubHost $rhost)) {
  $slug = Get-RemoteSlug $rurl
  if ($slug) {
    $qset = UniqSort (@($localMergedPre) + @($remotePre | ForEach-Object { $_.branch }) + @($default) | Where-Object { $_ })
    $rulesetsOk = $true
    $qn = 0
    $hits = @()
    foreach ($b in $qset) {
      # 分支必须真的存在于远端：ls-remote 成功时以它为准（权威）；ls-remote 不可用时
      # 退回 remote-tracking ref（契约不允许用"远端已无该 ref"否掉候选，见 §2 尾注）。
      if ($remoteReachable) {
        if (-not $remoteNames.Contains($b)) { continue }
      } else {
        if (-not (GitOk @('rev-parse','--verify','--quiet',"refs/remotes/origin/$b"))) { continue }
      }
      $qn++
      # 硬上限：超过即视为"没能查完"，降级告警（宁可不给结论，也不给半截结论）
      if ($qn -gt 100) { $rulesetsOk = $false; break }
      $ans = & gh api "repos/$slug/rules/branches/$b" --jq 'any(.[]; .type=="deletion")' 2>$null
      if ($LASTEXITCODE -ne 0) { $rulesetsOk = $false; break }
      if (([string]$ans).Trim() -eq 'true') { $hits += $b }
    }
    if ($rulesetsOk) { $protectedRulesets = UniqSort $hits }
  }
}
if (-not $rulesetsOk) {
  $protectedRulesets = @()
  Add-Warn 'rulesets-unavailable'
}
function Is-RuleProtected([string]$n) {
  if (@($protectedRulesets).Count -eq 0) { return $false }
  return ($protectedRulesets -ccontains $n)
}

# ---------- 输出候选（过滤掉规则集覆盖的分支）----------
$localMerged = @($localMergedPre | Where-Object { -not (Is-RuleProtected $_) })
$remoteMerged = @($remotePre | Where-Object { -not (Is-RuleProtected $_.branch) })

# worktree 检出报告（只报告，不作为删除判据——git branch -d 本身就拒绝删除被 worktree 检出的分支）
$wtRaw = GitOut @('worktree','list','--porcelain')
$wtBranches = @($wtRaw -split "`n" | Where-Object { $_ -match '^branch refs/heads/' } | ForEach-Object { ($_ -replace '^branch refs/heads/','').Trim() } | Sort-Object -Unique)

$result = [ordered]@{
  is_git                       = $true
  default_branch               = $default
  default_branch_source        = $defaultSource
  current_branch               = $current
  remote_reachable             = $remoteReachable
  protected_from_rulesets      = @($protectedRulesets)
  local_merge_base             = $localMergeBase
  remote_merge_base            = $remoteMergeBase
  remote_base_unverified       = $remoteBaseUnverified
  protected                    = $protected
  local_merged_candidates      = @($localMerged)
  local_stale_unmerged_report  = @($localStale)
  remote_merged_candidates     = @($remoteMerged)
  worktree_branches            = @($wtBranches)
  warnings                     = @($warns)
}
Write-Output (ConvertTo-Json -Depth 8 $result)
