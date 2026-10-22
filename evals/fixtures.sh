#!/usr/bin/env bash
# evals/fixtures.sh —— attention 采集脚本测试 fixture 生成器（bash 侧）
#
# 契约见 references/scan-recipes.md；断言表见 evals/script-assertions.json。
# 生成目录默认在系统临时目录下的 attention-evals/（可用 --out-dir 覆盖）。
# 为什么默认不放在仓库内：F1 是「非 git 目录」负例，若它位于本仓库工作树内，
# git 会向上找到本仓库并报 is_git=true，负例就失效了——这正是被测脚本要避免的坑。
# 每个 fixture 都是独立的小 git 仓库（F1 为非 git 目录）。
#
# 用法：
#   bash evals/fixtures.sh [--out-dir <path>] [--json]
#
# 与 fixtures.ps1 的差异（仅以下三条，其余逐条对齐 ID/目录名/文件内容/git 状态）：
#   1. 拒绝把 --out-dir 指到文件系统根或 . / ..（.ps1 会无条件 Remove-Item -Recurse 掉它）。
#   2. out_dir / path 在 MSYS/Cygwin（有 cygpath）下输出 Windows 形式，与 fixtures.ps1
#      的文本一致；其他平台原样输出 POSIX 路径。
#   3. 用 trap 清理本次的临时文件（.ps1 无临时文件）。
set -u

PROG=${0##*/}
die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit 2; }

usage() {
  cat <<'USAGE'
用法: bash evals/fixtures.sh [--out-dir <path>] [--json]

  --out-dir <path>  生成目录（默认: <系统临时目录>/attention-evals）
  --json            以 JSON 打印摘要 {out_dir,count,fixtures:[{id,label,path,notes}]}
  -h, --help        显示本帮助

生成的 21 个 fixture（F1-F21）与 evals/fixtures.ps1 完全一致。
USAGE
}

OUT_DIR=''
JSON_MODE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir)
      [ $# -ge 2 ] || die "--out-dir 缺少参数值"
      OUT_DIR=$2
      shift 2
      ;;
    --out-dir=*)
      OUT_DIR=${1#--out-dir=}
      shift
      ;;
    --json)
      JSON_MODE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数: $1（用 --help 查看用法）"
      ;;
  esac
done

# ============ 路径工具 ============
# 内部一律用 POSIX 路径做文件操作；输出时再转成平台原生形式（对齐 .ps1 的文本）。
win_to_posix() {
  case "$1" in
    [A-Za-z]:[\\/]*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -u -- "$1"
      else
        _d=$(printf '%s' "$1" | cut -c1 | tr '[:upper:]' '[:lower:]')
        _r=${1:2}
        _r=${_r//\\//}
        printf '/%s%s' "$_d" "$_r"
      fi
      ;;
    *) printf '%s' "$1" ;;
  esac
}
posix_to_native() {
  if command -v cygpath >/dev/null 2>&1; then
    _n=$(cygpath -w -- "$1" 2>/dev/null) && [ -n "$_n" ] && { printf '%s' "$_n"; return 0; }
  fi
  printf '%s' "$1"
}

if [ -z "$OUT_DIR" ]; then
  OUT_DIR=${TMPDIR:-}
  [ -n "$OUT_DIR" ] || OUT_DIR=${TEMP:-}
  [ -n "$OUT_DIR" ] || OUT_DIR=${TMP:-}
  [ -n "$OUT_DIR" ] || OUT_DIR=/tmp
  OUT_DIR=$OUT_DIR/attention-evals
fi
OUT_DIR=$(win_to_posix "$OUT_DIR")
case "$OUT_DIR" in
  ''|/|.|..|./|../|[A-Za-z]:|[A-Za-z]:/|[A-Za-z]:\\)
    die "拒绝把 --out-dir 指到文件系统根或当前目录: '$OUT_DIR'"
    ;;
esac

if [ -e "$OUT_DIR" ] || [ -L "$OUT_DIR" ]; then
  rm -rf -- "$OUT_DIR" || die "无法清理旧目录: $OUT_DIR"
fi
mkdir -p -- "$OUT_DIR" || die "无法创建目录: $OUT_DIR"

