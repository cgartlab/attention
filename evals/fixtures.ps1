#Requires -Version 7.0
<#
.SYNOPSIS
  生成 attention 采集脚本的 19 个测试 fixture（F1-F19）。
.DESCRIPTION
  契约见 references/scan-recipes.md；断言表见 evals/script-assertions.json。
  生成目录默认在系统临时目录下的 attention-evals/（可用 -OutDir 覆盖）。
  为什么默认不放在仓库内：F1 是"非 git 目录"负例，若它位于本仓库工作树内，
  git 会向上找到本仓库并报 is_git=true，负例就失效了——这正是被测脚本要避免的坑。
  每个 fixture 都是独立的小 git 仓库（F1 为非 git 目录）。
.EXAMPLE
  pwsh -NoProfile -File evals/fixtures.ps1 -Json
#>
[CmdletBinding()]
param(
  [string]$OutDir,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path ([System.IO.Path]::GetTempPath()) 'attention-evals' }
if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function New-FixtureRepo {
  param([string]$Id)
  $p = Join-Path $OutDir $Id
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  & git -C $p init -q -b main 2>&1 | Out-Null
  & git -C $p config user.email 'dev@example.com' 2>&1 | Out-Null
  & git -C $p config user.name 'Dev Example' 2>&1 | Out-Null
  & git -C $p config commit.gpgsign false 2>&1 | Out-Null
  return $p
}
function New-PlainDir {
  param([string]$Id)
  $p = Join-Path $OutDir $Id
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  return $p
}
function Set-FileContent {
  param([string]$Path, [string]$Content, [switch]$Crlf)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if ($Crlf) {
    $text = ($Content -replace "`r`n", "`n") -replace "`n", "`r`n"
  } else {
    $text = $Content
  }
  [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
}
function Add-Commit {
  param([string]$Repo, [string]$Message, [string]$Body, [string]$Date)
  & git -C $Repo add -A 2>&1 | Out-Null
  $argv = @('-C', $Repo, 'commit', '-q', '-m', $Message)
  if ($Body) { $argv += @('-m', $Body) }
  if ($Date) { $argv += @('--date', $Date) }
  # git commit --date 只设 author date；陈旧分支判定用 committer date（%cI），故必须同时设 GIT_COMMITTER_DATE
  $prevC = $env:GIT_COMMITTER_DATE
  if ($Date) { $env:GIT_COMMITTER_DATE = $Date }
  & git @argv 2>&1 | Out-Null
  if ($Date) { if ($null -ne $prevC) { $env:GIT_COMMITTER_DATE = $prevC } else { Remove-Item Env:\GIT_COMMITTER_DATE -ErrorAction SilentlyContinue } }
}
function Set-FakeRemote {
  param([string]$Repo, [string]$Url, [hashtable]$ExtraRefs)
  & git -C $Repo remote add origin $Url 2>&1 | Out-Null
  $sha = (& git -C $Repo rev-parse HEAD).Trim()
  & git -C $Repo update-ref refs/remotes/origin/main $sha 2>&1 | Out-Null
  & git -C $Repo symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>&1 | Out-Null
  & git -C $Repo config branch.main.remote origin 2>&1 | Out-Null
  & git -C $Repo config branch.main.merge refs/heads/main 2>&1 | Out-Null
  if ($ExtraRefs) {
    foreach ($k in $ExtraRefs.Keys) {
      & git -C $Repo update-ref "refs/remotes/origin/$k" $ExtraRefs[$k] 2>&1 | Out-Null
    }
  }
}

$fixtures = [System.Collections.Generic.List[object]]::new()
function Register-Fixture {
  param([string]$Id, [string]$Label, [string]$Path, [string]$Notes)
  $fixtures.Add([pscustomobject]@{ id = $Id; label = $Label; path = $Path; notes = $Notes })
}

$p = New-PlainDir 'F1-nongit'
Set-FileContent -Path (Join-Path $p 'a.txt') -Content "hello`n"
Register-Fixture 'F1' 'non-git dir' $p 'expect is_git=false'

$p = New-FixtureRepo 'F2-empty'
Register-Fixture 'F2' 'zero-commit repo' $p 'head_short=null; must not crash'

$p = New-FixtureRepo 'F3-detached'
Set-FileContent -Path (Join-Path $p 'a.txt') -Content "x`n"
Add-Commit -Repo $p -Message 'feat: init'
& git -C $p checkout -q --detach HEAD 2>&1 | Out-Null
Register-Fixture 'F3' 'detached HEAD' $p 'detached=true; current_branch=null'

$p = New-FixtureRepo 'F4-hostile'
Set-FileContent -Path (Join-Path $p 'base.txt') -Content "base`n"
Set-FileContent -Path (Join-Path $p 'unicode-file.txt') -Content "u`n"
Set-FileContent -Path (Join-Path $p "it's.txt") -Content "q`n"
Set-FileContent -Path (Join-Path $p 'brace{and}tab.txt') -Content "b`n"
Set-FileContent -Path (Join-Path $p 'deep dir/sub dir/nested.txt') -Content "n`n"
Set-FileContent -Path (Join-Path $p 'gradle.properties') -Content "version = 9.9.9`n" -Crlf
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "hostile", "version": "1.0.0" }'
Add-Commit -Repo $p -Message 'feat: hostile names'
Set-FileContent -Path (Join-Path $p 'unicode-file.txt') -Content "u2`n"
Set-FileContent -Path (Join-Path $p 'deep dir/sub dir/nested.txt') -Content "n2`n"
Set-FileContent -Path (Join-Path $p 'fresh untracked.txt') -Content "// TODO: untracked`n"
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/hostile.git'
Register-Fixture 'F4' 'hostile names + CRLF' $p 'strict JSON; relative forward-slash paths'

