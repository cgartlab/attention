#Requires -Version 7.0
<#
.SYNOPSIS
  attention 采集脚本回归 runner：fixture × 脚本 × 双实现，三层校验。
.DESCRIPTION
  1) 严格 JSON（RFC 8259，拒绝裸控制字符）
  2) parity（.sh 与 .ps1 字段集 + 逐字段值一致）
  3) 断言表（evals/script-assertions.json）
  结果写入 evals/results/；任一失败 → 退出码 1。
.EXAMPLE
  pwsh -NoProfile -File evals/run_evals.ps1
  pwsh -NoProfile -File evals/run_evals.ps1 -Filter F7,F9
#>
[CmdletBinding()]
param(
  [string]$FixturesDir,
  [string[]]$Filter,
  [int]$TimeoutSeconds = 20,
  [switch]$Json,
  [switch]$NoWrite,
  [switch]$KeepTemp
)

$ErrorActionPreference = 'Continue'
$RepoRoot  = Split-Path -Parent $PSScriptRoot
$ScrDir    = Join-Path $RepoRoot 'scripts'
$SpecFile  = Join-Path $PSScriptRoot 'script-assertions.json'
$Scripts   = @('git_state_snapshot','branch_cleanup_audit','version_consistency_audit','core_docs_relevance_scan','next_steps_analysis')
$TempRoot  = if ($FixturesDir) { $FixturesDir } else { Join-Path ([System.IO.Path]::GetTempPath()) 'attention-evals' }
$RunDir    = Join-Path ([System.IO.Path]::GetTempPath()) ("attention-eval-runs-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

# ---------- 依赖探测 ----------
$pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) { $pwshExe = (Get-Process -Id $PID).Path }
$bashExe = $null
$cmd = Get-Command bash -ErrorAction SilentlyContinue
if ($cmd) { $bashExe = $cmd.Source }
elseif (Test-Path 'C:\Program Files\Git\bin\bash.exe') { $bashExe = 'C:\Program Files\Git\bin\bash.exe' }
$bashOk = $false
if ($bashExe) {
  try {
    $probe = Start-Process -FilePath $bashExe -ArgumentList '-c "echo ok"' -NoNewWindow -PassThru -Wait `
      -RedirectStandardOutput (Join-Path $RunDir 'bp.out') -RedirectStandardError (Join-Path $RunDir 'bp.err')
    $bashOk = ($probe.ExitCode -eq 0) -and ((Get-Content (Join-Path $RunDir 'bp.out') -Raw -ErrorAction SilentlyContinue) -match 'ok')
  } catch { $bashOk = $false }
}
if (-not $bashOk) { Write-Host "[warn] bash 不可用：.sh 侧将标记 SKIP（不视为通过）" -ForegroundColor Yellow }

function ConvertTo-PosixPath([string]$p) {
  $s = $p -replace '\\','/'
  if ($s -match '^([A-Za-z]):(.*)$') { $s = '/' + $Matches[1].ToLower() + $Matches[2] }
  return $s
}
function Invoke-ScriptOnce {
  param([string]$Impl, [string]$ScriptName, [string]$RepoPath, [int]$TimeoutSec, [switch]$NoValue)
  $so = Join-Path $RunDir ("{0}-{1}-{2}.out" -f $ScriptName, $Impl, [guid]::NewGuid().ToString('N').Substring(0,6))
  $se = "$so.err"
  if ($Impl -eq 'ps1') {
    $exe = $pwshExe
    $argStr = "-NoProfile -File `"$ScrDir\$ScriptName.ps1`" --repo `"$RepoPath`""
    if ($NoValue) { $argStr = "-NoProfile -File `"$ScrDir\$ScriptName.ps1`" --repo" }
  } else {
    if (-not $bashOk) { return [pscustomobject]@{ impl='sh'; skip=$true; stdout=''; stderr='bash unavailable'; exit=$null; ms=0; timedOut=$false } }
    $exe = $bashExe
    $posixScript = ConvertTo-PosixPath (Join-Path $ScrDir "$ScriptName.sh")
    $posixRepo   = ConvertTo-PosixPath $RepoPath
    $argStr = "`"$posixScript`" --repo `"$posixRepo`""
    if ($NoValue) { $argStr = "`"$posixScript`" --repo" }
  }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $proc = Start-Process -FilePath $exe -ArgumentList $argStr -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
  $exited = $proc.WaitForExit($TimeoutSec * 1000)
  $sw.Stop()
  if (-not $exited) { try { $proc.Kill() } catch {} }
  $out = if (Test-Path $so) { Get-Content $so -Raw -ErrorAction SilentlyContinue } else { '' }
  $err = if (Test-Path $se) { Get-Content $se -Raw -ErrorAction SilentlyContinue } else { '' }
  return [pscustomobject]@{
    impl = $Impl; skip = $false; stdout = ($out ?? ''); stderr = ($err ?? '')
    exit = $(if ($exited) { $proc.ExitCode } else { $null })
    ms = [int]$sw.Elapsed.TotalMilliseconds; timedOut = (-not $exited)
  }
}
function Test-StrictJson([string]$t) {
  if ([string]::IsNullOrWhiteSpace($t)) { return $false }
  try { $null = [System.Text.Json.JsonDocument]::Parse($t); return $true } catch { return $false }
}
function Get-RawValue { param($Obj, [string]$Path)
  $segs = $Path -split '\.'
  $cur = @($Obj); $ok = $true
  foreach ($seg0 in $segs) {
    $seg = $seg0; $expand = $false
    if ($seg.EndsWith('[]')) { $expand = $true; $seg = $seg.Substring(0, $seg.Length - 2) }
    $next = @()
    foreach ($o in $cur) {
      if ($null -eq $o) { continue }
      $prop = $o.PSObject.Properties[$seg]
      if (-not $prop) { $ok = $false; break }
      $val = $prop.Value
      if ($expand) {
        if ($val -is [System.Array]) { foreach ($v in $val) { $next += $v } }
        elseif ($null -ne $val) { $next += $val }
      } else { $next += $val }
    }
    if (-not $ok) { break }
    $cur = $next
  }
  return [pscustomobject]@{ found = $ok; values = @($cur) }
}
function Flatten { param($Values)
  $flat = @()
  foreach ($v in @($Values)) { if ($v -is [System.Array]) { foreach ($x in $v) { $flat += $x } } else { $flat += $v } }
  return ,@($flat)
}
function Compare-Parity { param($A, $B)
  $ka = @($A.PSObject.Properties.Name | Sort-Object); $kb = @($B.PSObject.Properties.Name | Sort-Object)
  if (($ka -join ',') -ne ($kb -join ',')) { return "字段集不同: sh=[$($ka -join ',')] ps1=[$($kb -join ',')]" }
  $diffs = @()
  foreach ($k in $ka) {
    $va = (ConvertTo-Json -InputObject $A.$k -Compress -Depth 8); $vb = (ConvertTo-Json -InputObject $B.$k -Compress -Depth 8)
    if ($va -ne $vb) { $diffs += "${k}: sh=$va ps1=$vb" }
  }
  if ($diffs.Count) { return ($diffs -join ' ; ') }
  return $null
}

# ---------- 生成 fixture ----------
$fixOut = (& $pwshExe -NoProfile -File (Join-Path $PSScriptRoot 'fixtures.ps1') -Json -OutDir $TempRoot 2>&1 | Out-String)
$fixJson = $null
try { $fixJson = $fixOut | ConvertFrom-Json } catch { Write-Error "fixtures.ps1 输出不是 JSON: $fixOut"; exit 2 }
$fixMap = @{}
foreach ($f in $fixJson.fixtures) { $fixMap[$f.id] = $f.path }

# 伪 fixture：无效 --repo
$negPath = Join-Path $RunDir 'no-such-dir'
$negFile = Join-Path $RunDir 'a-file.txt'
Set-Content -Path $negFile -Value 'plain' -Encoding UTF8
$fixMap['NEG-PATH'] = $negPath
$fixMap['NEG-FILE'] = $negFile
$fixMap['NEG-NOVALUE'] = $fixMap['F6']

$allIds = @($fixMap.Keys | Sort-Object)
if ($Filter) { $allIds = @($allIds | Where-Object { $id = $_; ($Filter | Where-Object { $id -like "*$_*" }).Count -gt 0 }) }
if ($allIds.Count -eq 0) { Write-Host "[warn] -Filter 未匹配任何 fixture → 0 检查，这不是通过" -ForegroundColor Yellow }

# 提前读取断言表：NEG-novalue 的挂死检查要用它声明的超时，避免"措辞 5s、实际 kill 另一个值"
$spec = Get-Content $SpecFile -Raw | ConvertFrom-Json
$hangTimeout = 5
$hangCheck = $spec.checks | Where-Object { $_.op -eq 'no_hang' } | Select-Object -First 1
if ($hangCheck -and $hangCheck.timeout_seconds) { $hangTimeout = [int]$hangCheck.timeout_seconds }

# ---------- 跑矩阵 ----------
$runs = @{}
$runList = @()
foreach ($id in $allIds) {
  foreach ($n in $Scripts) {
    foreach ($impl in @('sh','ps1')) {
      $key = "$id|$n|$impl"
      if ($id -eq 'NEG-NOVALUE') {
        $r = Invoke-ScriptOnce -Impl $impl -ScriptName $n -RepoPath $fixMap[$id] -TimeoutSec $hangTimeout -NoValue
      } else {
        $r = Invoke-ScriptOnce -Impl $impl -ScriptName $n -RepoPath $fixMap[$id] -TimeoutSec $TimeoutSeconds
      }
      $parsed = $null; $parseErr = $null
      if (-not $r.skip -and -not $r.timedOut) {
        try { $parsed = $r.stdout | ConvertFrom-Json } catch { $parseErr = $_.Exception.Message }
      }
      $runs[$key] = [pscustomobject]@{
        fixture = $id; script = $n; impl = $impl; skip = $r.skip; timedOut = $r.timedOut
        exit = $r.exit; ms = $r.ms; raw = $r.stdout; stderr = $r.stderr
        parsed = $parsed; parseError = $parseErr; strictJson = (Test-StrictJson $r.stdout)
      }
      $runList += $runs[$key]
      $tag = if ($r.skip) { 'SKIP' } elseif ($r.timedOut) { 'TIMEOUT' } else { "exit=$($r.exit)" }
      Write-Verbose "  $key $tag $($r.ms)ms"
    }
  }
}

# ---------- 校验 ----------
$results = @()
function Add-Result { param([string]$Id, [string]$Fixture, [string]$Script, [string]$Impl, [string]$Op, [bool]$Pass, [string]$Detail, [string]$Note)
  $script:results += [pscustomobject]@{ id=$Id; fixture=$Fixture; script=$Script; impl=$Impl; op=$Op; pass=$Pass; detail=$Detail; note=$Note }
}
foreach ($c in $spec.checks) {
  $fxIds = if ($c.fixtures -eq '*' -or -not $c.fixtures) { $allIds } else { @($c.fixtures) }
  $scrs  = if ($c.script -eq '*') { $Scripts } else { @($c.script) }
  $impls = if ($c.impl -eq '*') { @('sh','ps1') } else { @($c.impl) }
  foreach ($fx in $fxIds) {
    foreach ($sc in $scrs) {
      if ($c.op -eq 'parity') {
        $a = $runs["$fx|$sc|sh"]; $b = $runs["$fx|$sc|ps1"]
        if (-not $a -or -not $b) { continue }
        if ($a.skip -or $b.skip) { Add-Result $c.id $fx $sc 'sh+ps1' 'parity' $false 'SKIP(bash 不可用)' $c.note; continue }
        if ($a.timedOut -or $b.timedOut) { Add-Result $c.id $fx $sc 'sh+ps1' 'parity' $false 'TIMEOUT' $c.note; continue }
        if (-not $a.parsed -or -not $b.parsed) { Add-Result $c.id $fx $sc 'sh+ps1' 'parity' $false 'JSON 解析失败（见 strict_json 检查）' $c.note; continue }
        $d = Compare-Parity $a.parsed $b.parsed
        Add-Result $c.id $fx $sc 'sh+ps1' 'parity' ($null -eq $d) ($d ?? 'ok') $c.note
        continue
      }
      foreach ($im in $impls) {
        $run = $runs["$fx|$sc|$im"]
        if (-not $run) { continue }
        if ($run.skip) { Add-Result $c.id $fx $sc $im $c.op $false 'SKIP(bash 不可用)' $c.note; continue }
        switch ($c.op) {
          'strict_json' {
            Add-Result $c.id $fx $sc $im 'strict_json' $run.strictJson $(if ($run.strictJson) { 'ok' } else { '非法 JSON: ' + (($run.raw -replace '\s+',' ').Trim().Substring(0, [Math]::Min(160, (($run.raw -replace '\s+',' ').Trim()).Length))) }) $c.note
          }
          'no_hang' {
            Add-Result $c.id $fx $sc $im 'no_hang' (-not $run.timedOut) $(if ($run.timedOut) { "超过 $($c.timeout_seconds)s 未退出（疑似死循环）" } else { "退出于 $($run.ms)ms" }) $c.note
          }
          'raw_not_contains' {
            $hit = $run.raw -and $run.raw.Contains([string]$c.value)
            Add-Result $c.id $fx $sc $im 'raw_not_contains' (-not $hit) $(if ($hit) { "原始输出含敏感值" } else { 'ok' }) $c.note
          }
          default {
            if ($run.timedOut -or -not $run.parsed) {
              Add-Result $c.id $fx $sc $im $c.op $false '无有效 JSON 输出' $c.note; continue
            }
            $rv = Get-RawValue $run.parsed $c.path
            if (-not $rv.found) { Add-Result $c.id $fx $sc $im $c.op $false "字段不存在: $($c.path)" $c.note; continue }
            $flat = Flatten $rv.values
            $pass = $false; $detail = ''
            switch ($c.op) {
              'is_true'  { $pass = ($flat.Count -eq 1 -and $flat[0] -eq $true); $detail = "值=$($flat -join ',')" }
              'is_false' { $pass = ($flat.Count -eq 1 -and $flat[0] -eq $false); $detail = "值=$($flat -join ',')" }
              'is_null'  { $pass = ($flat.Count -ge 1 -and ($flat | Where-Object { $null -ne $_ }).Count -eq 0); $detail = "值=$($flat -join ',')" }
              'is_empty_array' { $pass = ($flat.Count -eq 0); $detail = "元素数=$($flat.Count)" }
              'is_nonempty_array' { $pass = ($flat.Count -gt 0); $detail = "元素数=$($flat.Count)" }
              'equals' { $pass = ($flat.Count -ge 1 -and ($flat | Where-Object { "$_" -eq [string]$c.value }).Count -gt 0); $detail = "值=$($flat -join ',')" }
              'contains' { $pass = (($flat | Where-Object { "$_" -eq [string]$c.value -or ("$_").Contains([string]$c.value) }).Count -gt 0); $detail = "值=$($flat -join ',')" }
              'not_contains' { $pass = (($flat | Where-Object { "$_" -eq [string]$c.value -or ("$_").Contains([string]$c.value) }).Count -eq 0); $detail = "值=$($flat -join ',')" }
              'matches' { $pass = (($flat | Where-Object { "$_" -match [string]$c.value }).Count -gt 0); $detail = "值=$($flat -join ',')" }
              'count_gte' { $pass = ($flat.Count -ge [int]$c.value); $detail = "元素数=$($flat.Count) 期望>=$($c.value)" }
              'unique_array' {
                $u = @($flat | Select-Object -Unique); $pass = ($u.Count -eq $flat.Count)
                $dup = ($flat | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) -join ','
                $detail = $(if ($pass) { 'ok' } else { "重复项: $dup" })
              }
              default { $detail = "未知 op: $($c.op)" }
            }
            Add-Result $c.id $fx $sc $im $c.op $pass $detail $c.note
          }
        }
      }
    }
  }
}

# ---------- 汇总 ----------
$failed = @($results | Where-Object { -not $_.pass })
$total = $results.Count; $passN = $total - $failed.Count
$summary = [pscustomobject]@{
  when = (Get-Date).ToString('s'); repo = $RepoRoot
  git_sha = (& git -C $RepoRoot rev-parse --short HEAD 2>$null)
  git_dirty = [bool](& git -C $RepoRoot status --porcelain 2>$null)
  bash = $(if ($bashOk) { 'available' } else { 'unavailable' })
  fixtures = $allIds.Count; runs = $runList.Count
  checks_total = $total; checks_passed = $passN; checks_failed = $failed.Count
  failures = @($failed | ForEach-Object { [pscustomobject]@{ id=$_.id; fixture=$_.fixture; script=$_.script; impl=$_.impl; op=$_.op; detail=$_.detail } })
}
if (-not $NoWrite) {
  $resDir = Join-Path $PSScriptRoot 'results'
  New-Item -ItemType Directory -Force -Path $resDir | Out-Null
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
  $file = Join-Path $resDir "$stamp-$($summary.git_sha).json"
  $payload = [pscustomobject]@{ summary = $summary; results = $results }
  $payload | ConvertTo-Json -Depth 8 | Set-Content -Path $file -Encoding UTF8
  Write-Host "results -> $file"
}
if (-not $KeepTemp) { Remove-Item $RunDir -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "run dir kept: $RunDir" }
if ($Json) { $summary | ConvertTo-Json -Depth 6; exit $(if ($failed.Count) { 1 } else { 0 }) }
Write-Host ""
Write-Host ("=" * 68)
Write-Host ("checks: {0} passed / {1} failed / {2} total   (bash: {3})" -f $passN, $failed.Count, $total, $summary.bash)
if ($failed.Count) {
  Write-Host ""; Write-Host "失败项（按 fixture 分组）：" -ForegroundColor Red
  $failed | Group-Object fixture | Sort-Object Name | ForEach-Object {
    Write-Host ("  [{0}]" -f $_.Name) -ForegroundColor Red
    $_.Group | ForEach-Object { Write-Host ("      {0,-34} {1,-6} {2}" -f $_.id, $_.impl, $_.detail) }
  }
}
Write-Host ("=" * 68)
exit $(if ($failed.Count) { 1 } else { 0 })
