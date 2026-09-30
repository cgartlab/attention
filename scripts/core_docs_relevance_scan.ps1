#requires -Version 7.0
<#
.SYNOPSIS
  Scan core docs for references to changed source files (read-only).
.DESCRIPTION
  Read-only: prints one JSON object on stdout (contract: references/scan-recipes.md §4).
  This is a LOW-PRECISION hint, not a verdict on whether docs need updating.
  --repo must exist and be a directory; otherwise the script prints
  {"is_git":false,"error":"repo path not found"} and exits 0.
.PARAMETER repo
  Repository path (default: current directory).
.PARAMETER defaultBranch
  Override the auto-detected default branch.
.EXAMPLE
  pwsh -NoProfile -File scripts/core_docs_relevance_scan.ps1 --repo D:\code\myproj
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
  Write-Host "Usage: pwsh -NoProfile -File core_docs_relevance_scan.ps1 [--repo <path>] [--defaultBranch <name>] [--help]"
  Write-Host ""
  Write-Host "Read-only scan of core docs against the change set, printed as one JSON object."
  Write-Host "This is a LOW-PRECISION hint, not a verdict on whether docs need updating."
  Write-Host ""
  Write-Host "  --repo <path>            Repository path (default: current directory). Must exist and"
  Write-Host "                           be a directory, otherwise prints"
  Write-Host "                           {""is_git"":false,""error"":""repo path not found""} and exits 0."
  Write-Host "  --defaultBranch <name>   Override the auto-detected default branch."
  Write-Host "  --help, -h               Print this usage and exit 0."
  Write-Host ""
  Write-Host "Fields: is_git, core_docs, changed_files, changed_basenames, docs_mentioning_changes,"
  Write-Host "docs_stale_candidates, warnings."
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

$changedArr = @()
$changedArr += GitZ @('diff','--cached','--name-only','--no-renames','-z')
$changedArr += GitZ @('diff','--name-only','--no-renames','-z')
$changedArr += GitZ @('ls-files','--others','--exclude-standard','-z')
if ($default -and (GitOk @('rev-parse','--verify',"refs/remotes/origin/$default"))) {
  $changedArr += GitZ @('diff','--name-only','--no-renames','-z',"origin/$default..HEAD")
}
$changed = UniqSort ($changedArr | ForEach-Object { ToPosix $_ })
$changedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($c in $changed) { [void]$changedSet.Add($c) }

$basenames = @()
foreach ($c in $changed) {
  $i = $c.LastIndexOf('/')
  $bn = if ($i -ge 0) { $c.Substring($i + 1) } else { $c }
  if ($bn) { $basenames += $bn }
}
$changedBasenames = UniqSort $basenames

# 核心文档：顶层普通文件（前缀匹配，区分大小写）+ docs/**/*.md（排序后前 50 个）
$coreRaw = @()
foreach ($f in @(Get-ChildItem -File -ErrorAction SilentlyContinue)) {
  if ($f.Name -cmatch '^(README|CHANGELOG|CHANGES|HISTORY|CONTRIBUTING|LICENSE|AGENTS|CLAUDE)') { $coreRaw += $f.Name }
}
if (Test-Path -LiteralPath 'docs') {
  $docsRoot = (Resolve-Path -LiteralPath 'docs').Path
  $dl = @(Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = $_.FullName.Substring($docsRoot.Length).TrimStart('\','/')
    'docs/' + (ToPosix $rel)
  })
  $dl = UniqSort $dl
  $coreRaw += @($dl | Select-Object -First 50)
}
$coreDocs = UniqSort $coreRaw

$coreDocsOut = @()
$mentioning = @()
$stale = @()
foreach ($doc in $coreDocs) {
  $exists = Test-Path -LiteralPath $doc -PathType Leaf
  $coreDocsOut += [pscustomobject]@{ file = $doc; exists = $exists }
  if (-not $exists) { continue }
  $content = Get-Content -Raw -LiteralPath $doc -ErrorAction SilentlyContinue
  $refs = @()
  foreach ($bn in $changedBasenames) {
    if ($content -and ($content -match [regex]::Escape($bn))) { $refs += $bn }
  }
  if ($refs.Count -gt 0) {
    $mentioning += [pscustomobject]@{ doc = $doc; references = @($refs) }
  } elseif (-not $changedSet.Contains($doc)) {
    $stale += $doc
  }
}

$result = [ordered]@{
  is_git                = $true
  core_docs             = @($coreDocsOut)
  changed_files         = $changed
  changed_basenames     = $changedBasenames
  docs_mentioning_changes = @($mentioning)
  docs_stale_candidates = UniqSort $stale
  warnings              = @()
}
Write-Output (ConvertTo-Json -Depth 8 $result)