$p = New-FixtureRepo 'F5-dirty'
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "calc", "version": "0.3.0", "scripts": { "test": "node test.js", "build": "node build.js" } }'
Set-FileContent -Path (Join-Path $p 'src/math.js') -Content "exports.add=(a,b)=>a+b;`n"
Set-FileContent -Path (Join-Path $p 'src/format.js') -Content "exports.fmt=v=>String(v);`n"
Set-FileContent -Path (Join-Path $p 'test.js') -Content "const m=require('./src/math');if(m.add(2,3)!==5)throw new Error('add broken');console.log('all tests passed');`n"
Set-FileContent -Path (Join-Path $p 'build.js') -Content "console.log('build ok');`n"
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# calc`n`nTiny calculator helpers.`n"
Set-FileContent -Path (Join-Path $p 'CHANGELOG.md') -Content "# Changelog`n`n## [0.3.0] - 2026-07-01`n`n### Added`n- format helper`n"
Set-FileContent -Path (Join-Path $p 'LICENSE') -Content "MIT License`n"
Add-Commit -Repo $p -Message 'feat: calc helpers'
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/calc.git'
Set-FileContent -Path (Join-Path $p 'src/math.js') -Content "exports.add=(a,b)=>a-b;`n"
Set-FileContent -Path (Join-Path $p 'src/format.js') -Content "exports.fmt=v=>String(v);exports.pct=v=>v+'%';`n"
Set-FileContent -Path (Join-Path $p 'src/percent.js') -Content "// TODO: finish percent helpers`nexports.of=(v,p)=>v*p/100;`n"
Register-Fixture 'F5' 'dirty WIP + failing test' $p 'todo_fixme should include untracked TODO'

$p = New-FixtureRepo 'F6-clean-sync'
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# counter`n`nLibrary.`n"
Set-FileContent -Path (Join-Path $p 'src/counter.js') -Content "exports.add=(a,b)=>a+b;`n"
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "counter", "version": "1.0.0" }'
Add-Commit -Repo $p -Message 'feat: initial counter'
& git -C $p checkout -q -b feature/done 2>&1 | Out-Null
Set-FileContent -Path (Join-Path $p 'src/counter.js') -Content "exports.add=(a,b)=>a+b;exports.sub=(a,b)=>a-b;`n"
Add-Commit -Repo $p -Message 'feat(counter): add sub helper'
$mergedSha = (& git -C $p rev-parse HEAD).Trim()
& git -C $p checkout -q main 2>&1 | Out-Null
& git -C $p merge -q --no-ff feature/done -m 'Merge feature/done' 2>&1 | Out-Null
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/counter.git' -ExtraRefs @{ 'feature/done' = $mergedSha }
& git -C $p checkout -q -b feature/old 2>&1 | Out-Null
Set-FileContent -Path (Join-Path $p 'src/legacy.js') -Content "exports.legacy=()=>42;`n"
Add-Commit -Repo $p -Message 'wip: legacy experiment' -Date (Get-Date).AddDays(-91).ToString('yyyy-MM-ddTHH:mm:ss')
& git -C $p checkout -q main 2>&1 | Out-Null
Register-Fixture 'F6' 'clean sync + branches' $p 'unpushed_branches should include feature/old'

$p = New-FixtureRepo 'F7-version-mismatch'
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "rel", "version": "1.1.0" }'
Set-FileContent -Path (Join-Path $p 'Cargo.toml') -Content "[package]`nname = `"rel`"`nversion = `"1.0.0`"`nedition = `"2021`"`n"
Set-FileContent -Path (Join-Path $p 'pyproject.toml') -Content "[tool.poetry]`nname = `"rel`"`nversion = `"1.0.0`"`n"
Set-FileContent -Path (Join-Path $p 'gradle.properties') -Content "version=0.9.0`n" -Crlf
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# rel`n"
Add-Commit -Repo $p -Message 'chore: bootstrap rel'
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/rel.git'
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "rel", "version": "1.1.0", "files": ["src"] }'
Register-Fixture 'F7' 'version mismatch (multi-ecosystem)' $p 'consistent=false; release_signals includes version-file-touched'

