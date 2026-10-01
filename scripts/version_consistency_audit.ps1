#requires -Version 7.0
<#
.SYNOPSIS
  Audit version-bearing files for consistency and collect release signals (read-only).
.DESCRIPTION
  Read-only: prints one JSON object on stdout (contract: references/scan-recipes.md §3).
  Detects version files across ecosystems, reads their versions, reports consistency and
  the release signals observed. It does NOT decide whether a version bump is mandatory --
  that is the model's job (see references/judgment-criteria.md).
  --repo must exist and be a directory; otherwise the script prints
  {"is_git":false,"error":"repo path not found"} and exits 0.
.PARAMETER repo
  Repository path (default: current directory).
.PARAMETER defaultBranch
  Override the auto-detected default branch.
.PARAMETER targetVersion
  The version the caller intends to release (echoed back; null when not given).
.PARAMETER sinceTag
  Start of the commit range scanned for release signals.
.EXAMPLE
  pwsh -NoProfile -File scripts/version_consistency_audit.ps1 --repo D:\code\myproj
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
function Clean-Val([string]$s) {
  if ($null -eq $s) { return $null }
  $s = ($s -replace '\r$','').Trim()
  if ($s.Length -ge 2) {
    $f = $s.Substring(0,1); $l = $s.Substring($s.Length - 1,1)
    if (($f -eq '"' -and $l -eq '"') -or ($f -eq "'" -and $l -eq "'")) { $s = $s.Substring(1, $s.Length - 2) }
  }
  return $s
}
function Get-FirstLine([string]$file, [string]$re) {
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  foreach ($l in @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)) {
    if ([string]$l -cmatch $re) { return ([string]$l -replace '\r$','') }
  }
  return $null
}
function Grab-Q([string]$file, [string]$re) {
  $line = Get-FirstLine $file $re
  if (-not $line) { return $null }
  $m = [regex]::Match($line, '^[^"'']*["'']([^"'']*)["'']')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}