# ============ 临时文件清理 ============
TMP_JSON=''
# shellcheck disable=SC2329  # 由 trap 调用
cleanup() {
  if [ -n "$TMP_JSON" ] && [ -e "$TMP_JSON" ]; then rm -f -- "$TMP_JSON"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# ============ 写文件工具 ============
# write_file <path> <内容>：内容原样写入（不额外补换行，与 .ps1 WriteAllText 一致）；
# 下面多行单引号字符串里，行尾的换行本身就是文件内容的一部分（对应 .ps1 的 `n）。
write_file() {
  _dir=$(dirname -- "$1")
  [ -d "$_dir" ] || mkdir -p -- "$_dir" || die "无法创建目录: $_dir"
  printf '%s' "$2" > "$1" || die "无法写入: $1"
}
# write_file_crlf <path> <内容>：对应 .ps1 的 -Crlf（\n -> \r\n）
write_file_crlf() {
  _dir=$(dirname -- "$1")
  [ -d "$_dir" ] || mkdir -p -- "$_dir" || die "无法创建目录: $_dir"
  printf '%s' "$2" | while IFS= read -r _line; do printf '%s\r\n' "$_line"; done > "$1" \
    || die "无法写入: $1"
}

# ============ git 工具 ============
mk_plain_dir() { mkdir -p -- "$1" || die "无法创建目录: $1"; }

init_repo() {
  mkdir -p -- "$1" || die "无法创建目录: $1"
  # git 是原生程序：在关掉了 MSYS 路径转换的环境（例如 MSYS2_ARG_CONV_EXCL=*）里，传 POSIX 路径
  # 会让它直接 'cannot change to'。这类失败绝不能吞——否则 fixture 悄悄退化成"非 git 目录"，
  # 回归会报一屏"字段不存在"（实测 152 条假失败），把"生成失败"伪装成"断言失败"。
  local _err
  _err=$(git -C "$1" init -q -b main 2>&1) || die "git init 失败（$1）: $_err"
  git -C "$1" config user.email 'dev@example.com' >/dev/null 2>&1
  git -C "$1" config user.name 'Dev Example' >/dev/null 2>&1
  git -C "$1" config commit.gpgsign false >/dev/null 2>&1
}

add_commit() { # <repo> <message> [body] [date]
  local repo=$1 msg=$2 body=${3:-} date_arg=${4:-} _err
  git -C "$repo" add -A >/dev/null 2>&1 || die "git add 失败（$repo）"
  # git commit --date 只设 author date；陈旧分支判定看的是 committer date（%cI），
  # 所以传了 date 时必须同时设 GIT_COMMITTER_DATE。.ps1 用 set/restore 环境变量，
  # 这里用「命令前置变量」，效果等价且不会泄漏到其它 git 调用。
  # 提交失败同样是"静默毁 fixture"的高危点（空仓库照样 exit 0），故一并炸出来。
  if [ -n "$body" ] && [ -n "$date_arg" ]; then
    _err=$(GIT_COMMITTER_DATE="$date_arg" git -C "$repo" commit -q -m "$msg" -m "$body" --date "$date_arg" 2>&1) \
      || die "git commit 失败（$repo）: $msg -- $_err"
  elif [ -n "$body" ]; then
    _err=$(git -C "$repo" commit -q -m "$msg" -m "$body" 2>&1) \
      || die "git commit 失败（$repo）: $msg -- $_err"
  elif [ -n "$date_arg" ]; then
    _err=$(GIT_COMMITTER_DATE="$date_arg" git -C "$repo" commit -q -m "$msg" --date "$date_arg" 2>&1) \
      || die "git commit 失败（$repo）: $msg -- $_err"
  else
    _err=$(git -C "$repo" commit -q -m "$msg" 2>&1) \
      || die "git commit 失败（$repo）: $msg -- $_err"
  fi
}

set_fake_remote() { # <repo> <url> [<branch>=<sha> ...]
  local repo=$1 url=$2 sha kv
  shift 2
  git -C "$repo" remote add origin "$url" >/dev/null 2>&1
  sha=$(git -C "$repo" rev-parse HEAD 2>/dev/null | tr -d '\r\n')
  git -C "$repo" update-ref refs/remotes/origin/main "$sha" >/dev/null 2>&1
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main >/dev/null 2>&1
  git -C "$repo" config branch.main.remote origin >/dev/null 2>&1
  git -C "$repo" config branch.main.merge refs/heads/main >/dev/null 2>&1
  for kv in "$@"; do
    git -C "$repo" update-ref "refs/remotes/origin/${kv%%=*}" "${kv#*=}" >/dev/null 2>&1
  done
}

# <n> 天前的本地时间，格式 yyyy-MM-ddTHH:mm:ss
# 对应 .ps1 的 (Get-Date).AddDays(-n).ToString('yyyy-MM-ddTHH:mm:ss')
iso_days_ago() {
  local n=$1 out
  if out=$(date -d "-$n days" +%Y-%m-%dT%H:%M:%S 2>/dev/null); then
    printf '%s' "$out"
  elif out=$(date -v-"$n"d +%Y-%m-%dT%H:%M:%S 2>/dev/null); then
    printf '%s' "$out"
  else
    printf '%s days ago' "$n" # 退给 git 的 approxidate 解析
  fi
}

# ============ fixture 登记 ============
# bash 3.2 无关联数组，用平行索引数组（与 .ps1 的 List[object] 顺序一致）
IDS=()
LABELS=()
PATHS=()
NOTES=()
register_fixture() {
  IDS[${#IDS[@]}]=$1
  LABELS[${#LABELS[@]}]=$2
  PATHS[${#PATHS[@]}]=$3
  NOTES[${#NOTES[@]}]=$4
}

# ============ F1-F19 ============

# ---- F1: 非 git 目录 ----
p="$OUT_DIR/F1-nongit"
mk_plain_dir "$p"
write_file "$p/a.txt" 'hello
'
register_fixture 'F1' 'non-git dir' "$p" 'expect is_git=false'

# ---- F2: 零提交仓库 ----
p="$OUT_DIR/F2-empty"
init_repo "$p"
register_fixture 'F2' 'zero-commit repo' "$p" 'head_short=null; must not crash'

# ---- F3: detached HEAD ----
p="$OUT_DIR/F3-detached"
init_repo "$p"
write_file "$p/a.txt" 'x
'
add_commit "$p" 'feat: init'
git -C "$p" checkout -q --detach HEAD >/dev/null 2>&1
register_fixture 'F3' 'detached HEAD' "$p" 'detached=true; current_branch=null'

# ---- F4: 恶意文件名 + CRLF ----
p="$OUT_DIR/F4-hostile"
init_repo "$p"
write_file "$p/base.txt" 'base
'
write_file "$p/unicode-file.txt" 'u
'
write_file "$p/it's.txt" 'q
'
write_file "$p/brace{and}tab.txt" 'b
'
write_file "$p/deep dir/sub dir/nested.txt" 'n
'
write_file_crlf "$p/gradle.properties" 'version = 9.9.9
'
write_file "$p/package.json" '{ "name": "hostile", "version": "1.0.0" }'
add_commit "$p" 'feat: hostile names'
write_file "$p/unicode-file.txt" 'u2
'
write_file "$p/deep dir/sub dir/nested.txt" 'n2
'
write_file "$p/fresh untracked.txt" '// TODO: untracked
'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/hostile.git'
register_fixture 'F4' 'hostile names + CRLF' "$p" 'strict JSON; relative forward-slash paths'

# ---- F5: 脏工作区 + 失败测试 ----
p="$OUT_DIR/F5-dirty"
init_repo "$p"
write_file "$p/package.json" '{ "name": "calc", "version": "0.3.0", "scripts": { "test": "node test.js", "build": "node build.js" } }'
write_file "$p/src/math.js" 'exports.add=(a,b)=>a+b;
'
write_file "$p/src/format.js" 'exports.fmt=v=>String(v);
'
write_file "$p/test.js" "const m=require('./src/math');if(m.add(2,3)!==5)throw new Error('add broken');console.log('all tests passed');
"
write_file "$p/build.js" "console.log('build ok');
"
write_file "$p/README.md" '# calc

Tiny calculator helpers.
'
write_file "$p/CHANGELOG.md" '# Changelog

## [0.3.0] - 2026-07-01

### Added
- format helper
'
write_file "$p/LICENSE" 'MIT License
'
add_commit "$p" 'feat: calc helpers'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/calc.git'
write_file "$p/src/math.js" 'exports.add=(a,b)=>a-b;
'
write_file "$p/src/format.js" "exports.fmt=v=>String(v);exports.pct=v=>v+'%';
"
write_file "$p/src/percent.js" '// TODO: finish percent helpers
exports.of=(v,p)=>v*p/100;
'
register_fixture 'F5' 'dirty WIP + failing test' "$p" 'todo_fixme should include untracked TODO'

# ---- F6: 干净同步 + 分支 ----
p="$OUT_DIR/F6-clean-sync"
init_repo "$p"
write_file "$p/README.md" '# counter

Library.
'
write_file "$p/src/counter.js" 'exports.add=(a,b)=>a+b;
'
write_file "$p/package.json" '{ "name": "counter", "version": "1.0.0" }'
add_commit "$p" 'feat: initial counter'
git -C "$p" checkout -q -b feature/done >/dev/null 2>&1
write_file "$p/src/counter.js" 'exports.add=(a,b)=>a+b;exports.sub=(a,b)=>a-b;
'
add_commit "$p" 'feat(counter): add sub helper'
MERGED_SHA=$(git -C "$p" rev-parse HEAD 2>/dev/null | tr -d '\r\n')
git -C "$p" checkout -q main >/dev/null 2>&1
git -C "$p" merge -q --no-ff feature/done -m 'Merge feature/done' >/dev/null 2>&1
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/counter.git' "feature/done=$MERGED_SHA"
git -C "$p" checkout -q -b feature/old >/dev/null 2>&1
write_file "$p/src/legacy.js" 'exports.legacy=()=>42;
'
add_commit "$p" 'wip: legacy experiment' '' "$(iso_days_ago 91)"
git -C "$p" checkout -q main >/dev/null 2>&1
register_fixture 'F6' 'clean sync + branches' "$p" 'unpushed_branches should include feature/old'

# ---- F7: 多生态版本号不一致 ----
p="$OUT_DIR/F7-version-mismatch"
init_repo "$p"
write_file "$p/package.json" '{ "name": "rel", "version": "1.1.0" }'
write_file "$p/Cargo.toml" '[package]
name = "rel"
version = "1.0.0"
edition = "2021"
'
write_file "$p/pyproject.toml" '[tool.poetry]
name = "rel"
version = "1.0.0"
'
write_file_crlf "$p/gradle.properties" 'version=0.9.0
'
write_file "$p/README.md" '# rel
'
add_commit "$p" 'chore: bootstrap rel'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/rel.git'
write_file "$p/package.json" '{ "name": "rel", "version": "1.1.0", "files": ["src"] }'
register_fixture 'F7' 'version mismatch (multi-ecosystem)' "$p" 'consistent=false; release_signals includes version-file-touched'

# ---- F8: CRLF 版本文件 ----
p="$OUT_DIR/F8-crlf"
init_repo "$p"
write_file_crlf "$p/gradle.properties" 'version = 9.9.9
'
write_file "$p/README.md" '# crlf
'
add_commit "$p" 'feat: crlf repo'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/crlf.git'
register_fixture 'F8' 'CRLF version file' "$p" 'strict JSON; version must not contain raw CR'

# ---- F9: 依赖里的 version 在前 ----
p="$OUT_DIR/F9-depversion"
init_repo "$p"
write_file "$p/package.json" '{ "name": "p", "dependencies": { "left-pad": { "version": "1.3.0" } }, "version": "2.0.0" }'
write_file "$p/README.md" '# p
'
add_commit "$p" 'feat: dep order'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/p.git'
register_fixture 'F9' 'dependency version before top-level' "$p" 'both impls must read top-level 2.0.0'

# ---- F10: 被忽略目录里的版本文件 ----
p="$OUT_DIR/F10-ignored"
init_repo "$p"
write_file "$p/package.json" '{ "name": "probe", "version": "1.0.0" }'
write_file "$p/vendor/sub/Cargo.toml" '[package]
name="vendored"
version="3.3.3"
'
write_file "$p/.gitignore" 'vendor/
'
write_file "$p/README.md" '# probe
'
add_commit "$p" 'feat: probe with vendor'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/probe.git'
register_fixture 'F10' 'version file inside ignored dir' "$p" 'version_files must not include vendor/'

# ---- F11: host 解析 + token 掩码 ----
p="$OUT_DIR/F11-host"
init_repo "$p"
write_file "$p/package.json" '{ "name": "h", "version": "1.0.0" }'
write_file "$p/README.md" '# h
'
add_commit "$p" 'feat: host probe'
set_fake_remote "$p" 'https://user:ghp_SUPERSECRETTOKEN@127.0.0.1:1/team/github.com-mirror.git'
register_fixture 'F11' 'host parsing + token masking' "$p" 'is_github=false; output must not contain token'

# ---- F12: 发行信号 ----
p="$OUT_DIR/F12-signals"
init_repo "$p"
write_file "$p/package.json" '{ "name": "sig", "version": "1.0.0" }'
write_file "$p/src/a.js" 'exports.a=1;
'
add_commit "$p" 'chore(release): prepare 1.1.0'
write_file "$p/src/a.js" 'exports.a=2;
'
add_commit "$p" 'feat!: drop legacy api'
write_file "$p/src/a.js" 'exports.a=3;
'
add_commit "$p" 'fix: correct rounding'
write_file "$p/src/a.js" 'exports.a=4;
'
add_commit "$p" 'refactor: move config' 'BREAKING CHANGE: config moved to config/'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/sig.git'
register_fixture 'F12' 'release signals' "$p" 'release_signals should include chore(release)/feat!/fix:/breaking-footer'

# ---- F13: monorepo ----
p="$OUT_DIR/F13-monorepo"
init_repo "$p"
write_file "$p/pnpm-workspace.yaml" "packages:
  - 'packages/*'
"
write_file "$p/packages/a/package.json" '{ "name": "@x/a", "version": "1.0.0" }'
write_file "$p/packages/b/package.json" '{ "name": "@x/b", "version": "1.0.0" }'
write_file "$p/README.md" '# mono
'
add_commit "$p" 'feat: monorepo bootstrap'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/mono.git'
register_fixture 'F13' 'monorepo' "$p" 'monorepo_mode=true; packages contains two entries'

# ---- F14: color.ui 注入 ----
p="$OUT_DIR/F14-color"
init_repo "$p"
write_file "$p/a.txt" 'base
'
add_commit "$p" 'feat: base'
git -C "$p" checkout -q -b feature/merged >/dev/null 2>&1
write_file "$p/a.txt" 'base
more
'
add_commit "$p" 'feat: merged work'
git -C "$p" checkout -q main >/dev/null 2>&1
git -C "$p" merge -q --no-ff feature/merged -m 'merge feature/merged' >/dev/null 2>&1
git -C "$p" config color.ui always >/dev/null 2>&1
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/color.git'
register_fixture 'F14' 'color injection' "$p" 'local_merged_candidates should include feature/merged'

# ---- F15: vendor 未被 .gitignore 排除 ----
p="$OUT_DIR/F15-vendor-unignored"
init_repo "$p"
write_file "$p/package.json" '{ "name": "vu", "version": "1.0.0" }'
# 关键：vendor 不在 .gitignore 里 —— 只靠 --exclude-standard 挡不住它，必须靠硬编码路径段排除
write_file "$p/vendor/sub/Cargo.toml" '[package]
name="vendored"
version="9.9.9"
'
write_file "$p/README.md" '# vu
'
add_commit "$p" 'feat: vendored tree not ignored'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/vu.git'
register_fixture 'F15' 'vendor/ NOT ignored' "$p" 'vendor/sub/Cargo.toml is tracked; hardcoded exclusion must still drop it'

# ---- F16: Cargo workspace 版本继承 ----
p="$OUT_DIR/F16-cargo-workspace"
init_repo "$p"
write_file "$p/Cargo.toml" '[workspace]
members = ["packages/a", "packages/b"]

[workspace.package]
version = "2.0.0"
edition = "2021"
'
# 成员两种写法都要识别：点号键 与 内联表
write_file "$p/packages/a/Cargo.toml" '[package]
name = "a"
version.workspace = true
edition.workspace = true
'
write_file "$p/packages/b/Cargo.toml" '[package]
name = "b"
version = { workspace = true }
edition.workspace = true
'
write_file "$p/README.md" '# ws
'
add_commit "$p" 'feat: cargo workspace'
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/ws.git'
register_fixture 'F16' 'cargo workspace inheritance' "$p" 'inherited_version_files>=2; packages=[packages/a,packages/b]; member versions must NOT enter version_files'

# ---- F17: cleanup.protect 多值 ----
p="$OUT_DIR/F17-protect-config"
init_repo "$p"
write_file "$p/package.json" '{ "name": "pc", "version": "1.0.0" }'
write_file "$p/README.md" '# pc
'
add_commit "$p" 'feat: protect config'
# 三个值：--get-all 全回；--get 只回最后一个（zeta/*）。若实现误用 --get，
# hotfix/* 会消失（release/* 会因内置字面量而假通过），故 hotfix/* 是关键判别项。
git -C "$p" config --add cleanup.protect 'release/*' >/dev/null 2>&1
git -C "$p" config --add cleanup.protect 'hotfix/*' >/dev/null 2>&1
git -C "$p" config --add cleanup.protect 'zeta/*' >/dev/null 2>&1
set_fake_remote "$p" 'https://127.0.0.1:1/github.com/team/pc.git'
register_fixture 'F17' 'cleanup.protect multi-value' "$p" 'protected must contain every --get-all value'

# ---- F18: 本地/远程合并基准分离 ----
p="$OUT_DIR/F18-merge-base-split"
init_repo "$p"
write_file "$p/a.txt" 'base
'
add_commit "$p" 'feat: base'
BASE_SHA=$(git -C "$p" rev-parse HEAD 2>/dev/null | tr -d '\r\n')
git -C "$p" checkout -q -b feature >/dev/null 2>&1
write_file "$p/a.txt" 'base
feature
'
add_commit "$p" 'feat: feature work'
FEAT_SHA=$(git -C "$p" rev-parse HEAD 2>/dev/null | tr -d '\r\n')
git -C "$p" checkout -q main >/dev/null 2>&1
git -C "$p" merge -q --no-ff feature -m 'merge feature' >/dev/null 2>&1
# 伪造一个「落后」的 origin/main：本地已合并 feature，远程还停在合并前
git -C "$p" remote add origin 'https://127.0.0.1:1/github.com/team/split.git' >/dev/null 2>&1
git -C "$p" update-ref refs/remotes/origin/main "$BASE_SHA" >/dev/null 2>&1
git -C "$p" update-ref refs/remotes/origin/feature "$FEAT_SHA" >/dev/null 2>&1
git -C "$p" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main >/dev/null 2>&1
register_fixture 'F18' 'local main merged, origin/main stale' "$p" 'local base=main (feature merged); remote base=origin/main (feature NOT merged)'

# ---- F19: 有 remote 但无 origin/<default> ----
p="$OUT_DIR/F19-base-unverified"
init_repo "$p"
write_file "$p/a.txt" 'base
'
# 关键判别项：必须有核心文档（否则 docs_stale_candidates 恒为空，「变更集为空 -> 仍须为 []」
# 这条断言就没有判别力——什么文档都没有时它本来就空）。README.md 提交进去，工作树保持干净。
write_file "$p/README.md" '# nobase

Library.
'
add_commit "$p" 'feat: base'
# 有 remote，但没有 refs/remotes/origin/<default> —— 远程基准无从验证
git -C "$p" remote add origin 'https://127.0.0.1:1/github.com/team/nobase.git' >/dev/null 2>&1
register_fixture 'F19' 'remote without origin/<default>' "$p" 'remote_base_unverified=true + remote-base-unverified warning; changeset empty + has core docs -> docs_stale_candidates=[]'

# ---- F20: 纯本地仓库（完全没有 remote）----
p="$OUT_DIR/F20-local-only"
init_repo "$p"
write_file "$p/README.md" '# local

Pure local repository: it has no remote at all.
'
write_file "$p/src/a.js" 'exports.a=1;
'
add_commit "$p" 'feat: initial local work'
write_file "$p/src/a.js" 'exports.a=2;
'
add_commit "$p" 'feat: second local commit'
# 完全没有 remote（既没有 origin，也没有任何其它 remote），工作树干净。
# 判别项：没有远程就没有「未推送分支/未推送提交」这一概念——unpushed_branches 必须 []、
# unpushed_commits 保持 null 但语义是「不适用」，并加 no-remote 警告。
register_fixture 'F20' 'local-only repo (no remote at all)' "$p" 'has_remote=false; unpushed_branches=[]; unpushed_commits=null + no-remote warning; branch audit: remote_base_unverified=true, remote_merge_base=null, remote_reachable=false'

# ---- F21: Agent Skill 仓库（SKILL.md + 自带测试入口）----
p="$OUT_DIR/F21-skill-repo"
init_repo "$p"
write_file "$p/SKILL.md" '---
name: demo-skill
description: Demo agent skill used by the eval fixtures.
metadata:
  version: "0.1.0"
  date: "2026-01-01"
---

# Demo Skill

Fixture for the Agent Skill repository ecosystem.
'
# 这一行是 F3 的判别项：只有 X 占位符（8 个连续 X），没有真正的待办标记。
write_file "$p/evals/run_evals.ps1" '#!/usr/bin/env pwsh
#Requires -Version 7.0
$BASE_TMP = [System.IO.Path]::GetTempPath()
$RUN_DIR = (mktemp -d "$BASE_TMP/attention-eval-runs-XXXXXXXX")
Write-Host "run_evals ok"
'
write_file "$p/scripts/smoke_test.ps1" '#!/usr/bin/env pwsh
#Requires -Version 7.0
Write-Host "smoke_test ok"
'
add_commit "$p" 'feat: demo agent skill'
register_fixture 'F21' 'agent skill repo (SKILL.md + bundled evals)' "$p" 'version_files has SKILL.md=0.1.0 (consistent=true); test_commands has run_evals+smoke_test; todo_fixme=[] (an X-placeholder run must not match the marker pattern)'

# ============ 输出 ============
COUNT=${#IDS[@]}

# JSON 字符串转义（反斜杠/引号/空白控制字符）
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

if [ "$JSON_MODE" -eq 1 ]; then
  TMP_JSON=$(mktemp "$OUT_DIR/.fixtures-json.XXXXXX") || die "mktemp 失败"
  {
    printf '{\n'
    printf '  "out_dir": "%s",\n' "$(json_escape "$(posix_to_native "$OUT_DIR")")"
    printf '  "count": %s,\n' "$COUNT"
    printf '  "fixtures": [\n'
    i=0
    while [ "$i" -lt "$COUNT" ]; do
      printf '    {\n'
      printf '      "id": "%s",\n' "$(json_escape "${IDS[$i]}")"
      printf '      "label": "%s",\n' "$(json_escape "${LABELS[$i]}")"
      printf '      "path": "%s",\n' "$(json_escape "$(posix_to_native "${PATHS[$i]}")")"
      printf '      "notes": "%s"\n' "$(json_escape "${NOTES[$i]}")"
      if [ "$i" -lt "$((COUNT - 1))" ]; then
        printf '    },\n'
      else
        printf '    }\n'
      fi
      i=$((i + 1))
    done
    printf '  ]\n'
    printf '}\n'
  } > "$TMP_JSON"
  cat -- "$TMP_JSON"
else
  printf 'fixtures: %s -> %s\n' "$COUNT" "$(posix_to_native "$OUT_DIR")"
  i=0
  while [ "$i" -lt "$COUNT" ]; do
    printf '  [%s] %-36s %s\n' "${IDS[$i]}" "${LABELS[$i]}" "$(posix_to_native "${PATHS[$i]}")"
    i=$((i + 1))
  done
fi

exit 0
