#requires -Version 7.0
<#
.SYNOPSIS
  Gather signals for next-step development suggestions (read-only).
.DESCRIPTION
  Read-only: prints one JSON object of raw signals on stdout (contract:
  references/scan-recipes.md §5). The model reasons over these signals.
  --repo must exist and be a directory; otherwise the script prints
  {"is_git":false,"error":"repo path not found"} and exits 0.
.PARAMETER repo
  Repository path (default: current directory).
.PARAMETER defaultBranch
  Override the auto-detected default branch (used for behind_default).
.EXAMPLE
  pwsh -NoProfile -File scripts/next_steps_analysis.ps1 --repo D:\code\myproj
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
function NonBlank { param($Lines); return ,@(@($Lines) | Where-Object { $null -ne $_ -and ([string]$_).Trim() -ne '' }) }
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
function MaskUrl([string]$u) {
  if (-not $u) { return $null }
  if ($u -match '^([A-Za-z][A-Za-z0-9+.-]*://)[^/]*@') { return ($u -replace '^([A-Za-z][A-Za-z0-9+.-]*://)[^/]*@', '${1}***@') }
  if ($u -match '^[^/@]+@[^/]*:') { return ($u -replace '^[^/@]+@', '***@') }
  return $u
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
  Write-Host "Usage: pwsh -NoProfile -File next_steps_analysis.ps1 [--repo <path>] [--defaultBranch <name>] [--help]"
  Write-Host ""
  Write-Host "Read-only signal collection for next-step suggestions, as one JSON object."
  Write-Host ""
  Write-Host "  --repo <path>            Repository path (default: current directory). Must exist and"
  Write-Host "                           be a directory, otherwise prints"
  Write-Host "                           {""is_git"":false,""error"":""repo path not found""} and exits 0."
  Write-Host "  --defaultBranch <name>   Override the auto-detected default branch (used for"
  Write-Host "                           behind_default)."
  Write-Host "  --help, -h               Print this usage and exit 0."
  Write-Host ""
  Write-Host "Fields: is_git, default_branch, behind_default, recent_commits, is_github,"
  Write-Host "remote_url_masked, gh_authed, gh_query_state, open_issues, open_prs, todo_fixme,"
  Write-Host "branches, test_commands, missing_core_docs, warnings."
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

$tmpR = NonBlank (GitOut @('log','--oneline','-n','15'))
$recent = @($tmpR)

# 远端 host 判定按主机名（不得对整条 URL 子串匹配）
$remoteLine = Git1 @('remote','-v')
$remoteUrl = $null
if ($remoteLine) {
  $rp = @($remoteLine -split '\s+' | Where-Object { $_ -ne '' })
  if ($rp.Count -ge 2) { $remoteUrl = $rp[1] }
}
# 注意：不要用 $host —— PowerShell 的自动变量 $Host 大小写不敏感，会被它顶替
$remoteHost = HostOfUrl $remoteUrl
$isGithub = $false
if ($remoteHost -eq 'github.com' -or ($remoteHost -and $remoteHost.EndsWith('.github.com', [System.StringComparison]::OrdinalIgnoreCase))) { $isGithub = $true }
$remoteUrlMasked = $null
if ($remoteUrl) { $remoteUrlMasked = MaskUrl $remoteUrl }
# gh_authed：**本地凭据探测**——`gh auth token` 只读本地凭据存储、不联网，退出码确定性。
# 绝不用 `gh auth status`：它会做 API 校验，并发/机器繁忙时偶发非 0，会把"没查成"
# 写成事实性的"未认证"，并连带翻转 gh-host-mismatch（违反 §5"没查成必须留痕"）。
# gh 不存在时沿用原降级口径：gh_authed=false，不新增警告码。
$ghAuthed = $false
$ghExe = (Get-Command gh -ErrorAction SilentlyContinue).Source
if ($ghExe) {
  & $ghExe auth token *> $null
  if ($LASTEXITCODE -eq 0) {
    $ghAuthed = $true
    # 宿主不匹配 = 远端 host 在本地凭据里没有 token（同样只读本地、不联网）。
    # 网络可达性是另一件事，由 remote_reachable / gh_query_state 表达。
    if ($remoteHost) {
      & $ghExe auth token --hostname $remoteHost *> $null
      if ($LASTEXITCODE -ne 0) { Add-Warn 'gh-host-mismatch' }
    }
  }
}

# 查询失败 -> null + gh-query-failed（绝不输出 []，那会被读成"确实没有开放 issue/PR"）
$issues = $null; $prs = $null; $ghState = 'not-applicable'
if ($isGithub -and $ghAuthed) {
  $iout = @(& $ghExe issue list --state open --limit 20 2>$null); $irc = $LASTEXITCODE
  $pout = @(& $ghExe pr list --state open --limit 20 2>$null); $prc = $LASTEXITCODE
  if ($irc -eq 0 -and $prc -eq 0) {
    $ghState = 'ok'
    $tmpI = NonBlank $iout
    $issues = @($tmpI)
    $tmpP = NonBlank $pout
    $prs = @($tmpP)
  } else {
    $ghState = 'unavailable'
    Add-Warn 'gh-query-failed'
  }
}

# --untracked 必须放在 pattern 之前；排除表按仓库根锚定（:(exclude,top)）
# XXX 必须排除连续的 X 串（mktemp 模板里的 XXXXXX/XXXXXXXX 不是待办）：
# `(^|[^X])XXX([^X]|$)` 只命中「左右都不是 X」的孤立 XXX。
$tout = @(GitOut @('grep','--untracked','-n','-E','-e','TODO|FIXME|HACK|(^|[^X])XXX([^X]|$)','--','.',
  ':(exclude,top)*.md',':(exclude,top)*.markdown',':(exclude,top)*.json',':(exclude,top)*.rst',
  ':(exclude,top)scripts/next_steps_analysis.ps1',':(exclude,top)scripts/next_steps_analysis.sh',':(exclude,top)evals/'))
$grc = $LASTEXITCODE
if ($grc -gt 1) { Add-Warn 'git-grep-failed' }
$tmpT = NonBlank $tout
$todos = @($tmpT | Select-Object -First 30)

$tmpB = NonBlank (GitOut @('for-each-ref','--format=%(refname:short)%09%(committerdate:iso-strict)','refs/heads'))
$blines = [string[]]@($tmpB)
if ($blines.Count -gt 1) { [Array]::Sort($blines, [System.StringComparer]::Ordinal) }
$branches = @()
foreach ($line in $blines) {
  $p = $line -split "`t"
  if ($p.Count -ge 2 -and $p[0]) { $branches += [pscustomobject]@{ branch = $p[0]; last_commit = ($p[1] -replace '\r$','') } }
}

$testCmds = @()
$tcNames = @()
function Add-TestCmd([string]$name, [string]$script) {
  if (-not $name -or -not $script) { return }
  if ($script:tcNames -ccontains $name) { return }
  $script:tcNames += $name
  $script:testCmds += [pscustomobject]@{ name = $name; script = $script }
}
if (Test-Path -LiteralPath 'package.json') {
  try {
    $pj = Get-Content -Raw -LiteralPath 'package.json' | ConvertFrom-Json
    if ($pj.scripts) {
      foreach ($k in 'test','lint','build','check','typecheck','format') {
        $p = $pj.scripts.PSObject.Properties[$k]
        if ($p) { Add-TestCmd $k ([string]$p.Value) }
      }
    }
  } catch {}
}
if (Test-Path -LiteralPath 'Makefile') {
  $mk = Get-Content -Raw -LiteralPath 'Makefile'
  foreach ($t in 'test','lint','build','check') {
    if ($mk -cmatch "(?m)^$t\s*:") { Add-TestCmd $t "make $t" }
  }
}
if (Test-Path -LiteralPath 'pyproject.toml') {
  $py = Get-Content -Raw -LiteralPath 'pyproject.toml'
  foreach ($t in 'pytest','ruff','mypy') {
    if ($py -cmatch $t) { Add-TestCmd $t $t }
  }
}
# 本 skill 自带的测试入口：evals/run_evals.* 与 scripts/smoke_test.*。
# 「这个项目有没有测试」的真实答案就在这两个文件上，不识别就等于看不见（实测本仓库
# test_commands=[]）。script 给出对应实现路径：两套都存在时**确定性**地选 .sh
#（不按「能否执行」探测——探测结果会随运行本脚本的 shell 变化，反而破坏 .sh/.ps1 parity）。
function Add-SkillTestCmd([string]$name, [string]$basePath) {
  if (Test-Path -LiteralPath "$basePath.sh" -PathType Leaf) { Add-TestCmd $name "$basePath.sh" }
  elseif (Test-Path -LiteralPath "$basePath.ps1" -PathType Leaf) { Add-TestCmd $name "$basePath.ps1" }
}
Add-SkillTestCmd 'run_evals' 'evals/run_evals'
Add-SkillTestCmd 'smoke_test' 'scripts/smoke_test'

# 默认分支探测
$default = $null
if ($DefaultArg) { $default = $DefaultArg }
else {
  $sym = Git1 @('symbolic-ref','--quiet','--short','refs/remotes/origin/HEAD')
  if ($sym) { $default = ($sym -replace '^origin/','') }
  if (-not $default) {
    $lr = Git1 @('ls-remote','--symref','origin','HEAD')
    if ($lr -and $lr -match '^ref:\s+(\S+)') { $default = ($Matches[1] -replace '^refs/heads/','') }
  }
  if (-not $default) {
    foreach ($b in 'main','master','develop','trunk') {
      if (GitOk @('show-ref','--verify','--quiet',"refs/heads/$b")) { $default = $b; break }
    }
  }
}

$behind = $null
if ($default -and (GitOk @('rev-parse','--verify',"refs/remotes/origin/$default"))) {
  $cnt = Git1 @('rev-list','--count',"origin/$default..HEAD")
  if ($cnt) { $b0 = 0; if ([int]::TryParse($cnt, [ref]$b0)) { $behind = $b0 } }
}

# 缺失核心文档：顶层普通文件前缀精确匹配，区分大小写（与 Linux 上 git 行为对齐）
$tops = @(Get-ChildItem -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
$missing = @()
foreach ($e in 'README','CHANGELOG','LICENSE','AGENTS','CONTRIBUTING') {
  $found = $false
  foreach ($t in $tops) { if ([string]$t -and ([string]$t).StartsWith($e, [System.StringComparison]::Ordinal)) { $found = $true; break } }
  if (-not $found) { $missing += $e }
}

$result = [ordered]@{
  is_git            = $true
  default_branch    = $default
  behind_default    = $behind
  recent_commits    = $recent
  is_github         = $isGithub
  remote_url_masked = $remoteUrlMasked
  gh_authed         = $ghAuthed
  gh_query_state    = $ghState
  open_issues       = $issues
  open_prs          = $prs
  todo_fixme        = $todos
  branches          = @($branches)
  test_commands     = @($testCmds)
  missing_core_docs = @($missing)
  warnings          = @($warns)
}
Write-Output (ConvertTo-Json -Depth 8 $result)
