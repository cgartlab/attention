#Requires -Version 7.0
<#
.SYNOPSIS
  发布前自检（preflight）：把"能不能发"变成一组可判定的检查。
.DESCRIPTION
  这是"商业产品级发布"的第一道闸：在打 tag / 建 Release 之前，先在本地把该过的门都过一遍。
  它**只读**——不改文件、不提交、不打 tag、不推送；失败即非零退出。

  检查项（每项都有明确的通过与失败判据）：
    1) 工作区干净（无 staged/unstaged/untracked 改动）
    2) 分支状态：默认分支上直接发版要显式 -AllowDefaultBranch
    3) 版本一致性：version_consistency_audit 的 consistent 为 true；null 视为"无从判定"→ 失败
    4) CHANGELOG 就绪：[Unreleased] 存在且至少有一条条目
    5) 三层校验：evals/run_evals.ps1（严格 JSON + 双实现 parity + 断言表）
    6) 冒烟：scripts/smoke_test.ps1（双实现语义断言）
.PARAMETER Repo
  仓库路径，默认当前目录。
.PARAMETER SkipTests
  跳过第 5、6 项（只做静态检查；CI 上不要用这个）。
.PARAMETER AllowDefaultBranch
  允许在默认分支上准备发布（默认禁止：发版走 PR 更安全）。
.EXAMPLE
  pwsh -NoProfile -File scripts/release_preflight.ps1 --repo .
#>
# 手工解析 $args：**不用 param()** —— PowerShell 的参数绑定不接受本仓库统一的 `--kebab-case` 形式
# （`param([switch]$SkipTests)` 无法用 `--skip-tests` 传入），这是本仓库采集脚本的一致约定。
$Repo = $null; $SkipTests = $false; $AllowDefaultBranch = $false; $Help = $false; $Releasing = $null
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
  $a = [string]$argv[$i]
  if ($a -eq '--repo') {
    if ($i + 1 -lt $argv.Count) { $Repo = [string]$argv[$i + 1]; $i++ } else { Write-Host '[FAIL] --repo 缺少取值'; exit 1 }
  }
  elseif ($a -eq '--skip-tests') { $SkipTests = $true }
  elseif ($a -eq '--allow-default-branch') { $AllowDefaultBranch = $true }
  elseif ($a -eq '--releasing') {
    if ($i + 1 -lt $argv.Count) { $Releasing = [string]$argv[$i + 1]; $i++ } else { Write-Host '[FAIL] --releasing 缺少取值'; exit 1 }
  }
  elseif ($a -eq '--help' -or $a -eq '-h') { $Help = $true }
}

$ErrorActionPreference = 'Continue'
if ($Help) {
  Write-Host "Usage: pwsh -NoProfile -File release_preflight.ps1 [--repo <path>] [--skip-tests] [--allow-default-branch] [--releasing <version>] [--help]"
  Write-Host "只读的发布前自检：工作区/分支/版本一致性/CHANGELOG/三层校验/冒烟。失败即退出 1。"
  exit 0
}

if ($Repo) {
  if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
    Write-Host "[FAIL] --repo path not found: $Repo"; exit 1
  }
  Set-Location -LiteralPath $Repo
}
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $base

$checks = @()
function Add-Check([string]$name, [bool]$ok, [string]$detail) {
  $script:checks += [pscustomobject]@{ name = $name; ok = $ok; detail = $detail }
  $tag = if ($ok) { '[OK]  ' } else { '[FAIL]' }
  Write-Host ("{0} {1} {2}" -f $tag, $name, $(if ($detail) { "— $detail" } else { '' }))
}

# 1) 工作区干净
$dirty = @(git status --porcelain 2>$null)
Add-Check '工作区干净' ($dirty.Count -eq 0) $(if ($dirty.Count) { "$($dirty.Count) 处改动未提交（发布前必须先提交）" } else { '' })

# 2) 分支
$branch = (git symbolic-ref --quiet --short HEAD 2>$null)
# 默认分支：按契约梯子（origin/HEAD → 本地 main/master/develop/trunk），**不要**用 init.defaultBranch
$default = $null
$oh = (git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null)
if ($oh) { $default = $oh -replace '^origin/', '' }
if (-not $default) {
  foreach ($b in 'main','master','develop','trunk') {
    git show-ref --verify --quiet "refs/heads/$b"
    if ($LASTEXITCODE -eq 0) { $default = $b; break }
  }
}
if (-not $default) { $default = 'main' }
$onDefault = ($branch -eq $default)
Add-Check '分支状态' ((-not $onDefault) -or $AllowDefaultBranch) $(if ($onDefault) { "当前在默认分支 $default（发版建议走 PR；确要在此发版请加 --allow-default-branch）" } else { "当前 $branch（默认分支 $default）" })

