#requires -Version 7.0
<#
.SYNOPSIS
  冒烟自检：对目标仓库跑全部 5 个采集脚本（两套实现），校验 JSON 与语义正确性。
.DESCRIPTION
  与"只要能解析出 is_git 就算过"的旧版不同，本冒烟会断言：
    1) 输出是合法 JSON 且含 is_git；
    2) is_git 与"该路径是否真的在 git 工作树里"（git rev-parse 独立判定）一致；
    3) 在仓库内时，repo_root 必须等于 git 给出的 toplevel（防止"静默分析了别的仓库"这类错误结论，见 docs/QUALITY-AUDIT.md D1）。
  .ps1 始终运行；bash 可用时（按"能否执行"探测）同时运行 .sh 并各自断言。
  bash 不可用时 .sh 记为 SKIP（不算通过）。
.PARAMETER repo
  目标仓库路径。缺省为当前目录。路径不存在/不是目录 → [FAIL] 并退出 1（绝不回退当前目录）。
.EXAMPLE
  pwsh -NoProfile -File scripts/smoke_test.ps1 --repo D:\code\myproj
#>
$ErrorActionPreference = 'SilentlyContinue'

$RepoArg = $null; $HaveRepoArg = $false; $Help = $false
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
  $a = [string]$argv[$i]
  if ($a -eq '--repo') { if ($i + 1 -lt $argv.Count) { $RepoArg = [string]$argv[$i + 1]; $i++ } else { $HaveRepoArg = $true } }
  elseif ($a -eq '--help' -or $a -eq '-h') { $Help = $true }
}
if ($Help) {
  Write-Host "Usage: pwsh -NoProfile -File smoke_test.ps1 [--repo <path>]"
  Write-Host "Runs all 5 collectors (both implementations when bash is available) and asserts:"
  Write-Host "  valid JSON; is_git matches reality; repo_root matches git's toplevel."
  exit 0
}
if ($HaveRepoArg -or ($RepoArg -and -not (Test-Path -LiteralPath $RepoArg -PathType Container))) {
  Write-Host "[FAIL] --repo path not found: $(if ($RepoArg) { $RepoArg } else { '<missing>' })"
  exit 1
}

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = if ($RepoArg) { (Resolve-Path -LiteralPath $RepoArg).Path } else { (Get-Location).Path }
function Norm([string]$p) { if (-not $p) { return '' } ; return (($p -replace '\\','/') -replace '/+$','').ToLowerInvariant() }

# 事实：目标是否在 git 工作树里、toplevel 是什么（独立于被测脚本）
$isRepo = ((& git -C $target rev-parse --is-inside-work-tree 2>$null) | Select-Object -First 1) -eq 'true'
$toplevel = $null
if ($isRepo) { $toplevel = (& git -C $target rev-parse --show-toplevel 2>$null) | Select-Object -First 1 }
Write-Host "target: $target"
Write-Host "git 判定: is_git=$isRepo  toplevel=$(if ($toplevel) { $toplevel } else { '-' })"

# bash 探测：按"能否执行"，不是看文件在不在
$bashExe = $null
$c = Get-Command bash -ErrorAction SilentlyContinue
if ($c) { $bashExe = $c.Source } elseif (Test-Path 'C:\Program Files\Git\bin\bash.exe') { $bashExe = 'C:\Program Files\Git\bin\bash.exe' }
$bashOk = $false
if ($bashExe) {
  $o = & $bashExe -c 'echo ok' 2>$null
  $bashOk = ($LASTEXITCODE -eq 0) -and (($o | Out-String).Trim() -eq 'ok')
}
if (-not $bashOk) { Write-Host "[warn] bash 不可用：.sh 侧记为 SKIP（不算通过）" -ForegroundColor Yellow }

function To-Posix([string]$p) { $s = $p -replace '\\','/'; if ($s -match '^([A-Za-z]):(.*)$') { $s = '/' + $Matches[1].ToLower() + $Matches[2] } ; return $s }

$names = 'git_state_snapshot','branch_cleanup_audit','version_consistency_audit','core_docs_relevance_scan','next_steps_analysis'
$pass = 0; $fail = 0; $skip = 0
foreach ($impl in @('ps1','sh')) {
  foreach ($n in $names) {
    $label = "$n ($impl)"
    if ($impl -eq 'sh' -and -not $bashOk) { Write-Host "[SKIP] $label"; $skip++; continue }
    if ($impl -eq 'ps1') {
      $out = & pwsh -NoProfile -File "$base\$n.ps1" --repo $target 2>$null | Out-String
      $code = $LASTEXITCODE
    } else {
      $out = & $bashExe (To-Posix "$base/$n.sh") --repo (To-Posix $target) 2>$null | Out-String
      $code = $LASTEXITCODE
    }
    $reason = $null
    $j = $null
    try { $j = $out | ConvertFrom-Json } catch { $reason = '非法 JSON' }
    if (-not $reason) {
      if ($null -eq $j.is_git) { $reason = '缺 is_git 字段' }
      elseif ([bool]$j.is_git -ne $isRepo) { $reason = "is_git=$($j.is_git) 与事实($isRepo) 不一致" }
      elseif ($isRepo -and $j.PSObject.Properties['repo_root'] -and (Norm $j.repo_root) -ne (Norm $toplevel)) { $reason = "repo_root=$($j.repo_root) 与 git toplevel($toplevel) 不一致（疑似分析了别的仓库）" }
      elseif (-not $isRepo -and -not $j.error) { $reason = '非 git 目录但缺 error 字段' }
      elseif ($code -ne 0) { $reason = "退出码 $code（应恒为 0）" }
    }
    if ($reason) { Write-Host "[FAIL] $label — $reason"; $fail++ } else { Write-Host "[OK]   $label"; $pass++ }
  }
}
Write-Host "smoke_test: $pass passed, $fail failed, $skip skipped (repo: $target)"
if ($fail -gt 0) { exit 1 } else { exit 0 }
