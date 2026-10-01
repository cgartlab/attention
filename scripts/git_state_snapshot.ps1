#requires -Version 7.0
<#
.SYNOPSIS
  Snapshot the git working-tree state of a repository as JSON (read-only).
.DESCRIPTION
  Read-only: runs git plumbing commands only and prints one JSON object on stdout
  (contract: references/scan-recipes.md §1). Never mutates the repository.
  --repo must exist and be a directory; otherwise the script prints
  {"is_git":false,"error":"repo path not found"} and exits 0. It never silently
  falls back to the current directory.
.PARAMETER repo
  Repository path (default: current directory).
.PARAMETER defaultBranch
  Override the auto-detected default branch.
.EXAMPLE
  pwsh -NoProfile -File scripts/git_state_snapshot.ps1 --repo D:\code\myproj
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
function GitZ {
  param([string[]]$a)
  $raw = @(GitOut $a)
  if ($raw.Count -eq 0) { return ,@() }
  $j = ($raw -join "`0")
  return ,@($j -split "`0" | Where-Object { $_ -ne '' })
}
# GitZ 用 ,@() 保住空数组，因此它的返回值不能再直接进管道（会整体当一个对象）。
# 需要逐元素处理时走这里：先落地成数组，再枚举。
function GitZPaths {
  param([string[]]$a)
  $r = GitZ $a
  $out = @()
  foreach ($x in @($r)) { $out += (ToPosix $x) }
  return ,$out
}
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
function ToPosix([string]$p) {
  if ($null -eq $p) { return $p }
  return ($p -replace '\\','/' -replace '\r$','')
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

# ---------- 入参（不用 param()：--repo 漏值时 PowerShell 会直接绑定失败并吞掉 stdout） ----------
$RepoArg = $null; $HaveRepoArg = $false; $DefaultArg = $null; $Help = $false
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
  $a = [string]$argv[$i]
  if ($a -eq '--repo') { if ($i + 1 -lt $argv.Count) { $RepoArg = [string]$argv[$i + 1]; $i++ } else { $HaveRepoArg = $true } }
  elseif ($a -eq '--defaultBranch') { if ($i + 1 -lt $argv.Count) { $DefaultArg = [string]$argv[$i + 1]; $i++ } }
  elseif ($a -eq '--help' -or $a -eq '-h') { $Help = $true }
}

