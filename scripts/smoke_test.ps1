#requires -Version 7.0
<#
.SYNOPSIS
  Smoke-test: run all 5采集 scripts on a repo, verify each emits valid JSON (read-only).
.DESCRIPTION
  One-command regression check. Prints [OK]/[FAIL] per script + summary; exit 1 if any fail.
.PARAMETER repo
  Path to the repository. Defaults to current location.
.EXAMPLE
  pwsh -NoProfile -File scripts/smoke_test.ps1 --repo D:\code\myproj
#>
param([string]$repo,[switch]$help)
if ($help) { Write-Host "Usage: pwsh -NoProfile -File smoke_test.ps1 [--repo <path>]"; Write-Host "Runs all 5采集 scripts; verifies each emits valid JSON (has is_git)."; exit 0 }
if ($repo) { Set-Location -LiteralPath $repo }
$ErrorActionPreference = 'SilentlyContinue'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$names = 'git_state_snapshot','branch_cleanup_audit','version_consistency_audit','core_docs_relevance_scan','next_steps_analysis'
$pass = 0; $fail = 0
foreach ($n in $names) {
  $out = & pwsh -NoProfile -File "$base\$n.ps1" --repo $PWD 2>$null
  $ok = $false
  try { $j = $out | ConvertFrom-Json; if ($null -ne $j.is_git) { $ok = $true } } catch {}
  if ($ok) { Write-Host "[OK]   $n"; $pass++ } else { Write-Host "[FAIL] $n"; $fail++ }
}
Write-Host "smoke_test: $pass passed, $fail failed (repo: $PWD)"
if ($fail -gt 0) { exit 1 } else { exit 0 }