function Grab-AfterEq([string]$file, [string]$re) {
  $line = Get-FirstLine $file $re
  if (-not $line) { return $null }
  return (Clean-Val ($line -replace '^[^=]*=',''))
}
function Grab-AfterColon([string]$file, [string]$re) {
  $line = Get-FirstLine $file $re
  if (-not $line) { return $null }
  return (Clean-Val ($line -replace '^[^:]*:',''))
}
function Grab-Xml([string]$file, [string]$tag) {
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  $t = Get-Content -Raw -LiteralPath $file -ErrorAction SilentlyContinue
  if (-not $t) { return $null }
  $m = [regex]::Match($t, "<$tag>([^<]*)</$tag>")
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}
function Get-JsonValue([string]$file, [string]$path) {
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  try { $j = Get-Content -Raw -LiteralPath $file | ConvertFrom-Json } catch { return $null }
  $cur = $j
  foreach ($seg in $path.Split('.')) {
    if ($null -eq $cur) { return $null }
    $p = $cur.PSObject.Properties[$seg]
    if (-not $p) { return $null }
    $cur = $p.Value
  }
  if ($null -eq $cur) { return $null }
  return [string]$cur
}
function Get-LockRootVersion([string]$file) {
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  try { $j = Get-Content -Raw -LiteralPath $file | ConvertFrom-Json } catch { return $null }
  $p0 = $j.PSObject.Properties['packages']
  if (-not $p0) { return $null }
  $inner = $p0.Value.PSObject.Properties['']
  if (-not $inner) { return $null }
  $p = $inner.Value.PSObject.Properties['version']
  if (-not $p) { return $null }
  return [string]$p.Value
}
function Get-CargoLockVersion([string]$rootName, [string]$file) {
  if (-not $rootName) { return $null }
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  $name = $null; $ver = $null
  foreach ($line0 in @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)) {
    $line = [string]$line0
    if ($line -cmatch '^\[\[package\]\]') {
      if ($name -eq $rootName -and $ver) { return $ver }
      $name = $null; $ver = $null; continue
    }
    if (-not $name -and $line -cmatch '^[ \t]*name[ \t]*=') { $name = Clean-Val ($line -replace '^[^=]*=','') }
    if (-not $ver -and $line -cmatch '^[ \t]*version[ \t]*=') { $ver = Clean-Val ($line -replace '^[^=]*=','') }
  }
  if ($name -eq $rootName -and $ver) { return $ver }
  return $null
}
# SKILL.md（Agent Skill 仓库）：技能版本号写在 YAML frontmatter 里。
# 只为这一处做**最简单的** YAML 解析（不引 YAML 库）：文件必须以 `---` 开头/结束，
# 取「顶层 `metadata:` 块内、恰好缩进两格的 `version:`」，没有则回退顶层的 `version:`；
# 值去首尾空白、去成对引号。为什么必须识别：Skill 仓库的真正版本号就在这里，不进清单
# 会让 version_files=[] 且 consistent=null —— 等于巡不到自己的版本（实测本仓库即如此）。
function Get-SkillFrontmatterVersion([string]$file) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
  $lines = @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)
  if ($lines.Count -lt 1) { return $null }
  if (([string]$lines[0]).TrimEnd("`r") -notmatch '^---\s*$') { return $null }
  $top = $null; $yamlMeta = $null; $inMeta = $false
  for ($i = 1; $i -lt $lines.Count; $i++) {
    $line = ([string]$lines[$i]).TrimEnd("`r")
    if ($line -match '^---\s*$') { break }
    if ($line -match '^\s*$') { continue }
    if ($line -match '^\s*#') { continue }
    # 顶层键（无缩进）：metadata: 开启块；顶层 version: 作回退值
    if ($line -match '^\S') {
      $inMeta = $false
      if ($line -match '^metadata:\s*$') { $inMeta = $true; continue }
      if ($line -match '^version\s*:(.*)$') { $top = Clean-Val $Matches[1] }
      continue
    }
    # 恰好两格缩进的键（三格及以上视为更深层级，忽略）
    if ($line -match '^  [^\s]') {
      if ($inMeta -and $line -match '^  version\s*:(.*)$') { $yamlMeta = Clean-Val $Matches[1] }
      continue
    }
  }
  if ($yamlMeta) { return $yamlMeta }
  if ($top) { return $top }
  return $null
}
function Test-SegExcluded([string]$p) {
  $s = "/$p/"
  # vendor/third_party/Pods/bower_components 必须在表里：第三方内嵌依赖常未被 .gitignore
  # 排除，实测 vendor/sub/Cargo.toml 会被收进来、当成自有版本文件，报假"不一致"。
  foreach ($seg in 'node_modules','.git','target','dist','build','.venv','venv','__pycache__','obj','bin','vendor','third_party','Pods','bower_components') {
    if ($s -clike "*/$seg/*") { return $true }
  }
  return $false
}
# Cargo.toml 的 [workspace].members 列表（支持多行数组，含 `packages/*` 通配）
function Get-CargoMembers([string]$file) {
  $out = @()
  $inArr = $false
  foreach ($line0 in @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)) {
    $line = [string]$line0
    if (-not $inArr) {
      if ($line -cnotmatch '^[ \t]*members[ \t]*=') { continue }
      $i = $line.IndexOf('[')
      if ($i -lt 0) { continue }
      $inArr = $true
      $line = $line.Substring($i + 1)
    }
    foreach ($m in [regex]::Matches($line, '"([^"]*)"')) { $out += $m.Groups[1].Value }
    if ($line.Contains(']')) { break }
  }
  return ,$out
}
# 成员写 `version.workspace = true` 或 `version = { workspace = true }` 时没有字面版本
function Test-CargoInheritsVersion([string]$file) {
  if (Get-FirstLine $file '^[ \t]*version[ \t]*\.[ \t]*workspace[ \t]*=[ \t]*true') { return $true }
  if (Get-FirstLine $file '^[ \t]*version[ \t]*=[ \t]*\{[^}]*workspace[ \t]*=[ \t]*true') { return $true }
  return $false
}
# 展开 workspace members：`packages/*` 之类通配按实际含 Cargo.toml 的目录展开
function Expand-Member([string]$rootDir, [string]$pat) {
  $out = @()
  if (-not $pat) { return ,$out }
  if ($pat.StartsWith('!')) { return ,$out }
  if ($rootDir -eq '.') { $base = "./$pat" } else { $base = "$rootDir/$pat" }
  # Resolve-Path 在 pwsh 7 里回的是绝对路径，故这里显式归一为相对仓库根（与 .sh 一致）
  $cwd = ((Get-Location).Path -replace '\\','/')
  if ($cwd.EndsWith('/')) { $cwd = $cwd.Substring(0, $cwd.Length - 1) }
  foreach ($r in @(Resolve-Path -Path $base -ErrorAction SilentlyContinue)) {
    $it = Get-Item -LiteralPath $r.Path -ErrorAction SilentlyContinue
    if (-not $it -or -not $it.PSIsContainer) { continue }
    $rel = ($r.Path -replace '\\','/')
    if ($rel.StartsWith($cwd + '/')) { $rel = $rel.Substring($cwd.Length + 1) }
    if ($rel.StartsWith('./')) { $rel = $rel.Substring(2) }
    if (Test-Path -LiteralPath "$rel/Cargo.toml") { $out += $rel }
  }
  return ,$out
}