# 3) 版本一致性
$vRaw = & pwsh -NoProfile -File (Join-Path $base 'version_consistency_audit.ps1') --repo $root 2>$null | Out-String
$v = $null; try { $v = $vRaw | ConvertFrom-Json } catch {}
if ($v) {
  $files = @($v.version_files | ForEach-Object { "$($_.file)=$($_.version)" })
  $ok = ($v.consistent -eq $true)
  Add-Check '版本一致性' $ok $(if ($v.consistent -eq $null) { "consistent=null（无版本文件 → 无从判定，不算通过）；files=[$($files -join ', ')]" } elseif ($ok) { "consistent=true；files=[$($files -join ', ')]" } else { "consistent=false：$($files -join ', ')（发布前必须一致）" })
} else { Add-Check '版本一致性' $false 'version_consistency_audit 未产出合法 JSON' }

# 4) CHANGELOG 就绪
#    开发期：要求 [Unreleased] 存在且至少 1 条（防止"没写变更就发版"）
#    发布期（--releasing <ver>）：要求存在 `## [<ver>]` 段且其下有条目——切版后 [Unreleased] 会被清空，
#    若仍按开发期判据检查，发布流水线会把自己挡住（这正是本模式存在的原因）
$clPath = Join-Path $root 'CHANGELOG.md'
if (Test-Path $clPath) {
  $cl = Get-Content $clPath -Raw
  if ($Releasing) {
    $esc = [regex]::Escape($Releasing)
    $hasVer = $cl -match ("##\s*\[" + $esc + "\]")
    $verBody = ''
    if ($hasVer) {
      $tail = ($cl -split ("##\s*\[" + $esc + "\]"))[1]
      $verBody = ($tail -split "`n## ")[0]
    }
    $vCount = @($verBody -split "`n" | Where-Object { $_ -match '^-\s' }).Count
    Add-Check "CHANGELOG 含 [$Releasing] 且有条目" ($hasVer -and $vCount -gt 0) $(if (-not $hasVer) { "找不到 `## [$Releasing]` 段" } elseif ($vCount -eq 0) { "[$Releasing] 段没有条目" } else { "发布段 [$Releasing] 有 $vCount 条" })
  } else {
    $hasUn = $cl -match '##\s*\[Unreleased\]'
    $unBody = ''
    if ($hasUn) {
      $tail = ($cl -split '##\s*\[Unreleased\]')[1]
      $unBody = ($tail -split "`n## ")[0]
    }
    $count = @($unBody -split "`n" | Where-Object { $_ -match '^-\s' }).Count
    Add-Check 'CHANGELOG [Unreleased] 就绪' ($hasUn -and $count -gt 0) $(if (-not $hasUn) { '找不到 [Unreleased] 段' } elseif ($count -eq 0) { '[Unreleased] 存在但没有条目（切版后请改用 --releasing <ver>）' } else { "$count 条待发布条目" })
  }
} else { Add-Check 'CHANGELOG 就绪' $false 'CHANGELOG.md 不存在' }

# 5) 三层校验
if ($SkipTests) {
  Write-Host '[SKIP] 三层校验（--skip-tests）'
  Write-Host '[SKIP] 冒烟（--skip-tests）'
} else {
  $ev = & pwsh -NoProfile -File (Join-Path $root 'evals/run_evals.ps1') -FixturesDir (Join-Path ([System.IO.Path]::GetTempPath()) 'attention-preflight') -NoWrite 2>&1 | Out-String
  $summary = ($ev -split "`n" | Where-Object { $_ -match 'checks:' }) -join ' '
  Add-Check '三层校验（严格 JSON + parity + 断言表）' ($LASTEXITCODE -eq 0) ($summary.Trim())
  $sm = & pwsh -NoProfile -File (Join-Path $base 'smoke_test.ps1') --repo $root 2>&1 | Out-String
  $smLine = ($sm -split "`n" | Where-Object { $_ -match 'smoke_test:' }) -join ' '
  Add-Check '冒烟（双实现语义断言）' ($LASTEXITCODE -eq 0) ($smLine.Trim())
}

$failed = @($checks | Where-Object { -not $_.ok })
Write-Host ''
Write-Host ('=' * 64)
Write-Host ("release_preflight: {0} passed / {1} failed" -f ($checks.Count - $failed.Count), $failed.Count)
Write-Host ('=' * 64)
if ($failed.Count) { exit 1 }
exit 0