$p = New-FixtureRepo 'F8-crlf'
Set-FileContent -Path (Join-Path $p 'gradle.properties') -Content "version = 9.9.9`n" -Crlf
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# crlf`n"
Add-Commit -Repo $p -Message 'feat: crlf repo'
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/crlf.git'
Register-Fixture 'F8' 'CRLF version file' $p 'strict JSON; version must not contain raw CR'

$p = New-FixtureRepo 'F9-depversion'
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "p", "dependencies": { "left-pad": { "version": "1.3.0" } }, "version": "2.0.0" }'
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# p`n"
Add-Commit -Repo $p -Message 'feat: dep order'
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/p.git'
Register-Fixture 'F9' 'dependency version before top-level' $p 'both impls must read top-level 2.0.0'

$p = New-FixtureRepo 'F10-ignored'
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "probe", "version": "1.0.0" }'
Set-FileContent -Path (Join-Path $p 'vendor/sub/Cargo.toml') -Content "[package]`nname=`"vendored`"`nversion=`"3.3.3`"`n"
Set-FileContent -Path (Join-Path $p '.gitignore') -Content "vendor/`n"
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# probe`n"
Add-Commit -Repo $p -Message 'feat: probe with vendor'
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/probe.git'
Register-Fixture 'F10' 'version file inside ignored dir' $p 'version_files must not include vendor/'

$p = New-FixtureRepo 'F11-host'
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "h", "version": "1.0.0" }'
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# h`n"
Add-Commit -Repo $p -Message 'feat: host probe'
Set-FakeRemote -Repo $p -Url 'https://user:ghp_SUPERSECRETTOKEN@127.0.0.1:1/team/github.com-mirror.git'
Register-Fixture 'F11' 'host parsing + token masking' $p 'is_github=false; output must not contain token'

$p = New-FixtureRepo 'F12-signals'
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "sig", "version": "1.0.0" }'
Set-FileContent -Path (Join-Path $p 'src/a.js') -Content "exports.a=1;`n"
Add-Commit -Repo $p -Message 'chore(release): prepare 1.1.0'
Set-FileContent -Path (Join-Path $p 'src/a.js') -Content "exports.a=2;`n"
Add-Commit -Repo $p -Message 'feat!: drop legacy api'
Set-FileContent -Path (Join-Path $p 'src/a.js') -Content "exports.a=3;`n"
Add-Commit -Repo $p -Message 'fix: correct rounding'
Set-FileContent -Path (Join-Path $p 'src/a.js') -Content "exports.a=4;`n"
Add-Commit -Repo $p -Message 'refactor: move config' -Body 'BREAKING CHANGE: config moved to config/'
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/sig.git'
Register-Fixture 'F12' 'release signals' $p 'release_signals should include chore(release)/feat!/fix:/breaking-footer'

$p = New-FixtureRepo 'F13-monorepo'
Set-FileContent -Path (Join-Path $p 'pnpm-workspace.yaml') -Content "packages:`n  - 'packages/*'`n"
Set-FileContent -Path (Join-Path $p 'packages/a/package.json') -Content '{ "name": "@x/a", "version": "1.0.0" }'
Set-FileContent -Path (Join-Path $p 'packages/b/package.json') -Content '{ "name": "@x/b", "version": "1.0.0" }'
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# mono`n"
Add-Commit -Repo $p -Message 'feat: monorepo bootstrap'
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/mono.git'
Register-Fixture 'F13' 'monorepo' $p 'monorepo_mode=true; packages contains two entries'

$p = New-FixtureRepo 'F14-color'
Set-FileContent -Path (Join-Path $p 'a.txt') -Content "base`n"
Add-Commit -Repo $p -Message 'feat: base'
& git -C $p checkout -q -b feature/merged 2>&1 | Out-Null
Set-FileContent -Path (Join-Path $p 'a.txt') -Content "base`nmore`n"
Add-Commit -Repo $p -Message 'feat: merged work'
& git -C $p checkout -q main 2>&1 | Out-Null
& git -C $p merge -q --no-ff feature/merged -m 'merge feature/merged' 2>&1 | Out-Null
& git -C $p config color.ui always 2>&1 | Out-Null
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/color.git'
Register-Fixture 'F14' 'color injection' $p 'local_merged_candidates should include feature/merged'