if ($Help) {
  Write-Host "Usage: pwsh -NoProfile -File git_state_snapshot.ps1 [--repo <path>] [--defaultBranch <name>] [--help]"
  Write-Host ""
  Write-Host "Read-only snapshot of one repository as a single JSON object on stdout."
  Write-Host ""
  Write-Host "  --repo <path>            Repository path (default: current directory). Must exist and"
  Write-Host "                           be a directory, otherwise the script prints"
  Write-Host "                           {""is_git"":false,""error"":""repo path not found""} and exits 0 -- it"
  Write-Host "                           never silently falls back to the current directory."
  Write-Host "  --defaultBranch <name>   Override the auto-detected default branch."
  Write-Host "  --help, -h               Print this usage and exit 0."
  Write-Host ""
  Write-Host "Fields: is_git, repo_root, has_remote, remote_host, current_branch, detached, head_short,"
  Write-Host "upstream, ahead, behind, default_branch, default_branch_source, staged, unstaged, untracked,"
  Write-Host "stash_count, recent_changed_files, unpushed_commits, unpushed_branches, warnings."
  Write-Host "Never mutates the repository."
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

$root = ToPosix (Git1 @('rev-parse','--show-toplevel'))
$branch = Git1 @('symbolic-ref','--quiet','--short','HEAD')
$detached = [string]::IsNullOrEmpty($branch)
$headShort = Git1 @('rev-parse','--short','HEAD')
if (-not $headShort) { Add-Warn 'head-unborn' }
$upstream = Git1 @('rev-parse','--abbrev-ref','--symbolic-full-name','@{u}')
if ($upstream -eq 'HEAD') { $upstream = $null }

$ahead = $null; $behind = $null
if ($upstream) {
  $counts = Git1 @('rev-list','--left-right','--count','@{u}...HEAD')
  if ($counts) {
    $p = @($counts -split '\s+' | Where-Object { $_ -ne '' })
    if ($p.Count -ge 2) { $behind = [int]$p[0]; $ahead = [int]$p[1] }
  }
}

$hasRemote = $false; $remoteHost = $null
$remotes = @(GitOut @('remote'))
if ($remotes.Count -gt 0) {
  $hasRemote = $true
  $url = Git1 @('remote','get-url','origin')
  if (-not $url) { $url = Git1 @('remote','get-url',[string]$remotes[0]) }
  $remoteHost = HostOfUrl $url
}

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

$staged = UniqSort (GitZPaths @('diff','--cached','--name-only','--no-renames','-z'))
$unstaged = UniqSort (GitZPaths @('diff','--name-only','--no-renames','-z'))
$untracked = UniqSort (GitZPaths @('ls-files','--others','--exclude-standard','-z'))

$stashCount = 0
$stashList = @(GitOut @('stash','list'))
if ($stashList.Count -gt 0) { $stashCount = @($stashList | Where-Object { $_ -ne '' }).Count }

# 近期变更文件：n=min(10, 第一父链提交数-1)；n==0（仅根提交）时回退 git show --name-only HEAD。
# 两个坑（审计发现）：(1) 用 rev-list --count 会计入侧分支提交，而 HEAD~n 只走第一父链 -> HEAD~n 不存在；
# (2) 写成 min(10, count) 时提交数<=10 会直接变空。故计数必须加 --first-parent。
$recent = @()
$ccRaw = Git1 @('rev-list','--count','--first-parent','HEAD')
$cc = 0
if ($ccRaw -and [int]::TryParse($ccRaw, [ref]$cc)) {
  if ($cc -gt 0) {
    $n = [Math]::Min(10, $cc - 1)
    if ($cc -eq 1) {
      $recent = UniqSort (GitZPaths @('show','--name-only','--format=','-z','HEAD'))
    } else {
      $recent = UniqSort (GitZPaths @('diff','--name-only','--no-renames','-z',"HEAD~$n..HEAD"))
    }
  }
}

# 未推送提交：origin/<default> 优先，其次 upstream；都没有 -> null。
# null 有两种语义，必须靠 has_remote 区分：has_remote=false -> **不适用**（没有远程可推，
# 加 no-remote 警告）；has_remote=true 但取不到可比 ref -> **不可判定**。不得输出 []。
if (-not $hasRemote) { Add-Warn 'no-remote' }
$unpushed = $null
$range = $null
if ($default -and (GitOk @('rev-parse','--verify',"refs/remotes/origin/$default"))) {
  $range = "origin/$default..HEAD"
} elseif ($upstream -and (GitOk @('rev-parse','--verify',$upstream))) {
  $range = "$upstream..HEAD"
}
if ($range) {
  $unpushed = @(GitOut @('log','--oneline',$range) | Where-Object { $_ -ne '' })
}

# 未推送分支：tip 不被任何 refs/remotes/* 覆盖的本地分支。
# **has_remote=false 时必须输出 []**：没有远程就没有「未推送分支」这一概念。
# 否则一个完全干净的纯本地仓库会输出 ["main"]，配合判定条款会被判成脏态，
# 进而去尝试推送一个不存在的远程（实测本仓库即如此）。
$unpushedBranches = @()
if ($hasRemote) {
  $unpushedShas = @(GitOut @('rev-list','--branches','--not','--remotes'))
  $hsU = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($s in $unpushedShas) { if ($s) { [void]$hsU.Add(([string]$s).Trim()) } }
  $ub = New-Object System.Collections.Generic.List[string]
  foreach ($line in @(GitOut @('for-each-ref','--format=%(objectname) %(refname:short)','refs/heads'))) {
    if (-not $line) { continue }
    $sp = $line.IndexOf(' ')
    if ($sp -lt 1) { continue }
    $sha = $line.Substring(0, $sp)
    $name = $line.Substring($sp + 1).Trim()
    if ($name -and $hsU.Contains($sha)) { $ub.Add($name) }
  }
  $unpushedBranches = UniqSort $ub
}

$result = [ordered]@{
  is_git              = $true
  repo_root           = $root
  has_remote          = $hasRemote
  remote_host         = $remoteHost
  current_branch      = $branch
  detached            = $detached
  head_short          = $headShort
  upstream            = $upstream
  ahead               = $ahead
  behind              = $behind
  default_branch      = $default
  default_branch_source = $defaultSource
  staged              = $staged
  unstaged            = $unstaged
  untracked           = $untracked
  stash_count         = $stashCount
  recent_changed_files = $recent
  unpushed_commits    = $unpushed
  unpushed_branches   = $unpushedBranches
  warnings            = @($warns)
}
Write-Output (ConvertTo-Json -Depth 8 $result)