# ---------- 入参 ----------
$RepoArg = $null; $HaveRepoArg = $false; $DefaultArg = $null; $TargetArg = $null; $SinceArg = $null; $Help = $false
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
  $a = [string]$argv[$i]
  if ($a -eq '--repo') { if ($i + 1 -lt $argv.Count) { $RepoArg = [string]$argv[$i + 1]; $i++ } else { $HaveRepoArg = $true } }
  elseif ($a -eq '--defaultBranch') { if ($i + 1 -lt $argv.Count) { $DefaultArg = [string]$argv[$i + 1]; $i++ } }
  elseif ($a -eq '--target-version') { if ($i + 1 -lt $argv.Count) { $TargetArg = [string]$argv[$i + 1]; $i++ } }
  elseif ($a -eq '--since-tag') { if ($i + 1 -lt $argv.Count) { $SinceArg = [string]$argv[$i + 1]; $i++ } }
  elseif ($a -eq '--help' -or $a -eq '-h') { $Help = $true }
}

if ($Help) {
  Write-Host "Usage: pwsh -NoProfile -File version_consistency_audit.ps1 [--repo <path>] [--defaultBranch <name>]"
  Write-Host "                                                   [--target-version <x.y.z>] [--since-tag <tag>] [--help]"
  Write-Host ""
  Write-Host "Read-only: detect version files across ecosystems, read their versions, report"
  Write-Host "consistency, and collect release signals. Prints one JSON object. Never edits files."
  Write-Host ""
  Write-Host "  --repo <path>            Repository path (default: current directory). Must exist and"
  Write-Host "                           be a directory, otherwise prints"
  Write-Host "                           {""is_git"":false,""error"":""repo path not found""} and exits 0."
  Write-Host "  --defaultBranch <name>   Override the auto-detected default branch."
  Write-Host "  --target-version <x.y.z> The version the caller intends to release (echoed back; null"
  Write-Host "                           when not given). The script never guesses user intent."
  Write-Host "  --since-tag <tag>        Start of the commit range scanned for release signals"
  Write-Host "                           (default: git describe --tags --abbrev=0, i.e. all commits"
  Write-Host "                           when no tag exists)."
  Write-Host "  --help, -h               Print this usage and exit 0."
  Write-Host ""
  Write-Host "Fields: is_git, version_files, inherited_version_files, distinct_versions, consistent,"
  Write-Host "go_mod_present, monorepo_mode, packages, target_version, release_signals, release_involved,"
  Write-Host "changed_files, warnings."
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

# ---- 文件池：git ls-files ∪ git ls-files --others --exclude-standard（尊重 .gitignore）----
$pool = @()
$pool += GitZ @('ls-files','-z')
$pool += GitZ @('ls-files','--others','--exclude-standard','-z')
$pool = UniqSort ($pool | ForEach-Object { ToPosix $_ })

$cand = @()
foreach ($f in $pool) {
  if (Test-SegExcluded $f) { continue }
  $base = $f
  $slash = $f.LastIndexOf('/')
  if ($slash -ge 0) { $base = $f.Substring($slash + 1) }
  $keep = $false
  if ($base -cin @('package.json','package-lock.json','npm-shrinkwrap.json','Cargo.toml','Cargo.lock','pyproject.toml','setup.py','setup.cfg','pom.xml','gradle.properties','build.gradle','build.gradle.kts','Directory.Build.props','composer.json','pubspec.yaml','mix.exs','MODULE.bazel','DESCRIPTION','Chart.yaml','Package.swift','go.mod','SKILL.md')) { $keep = $true }
  elseif ($base -clike '*.csproj' -or $base -clike '*.gemspec' -or $base -clike '*.opam') { $keep = $true }
  elseif ($f -clike 'lib/*version.rb') { $keep = $true }
  if ($keep) { $cand += $f }
}
$cand = UniqSort $cand

# ---------- Cargo workspace 预扫描 ----------
# 预先建立：workspace 根清单集合、成员目录 -> 根清单映射（继承与 packages 都要用）
$wsRoots = @()
$memberOwner = @()
foreach ($f in @($cand | Where-Object { ($_ -split '/')[-1] -ceq 'Cargo.toml' })) {
  $txt = Get-Content -Raw -LiteralPath $f -ErrorAction SilentlyContinue
  if (-not ($txt -cmatch '(?m)^\[workspace\]')) { continue }
  $wsRoots += $f
  $slash = $f.LastIndexOf('/')
  $d = if ($slash -ge 0) { $f.Substring(0, $slash) } else { '.' }
  # 注意：下面这两个函数用 `return ,$out` 返回数组，调用处**不能**再套 @()，
  # 否则会变成「只含一个数组元素」的嵌套数组（实测踩过）。
  foreach ($m in (Get-CargoMembers $f)) {
    foreach ($md in (Expand-Member $d $m)) { $memberOwner += [pscustomobject]@{ dir = $md; root = $f } }
  }
}
# 兜底 provider：路径最浅的 [workspace] 清单（成员模式没命中该成员目录时用）
$fallbackRoot = $null
$bestDepth = -1
foreach ($r in $wsRoots) {
  $depth = 0
  foreach ($ch in $r.ToCharArray()) { if ($ch -eq '/') { $depth++ } }
  if ($null -eq $fallbackRoot -or $depth -lt $bestDepth -or ($depth -eq $bestDepth -and ([string]::CompareOrdinal($r, $fallbackRoot) -lt 0))) {
    $fallbackRoot = $r; $bestDepth = $depth
  }
}

$versionFiles = @()
$versions = @()
$goPresent = $false; $pkgCount = 0; $pyCount = 0; $cargoWs = $false
$pkgDirs = @()
$inheritedPaths = @()
function Add-VF([string]$file, [string]$eco, [string]$v) {
  if ($null -eq $v) { return }
  $v = ([string]$v).TrimEnd("`r")
  if ($v -eq '') { return }
  $script:versionFiles += [pscustomobject]@{ file = $file; ecosystem = $eco; version = $v }
  $script:versions += $v
}

foreach ($f in $cand) {
  $base = $f
  $slash = $f.LastIndexOf('/')
  if ($slash -ge 0) { $base = $f.Substring($slash + 1) }
  switch -CaseSensitive ($base) {
    'package.json' {
      $script:pkgCount++
      if ($slash -ge 0) { $script:pkgDirs += $f.Substring(0, $slash) }
      Add-VF $f 'node' (Get-JsonValue $f 'version')
    }
    'package-lock.json' {
      $v = Get-JsonValue $f 'version'
      if (-not $v) { $v = Get-LockRootVersion $f }
      Add-VF $f 'node-lock' $v
    }
    'npm-shrinkwrap.json' {
      $v = Get-JsonValue $f 'version'
      if (-not $v) { $v = Get-LockRootVersion $f }
      Add-VF $f 'node-lock' $v
    }
    'Cargo.toml' {
      $txt = Get-Content -Raw -LiteralPath $f -ErrorAction SilentlyContinue
      if ($txt -cmatch '(?m)^\[workspace\]') { $script:cargoWs = $true }
      if (Test-CargoInheritsVersion $f) {
        # 继承版本：进 inherited_version_files，**不计入** version_files/distinct_versions
        #（否则会凭空多出一个空版本，且成员版本来源不可见）
        $script:inheritedPaths += $f
      } else {
        Add-VF $f 'rust' (Grab-Q $f '^[ \t]*version[ \t]*=[ \t]*')
      }
    }
    'Cargo.lock' {
      $rn = $null
      if (Test-Path -LiteralPath 'Cargo.toml') { $rn = Grab-Q 'Cargo.toml' '^[ \t]*name[ \t]*=[ \t]*' }
      Add-VF $f 'rust-lock' (Get-CargoLockVersion $rn $f)
    }
    'pyproject.toml' {
      $script:pyCount++
      if ($slash -ge 0) { $script:pkgDirs += $f.Substring(0, $slash) }
      Add-VF $f 'python' (Grab-Q $f '^[ \t]*version[ \t]*=[ \t]*')
    }
    'setup.py' { Add-VF $f 'python' (Grab-Q $f 'version[ \t]*=[ \t]*') }
    'setup.cfg' { Add-VF $f 'python' (Grab-AfterEq $f '^[ \t]*version[ \t]*=') }
    'pom.xml' { Add-VF $f 'jvm' (Grab-Xml $f 'version') }
    'gradle.properties' { Add-VF $f 'jvm' (Grab-AfterEq $f '^[ \t]*version[ \t]*=') }
    'build.gradle' { Add-VF $f 'jvm' (Grab-Q $f 'version[ \t]*=[ \t]*') }
    'build.gradle.kts' { Add-VF $f 'jvm' (Grab-Q $f 'version[ \t]*=[ \t]*') }
    'Directory.Build.props' {
      $v = Grab-Xml $f 'Version'; if (-not $v) { $v = Grab-Xml $f 'VersionPrefix' }
      Add-VF $f 'dotnet' $v
    }
    'composer.json' { Add-VF $f 'php' (Get-JsonValue $f 'version') }
    'pubspec.yaml' { Add-VF $f 'dart' (Grab-AfterColon $f '^[ \t]*version[ \t]*:') }
    'mix.exs' { Add-VF $f 'elixir' (Grab-Q $f '^[ \t]*version[ \t]*:') }
    'MODULE.bazel' { Add-VF $f 'bazel' (Grab-Q $f 'version[ \t]*=[ \t]*') }
    'DESCRIPTION' { Add-VF $f 'r' (Grab-AfterColon $f '^Version[ \t]*:') }
    'Chart.yaml' { Add-VF $f 'helm' (Grab-AfterColon $f '^[ \t]*version[ \t]*:') }
    'Package.swift' { Add-VF $f 'swift' (Grab-Q $f 'version[ \t]*=[ \t]*') }
    'SKILL.md' { Add-VF $f 'agent-skill' (Get-SkillFrontmatterVersion $f) }
    'go.mod' { $script:goPresent = $true }
    default {
      if ($base -clike '*.csproj') {
        $v = Grab-Xml $f 'Version'; if (-not $v) { $v = Grab-Xml $f 'VersionPrefix' }
        Add-VF $f 'dotnet' $v
      } elseif ($base -clike '*.gemspec') { Add-VF $f 'ruby' (Grab-Q $f '\.version[ \t]*=[ \t]*') }
      elseif ($base -clike '*.opam') { Add-VF $f 'ocaml' (Grab-Q $f '^[ \t]*version[ \t]*:') }
      elseif ($f -clike 'lib/*version.rb') { Add-VF $f 'ruby' (Grab-Q $f '[Vv][Ee][Rr][Ss][Ii][Oo][Nn][ \t]*=') }
    }
  }
}

$vfCount = $versionFiles.Count
$distinct = UniqSort $versions

# ---------- Cargo workspace 继承（inherits_from = 提供版本的根清单）----------
$inherited = @()
foreach ($mf in $inheritedPaths) {
  $slash = $mf.LastIndexOf('/')
  $mdir = if ($slash -ge 0) { $mf.Substring(0, $slash) } else { '.' }
  $prov = $null
  foreach ($mo in $memberOwner) { if ($mo.dir -ceq $mdir) { $prov = $mo.root; break } }
  if (-not $prov) { $prov = $fallbackRoot }
  $inherited += [pscustomobject]@{ file = $mf; inherits_from = $prov }
}

# 版本文件数为 0 -> consistent=null（空集"一致"是空洞真值）+ no-version-files 警告
$consistent = $true
if ($vfCount -eq 0) { $consistent = $null; Add-Warn 'no-version-files' }
elseif ($distinct.Count -gt 1) { $consistent = $false }

# ---- monorepo 检测 ----
$monorepo = $false
if ($pkgCount -gt 1) { $monorepo = $true }
if ($pyCount -gt 1) { $monorepo = $true }
if ($cargoWs) { $monorepo = $true }
foreach ($m in 'pnpm-workspace.yaml','lerna.json','nx.json') { if (Test-Path -LiteralPath $m) { $monorepo = $true } }
$packages = UniqSort (@($pkgDirs) + @($memberOwner | ForEach-Object { $_.dir }))

# ---- 发布信号 ----
$range = 'HEAD'
if ($SinceArg) {
  if (GitOk @('rev-parse','--verify','--quiet',"$SinceArg^{commit}")) { $range = "$SinceArg..HEAD" }
  else { Add-Warn 'since-tag-not-found' }
} else {
  $tag = Git1 @('describe','--tags','--abbrev=0')
  if ($tag) { $range = "$tag..HEAD" }
}
$commits = @(GitOut @('log','--format=%h %s',$range) | Where-Object { $_ -ne '' })
function First-Commit([string]$re) {
  foreach ($c in $commits) { if ([string]$c -cmatch $re) { return [string]$c } }
  return $null
}

$signals = @()
function Add-Sig([string]$kind, [string]$sample) {
  if (-not $kind) { return }
  $script:signals += [pscustomobject]@{ kind = $kind; sample = $sample }
}

$touched = $null
foreach ($fp in @($versionFiles | ForEach-Object { $_.file })) {
  if ($changedSet.Contains($fp)) { $touched = $fp; break }
}
if ($touched) { Add-Sig 'version-file-touched' $touched }

$l = First-Commit '^[0-9a-f]+ (chore\(release\)|chore: *release)'; if ($l) { Add-Sig 'commit-chore-release' $l }
$l = First-Commit '^[0-9a-f]+ (feat|fix)!';                        if ($l) { Add-Sig 'commit-breaking' $l }
$l = First-Commit '^[0-9a-f]+ feat(\(|: )';                        if ($l) { Add-Sig 'commit-feat' $l }
$l = First-Commit '^[0-9a-f]+ fix(\(|: )';                         if ($l) { Add-Sig 'commit-fix' $l }

$footer = $null; $cur = $null; $n = 0
foreach ($line0 in @(GitOut @('log','--format=%h%x09%s%x09%B',$range))) {
  $line = [string]$line0
  $parts = $line -split "`t"
  if ($parts.Count -ge 3) { $cur = $parts[0] + ' ' + $parts[1]; $n = 0; continue }
  if ($n -le 20) { if ($line -cmatch 'BREAKING[- ]CHANGE:') { $footer = $cur; break }; $n++ }
}
if ($footer) { Add-Sig 'breaking-footer' $footer }

$result = [ordered]@{
  is_git            = $true
  version_files     = @($versionFiles)
  inherited_version_files = @($inherited)
  distinct_versions = $distinct
  consistent        = $consistent
  go_mod_present    = $goPresent
  monorepo_mode     = $monorepo
  packages          = $packages
  target_version    = $(if ($TargetArg) { $TargetArg } else { $null })
  release_signals   = @($signals)
  release_involved  = [bool]$touched
  changed_files     = $changed
  warnings          = @($warns)
}
Write-Output (ConvertTo-Json -Depth 8 $result)