$p = New-FixtureRepo 'F15-vendor-unignored'
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "vu", "version": "1.0.0" }'
# 关键：vendor 不在 .gitignore 里 —— 只靠 --exclude-standard 挡不住它，必须靠硬编码路径段排除
Set-FileContent -Path (Join-Path $p 'vendor/sub/Cargo.toml') -Content "[package]`nname=`"vendored`"`nversion=`"9.9.9`"`n"
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# vu`n"
Add-Commit -Repo $p -Message 'feat: vendored tree not ignored'
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/vu.git'
Register-Fixture 'F15' 'vendor/ NOT ignored' $p 'vendor/sub/Cargo.toml is tracked; hardcoded exclusion must still drop it'

$p = New-FixtureRepo 'F16-cargo-workspace'
Set-FileContent -Path (Join-Path $p 'Cargo.toml') -Content "[workspace]`nmembers = [`"packages/a`", `"packages/b`"]`n`n[workspace.package]`nversion = `"2.0.0`"`nedition = `"2021`"`n"
# 成员两种写法都要识别：点号键 与 内联表
Set-FileContent -Path (Join-Path $p 'packages/a/Cargo.toml') -Content "[package]`nname = `"a`"`nversion.workspace = true`nedition.workspace = true`n"
Set-FileContent -Path (Join-Path $p 'packages/b/Cargo.toml') -Content "[package]`nname = `"b`"`nversion = { workspace = true }`nedition.workspace = true`n"
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# ws`n"
Add-Commit -Repo $p -Message 'feat: cargo workspace'
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/ws.git'
Register-Fixture 'F16' 'cargo workspace inheritance' $p 'inherited_version_files>=2; packages=[packages/a,packages/b]; member versions must NOT enter version_files'

$p = New-FixtureRepo 'F17-protect-config'
Set-FileContent -Path (Join-Path $p 'package.json') -Content '{ "name": "pc", "version": "1.0.0" }'
Set-FileContent -Path (Join-Path $p 'README.md') -Content "# pc`n"
Add-Commit -Repo $p -Message 'feat: protect config'
# 三个值：--get-all 全回；--get 只回最后一个（zeta/*）。若实现误用 --get，
# hotfix/* 会消失（release/* 会因内置字面量而假通过），故 hotfix/* 是关键判别项。
& git -C $p config --add cleanup.protect 'release/*' 2>&1 | Out-Null
& git -C $p config --add cleanup.protect 'hotfix/*' 2>&1 | Out-Null
& git -C $p config --add cleanup.protect 'zeta/*' 2>&1 | Out-Null
Set-FakeRemote -Repo $p -Url 'https://127.0.0.1:1/github.com/team/pc.git'
Register-Fixture 'F17' 'cleanup.protect multi-value' $p 'protected must contain every --get-all value'

$p = New-FixtureRepo 'F18-merge-base-split'
Set-FileContent -Path (Join-Path $p 'a.txt') -Content "base`n"
Add-Commit -Repo $p -Message 'feat: base'
$baseSha = (& git -C $p rev-parse HEAD).Trim()
& git -C $p checkout -q -b feature 2>&1 | Out-Null
Set-FileContent -Path (Join-Path $p 'a.txt') -Content "base`nfeature`n"
Add-Commit -Repo $p -Message 'feat: feature work'
$featSha = (& git -C $p rev-parse HEAD).Trim()
& git -C $p checkout -q main 2>&1 | Out-Null
& git -C $p merge -q --no-ff feature -m 'merge feature' 2>&1 | Out-Null
# 伪造一个"落后"的 origin/main：本地已合并 feature，远程还停在合并前
& git -C $p remote add origin 'https://127.0.0.1:1/github.com/team/split.git' 2>&1 | Out-Null
& git -C $p update-ref refs/remotes/origin/main $baseSha 2>&1 | Out-Null
& git -C $p update-ref refs/remotes/origin/feature $featSha 2>&1 | Out-Null
& git -C $p symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>&1 | Out-Null
Register-Fixture 'F18' 'local main merged, origin/main stale' $p 'local base=main (feature merged); remote base=origin/main (feature NOT merged)'

$p = New-FixtureRepo 'F19-base-unverified'
Set-FileContent -Path (Join-Path $p 'a.txt') -Content "base`n"
Add-Commit -Repo $p -Message 'feat: base'
# 有 remote，但没有 refs/remotes/origin/<default> —— 远程基准无从验证
& git -C $p remote add origin 'https://127.0.0.1:1/github.com/team/nobase.git' 2>&1 | Out-Null
Register-Fixture 'F19' 'remote without origin/<default>' $p 'remote_base_unverified=true + remote-base-unverified warning'

$summary = [pscustomobject]@{
  out_dir  = $OutDir
  count    = $fixtures.Count
  fixtures = $fixtures
}
if ($Json) {
  $summary | ConvertTo-Json -Depth 6
} else {
  "fixtures: $($fixtures.Count) -> $OutDir"
  foreach ($f in $fixtures) { "  [{0}] {1,-36} {2}" -f $f.id, $f.label, $f.path }
}
