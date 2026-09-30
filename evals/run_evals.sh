#!/usr/bin/env bash
# evals/run_evals.sh —— attention 采集脚本回归 runner（bash 侧，对齐 evals/run_evals.ps1）
#
# 三层校验：
#   1) 严格 JSON（RFC 8259：字符串内不得有裸控制字符；拒绝 NaN/Infinity）
#   2) parity（.sh 与 .ps1 字段集一致 + 逐字段值一致）
#   3) 断言表（evals/script-assertions.json，期望值描述的是 TARGET 行为）
# 结果写入 evals/results/<yyyyMMdd-HHmmss>-<sha>.json；任一失败 → 退出码 1。
#
# 用法：
#   bash evals/run_evals.sh [--filter F7] [--no-write] [--fixtures-dir <path>] [--json]
#
# JSON 引擎探测（必须真的执行一次才算可用：Windows 上的 python3/python 常常只是
# Microsoft Store 的应用别名存根，命令存在但一执行就失败）：
#   $ATTENTION_EVAL_PYTHON → $PYTHON → python3 → python → py -3 → 常见安装位置扫描
# 只有 jq、或连 jq 都没有时：明确 SKIP 并说明，退出码 2（见 "JSON 引擎" 一节）。
#
# 与 run_evals.ps1 的差异（其余逐条对齐：fixture 矩阵 / 伪 fixture / 三层校验 /
# 结果文件名与 payload 结构 / 退出码语义）：
#   1. summary 里多两个字段 pwsh、engine（ps1 只报 bash）。
#   2. SKIP 的措辞按实际缺失方区分（ps1 侧缺 pwsh 时也写 "SKIP(bash 不可用)"）。
#   3. 临时运行目录用 trap 清理（ps1 不清理），--keep-temp 可保留用于排障。
#   4. 结果文件用 LF + UTF-8 无 BOM 写出（ps1 在 Windows 上是 CRLF）。
set -u

PROG=${0##*/}
die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit 2; }

usage() {
  cat <<'USAGE'
用法: bash evals/run_evals.sh [选项]

  --fixtures-dir <path>   fixture 目录（默认: <系统临时目录>/attention-evals）
  --out-dir <path>        同 --fixtures-dir（别名）
  --filter <子串>         只跑 id 含该子串的 fixture（大小写不敏感，可重复，逗号分隔亦可）
  --timeout <秒>          单个脚本超时秒数（默认 20；NEG-NOVALUE 固定 5）
  --json                  以 JSON 打印 summary（同时按退出码语义返回）
  --no-write              不写 evals/results/
  --keep-temp             保留临时运行目录（默认清理）
  -v, --verbose           把每个 run 的结果打到 stderr
  -h, --help              显示本帮助

退出码: 0=全部通过  1=有 check 失败  2=运行前提不满足（fixture 生成失败/无 JSON 引擎等）
USAGE
}

# ============ 参数 ============
FIX_DIR=''
FILTERS=()
TIMEOUT_SECONDS=20
JSON_OUT=0
NO_WRITE=0
KEEP_TEMP=0
VERBOSE=0

add_filter() { # 允许一次给逗号分隔的多个子串（对齐 ps1 的 -Filter F7,F9）
  local rest=$1 part
  while :; do
    case "$rest" in
      *,*) part=${rest%%,*}; rest=${rest#*,} ;;
      *) part=$rest; rest='' ;;
    esac
    [ -n "$part" ] && FILTERS[${#FILTERS[@]}]=$part
    [ -n "$rest" ] || break
  done
}

while [ $# -gt 0 ]; do
  case "$1" in
    --fixtures-dir|--out-dir)
      [ $# -ge 2 ] || die "$1 缺少参数值"
      FIX_DIR=$2
      shift 2
      ;;
    --fixtures-dir=*|--out-dir=*)
      FIX_DIR=${1#*=}
      shift
      ;;
    --filter)
      [ $# -ge 2 ] || die "--filter 缺少参数值"
      add_filter "$2"
      shift 2
      ;;
    --filter=*)
      add_filter "${1#--filter=}"
      shift
      ;;
    --timeout)
      [ $# -ge 2 ] || die "--timeout 缺少参数值"
      TIMEOUT_SECONDS=$2
      shift 2
      ;;
    --timeout=*)
      TIMEOUT_SECONDS=${1#--timeout=}
      shift
      ;;
    --json) JSON_OUT=1; shift ;;
    --no-write) NO_WRITE=1; shift ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1（用 --help 查看用法）" ;;
  esac
done

case "$TIMEOUT_SECONDS" in
  ''|*[!0-9]*) die "--timeout 需要正整数秒，收到: $TIMEOUT_SECONDS" ;;
esac
[ "$TIMEOUT_SECONDS" -ge 1 ] || die "--timeout 需要 >= 1"

# ============ 目录与常量 ============
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd) || die "无法定位脚本目录"
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd) || die "无法定位仓库根目录"
SCR_DIR="$REPO_ROOT/scripts"
SPEC_FILE="$SCRIPT_DIR/script-assertions.json"
FIXTURES_SH="$SCRIPT_DIR/fixtures.sh"
RESULTS_DIR="$SCRIPT_DIR/results"

SCRIPTS=(git_state_snapshot branch_cleanup_audit version_consistency_audit core_docs_relevance_scan next_steps_analysis)

[ -f "$FIXTURES_SH" ] || die "找不到 $FIXTURES_SH"
[ -f "$SPEC_FILE" ] || die "找不到 $SPEC_FILE"

TAB=$(printf '\t')

# ============ 路径工具 ============
# fixtures.sh 输出的是平台原生路径（Windows 下是 C:\...）；喂给 .sh 需要 POSIX 形式，
# 喂给 pwsh / python 需要原生形式。与 run_evals.ps1 的 ConvertTo-PosixPath 对应。
to_posix() {
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
to_native() {
  if command -v cygpath >/dev/null 2>&1; then
    _n=$(cygpath -w -- "$1" 2>/dev/null) && [ -n "$_n" ] && { printf '%s' "$_n"; return 0; }
  fi
  printf '%s' "$1"
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ============ 临时目录 ============
BASE_TMP=${TMPDIR:-}
[ -n "$BASE_TMP" ] || BASE_TMP=${TEMP:-}
[ -n "$BASE_TMP" ] || BASE_TMP=${TMP:-}
[ -n "$BASE_TMP" ] || BASE_TMP=/tmp
[ -n "$FIX_DIR" ] || FIX_DIR="$BASE_TMP/attention-evals"
FIX_DIR=$(to_posix "$FIX_DIR")

RUN_DIR=$(mktemp -d "$BASE_TMP/attention-eval-runs-XXXXXXXX") || die "mktemp 失败（$BASE_TMP）"
# shellcheck disable=SC2329  # 由 trap 调用
cleanup() {
  if [ "$KEEP_TEMP" -eq 0 ]; then
    rm -rf -- "$RUN_DIR"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# ============ JSON 引擎 ============
# 只探测"能真的跑起来"的 python：Windows 的 python3.exe 常是 Store 别名存根。
PY_EXE=''
PY_EXTRA=''
ENGINE=''
ENGINE_DESC=''
JQ_EXE=''

python_ok() { # $1=exe $2=额外参数（可为空字符串）
  if [ -n "$2" ]; then
    printf '{}' | "$1" "$2" -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1
  else
    printf '{}' | "$1" -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1
  fi
}
try_python() { # $1=exe $2=额外参数
  [ -n "$1" ] || return 1
  command -v "$1" >/dev/null 2>&1 || [ -x "$1" ] || return 1
  if python_ok "$1" "${2:-}"; then
    PY_EXE=$1
    PY_EXTRA=${2:-}
    ENGINE=python
    ENGINE_DESC=$1
    [ -n "$2" ] && ENGINE_DESC="$1 $2"
    return 0
  fi
  return 1
}

if [ -n "${ATTENTION_EVAL_PYTHON:-}" ]; then
  _cand=$(to_posix "$ATTENTION_EVAL_PYTHON")
  try_python "$_cand" '' || printf '[warn] ATTENTION_EVAL_PYTHON 不可用: %s\n' "$ATTENTION_EVAL_PYTHON" >&2
fi
[ -n "$ENGINE" ] || try_python "${PYTHON:-}" ''
[ -n "$ENGINE" ] || try_python python3 ''
[ -n "$ENGINE" ] || try_python python ''
[ -n "$ENGINE" ] || try_python py '-3'
if [ -z "$ENGINE" ]; then
  # 常见安装位置扫描（uv / pyenv / 官方安装器）；只作为 python3/python 不可用时的兜底
  for _base in "$(to_posix "${LOCALAPPDATA:-}")/Programs/Python" \
               "$(to_posix "${APPDATA:-}")/uv/python" \
               "$HOME/.local/share/uv/python" \
               "$HOME/.pyenv/versions" \
               "$(to_posix "${ProgramFiles:-}")/Python"; do
    [ -d "$_base" ] || continue
    for _cand in "$_base"/*/python.exe "$_base"/*/bin/python3 "$_base"/*/python3; do
      [ -x "$_cand" ] || continue
      try_python "$_cand" '' && break
    done
    [ -n "$ENGINE" ] && break
  done
fi
if [ -z "$ENGINE" ] && command -v jq >/dev/null 2>&1; then
  if printf '{}' | jq -e . >/dev/null 2>&1; then
    JQ_EXE=$(command -v jq)
  fi
fi
if [ -z "$ENGINE" ]; then
  printf '%s: [SKIP] 找不到可用的 JSON 引擎，三层校验无法评估。\n' "$PROG" >&2
  if [ -n "$JQ_EXE" ]; then
    printf '        只找到 jq（%s）：jq 能做严格 JSON 解析，但 parity 与断言表需要\n' "$JQ_EXE" >&2
    printf '        逐字段比较/点号路径求值；只做半个引擎会给出误导性的红绿结论，故不评估。\n' >&2
  fi
  printf '        请安装 python3，或用 ATTENTION_EVAL_PYTHON=<解释器路径> 指定，例如：\n' >&2
  printf '          ATTENTION_EVAL_PYTHON=/usr/bin/python3 bash evals/run_evals.sh\n' >&2
  printf '        注意：Windows 上 python3.exe 可能只是 Microsoft Store 的应用别名存根\n' >&2
  printf '              （命令存在但一执行就失败），所以这里必须真的跑一次才算可用。\n' >&2
  exit 2
fi
printf '[info] JSON 引擎: %s\n' "$ENGINE_DESC" >&2

run_py() {
  if [ -n "$PY_EXTRA" ]; then "$PY_EXE" "$PY_EXTRA" "$@"; else "$PY_EXE" "$@"; fi
}
# Windows 上 python 的 stdout 默认用 locale 编码（本机是 gbk），而消费方（PowerShell 7 /
# Git Bash）都按 UTF-8 解码 → 中文会变成乱码。显式钉成 UTF-8。
PYTHONIOENCODING=utf-8
export PYTHONIOENCODING

# ============ 依赖探测（pwsh / bash） ============
BASH_EXE=$(command -v bash 2>/dev/null || true)
[ -n "$BASH_EXE" ] || BASH_EXE=/bin/bash
BASH_OK=0
if "$BASH_EXE" -c 'exit 0' >/dev/null 2>&1; then BASH_OK=1; fi
if [ "$BASH_OK" -eq 0 ]; then
  printf '[warn] bash 不可用：.sh 侧将标记 SKIP（不视为通过）\n' >&2
fi

PWSH_EXE=$(command -v pwsh 2>/dev/null || true)
if [ -z "$PWSH_EXE" ] && [ -x '/c/Program Files/PowerShell/7/pwsh.exe' ]; then
  PWSH_EXE='/c/Program Files/PowerShell/7/pwsh.exe'
fi
PWSH_OK=0
if [ -n "$PWSH_EXE" ]; then
  if "$PWSH_EXE" -NoProfile -Command 'exit 0' >/dev/null 2>&1; then PWSH_OK=1; fi
fi
if [ "$PWSH_OK" -eq 0 ]; then
  printf '[warn] pwsh 不可用：.ps1 侧将标记 SKIP（不视为通过）\n' >&2
fi

# ============ 计时 / 带超时执行 ============
now_ms() {
  _n=$(date +%s%3N 2>/dev/null)
  case "$_n" in
    ''|*[!0-9]*) printf '%s000' "$(date +%s)" ;;
    *) printf '%s' "$_n" ;;
  esac
}

RUN_EXIT='null'
RUN_TIMEDOUT=0
# run_timed <超时秒> <stdout文件> <stderr文件> <命令...>
# 不用 timeout(1)：macOS 无此命令。看门狗子 shell 用 kill -9 结束被测脚本，
# 是否超时以标志文件为准（与 ps1 的 WaitForExit 布尔值语义一致）。
run_timed() {
  local t=$1 out=$2 err=$3
  shift 3
  local flag="$RUN_DIR/.watchdog-$$-$RANDOM"
  local pid watchdog status
  "$@" > "$out" 2> "$err" &
  pid=$!
  (
    sleep "$t"
    if kill -0 "$pid" 2>/dev/null; then
      : > "$flag"
      kill -9 "$pid" 2>/dev/null
    fi
  ) &
  watchdog=$!
  wait "$pid" 2>/dev/null
  status=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  if [ -e "$flag" ]; then
    RUN_TIMEDOUT=1
    RUN_EXIT='null'
  else
    RUN_TIMEDOUT=0
    RUN_EXIT=$status
  fi
  rm -f -- "$flag"
}

# ============ 生成 fixture ============
FIX_JSON="$RUN_DIR/fixtures.json"
if ! "$BASH_EXE" "$FIXTURES_SH" --json --out-dir "$FIX_DIR" > "$FIX_JSON" 2> "$RUN_DIR/fixtures.err"; then
  printf '%s: [error] fixtures.sh 失败：\n' "$PROG" >&2
  cat -- "$RUN_DIR/fixtures.err" >&2
  exit 2
fi
FIX_MAP_RAW="$RUN_DIR/fixtures.tsv"
# 写 sys.stdout.buffer：绕开 Windows 上 python 的 \n -> \r\n 文本模式转换，
# 否则路径末尾会多一个 CR，pwsh 侧就会解析到错误的仓库。
run_py -c 'import json,sys
d = json.load(sys.stdin)
for f in d.get("fixtures", []):
    sys.stdout.buffer.write(("%s\t%s\n" % (f["id"], f["path"])).encode("utf-8"))' < "$FIX_JSON" > "$FIX_MAP_RAW" || {
  printf '%s: [error] fixtures.sh 的 JSON 无法解析\n' "$PROG" >&2
  exit 2
}

FIX_IDS=()
FIX_PATHS=()
while IFS="$TAB" read -r _id _path; do
  _id=${_id%$'\r'}
  _path=${_path%$'\r'}
  [ -n "$_id" ] || continue
  FIX_IDS[${#FIX_IDS[@]}]=$_id
  FIX_PATHS[${#FIX_PATHS[@]}]=$_path
done < "$FIX_MAP_RAW"
[ "${#FIX_IDS[@]}" -gt 0 ] || die "fixtures.sh 没有产出任何 fixture"

path_for_id() {
  local want=$1 i=0
  while [ "$i" -lt "${#FIX_IDS[@]}" ]; do
    if [ "${FIX_IDS[$i]}" = "$want" ]; then printf '%s' "${FIX_PATHS[$i]}"; return 0; fi
    i=$((i + 1))
  done
  return 1
}

# 伪 fixture：无效 --repo（与 run_evals.ps1 一致）
NEG_DIR="$RUN_DIR/no-such-dir"
NEG_FILE_PATH="$RUN_DIR/a-file.txt"
printf 'plain\n' > "$NEG_FILE_PATH"
NEG_NOVALUE_PATH=$(path_for_id 'F6') || die "fixtures 里没有 F6（NEG-NOVALUE 需要它）"
FIX_IDS[${#FIX_IDS[@]}]='NEG-PATH'
FIX_PATHS[${#FIX_PATHS[@]}]="$NEG_DIR"
FIX_IDS[${#FIX_IDS[@]}]='NEG-FILE'
FIX_PATHS[${#FIX_PATHS[@]}]="$NEG_FILE_PATH"
FIX_IDS[${#FIX_IDS[@]}]='NEG-NOVALUE'
FIX_PATHS[${#FIX_PATHS[@]}]="$NEG_NOVALUE_PATH"

# 全部 id 排序（对齐 ps1 的 Sort-Object），再按 --filter 过滤（大小写不敏感子串 OR）
ALL_IDS=()
while IFS= read -r _id; do
  _id=${_id%$'\r'}
  [ -n "$_id" ] || continue
  if [ "${#FILTERS[@]}" -gt 0 ]; then
    _match=0
    _id_low=$(lower "$_id")
    for _f in ${FILTERS[@]+"${FILTERS[@]}"}; do
      _f_low=$(lower "$_f")
      case "$_id_low" in
        *"$_f_low"*) _match=1 ;;
      esac
    done
    [ "$_match" -eq 1 ] || continue
  fi
  ALL_IDS[${#ALL_IDS[@]}]=$_id
done < <(printf '%s\n' "${FIX_IDS[@]}" | LC_ALL=C sort)

if [ "${#ALL_IDS[@]}" -eq 0 ]; then
  printf '[warn] --filter 未匹配任何 fixture：checks=0（.ps1 版同样会报绿，注意别被误导）\n' >&2
fi

# ============ 跑矩阵 ============
MANIFEST="$RUN_DIR/manifest.tsv"
: > "$MANIFEST"
RUN_COUNT=0
for _id in ${ALL_IDS[@]+"${ALL_IDS[@]}"}; do
  _repo_native=$(path_for_id "$_id") || die "找不到 $_id 的路径"
  _repo_posix=$(to_posix "$_repo_native")
  _tmo=$TIMEOUT_SECONDS
  _novalue=0
  if [ "$_id" = 'NEG-NOVALUE' ]; then
    _tmo=5
    _novalue=1
  fi
  for _sc in "${SCRIPTS[@]}"; do
    for _impl in sh ps1; do
      _out_base="$_id-$_sc-$_impl.out"
      _out_file="$RUN_DIR/$_out_base"
      _err_base="$_out_base.err"
      _err_file="$RUN_DIR/$_err_base"
      _skip=0
      RUN_EXIT='null'
      RUN_TIMEDOUT=0
      _ms=0
      CMD=()
      if [ "$_impl" = 'sh' ]; then
        if [ "$BASH_OK" -eq 0 ]; then
          _skip=1
        else
          CMD[0]=$(to_posix "$BASH_EXE")
          CMD[1]="$SCR_DIR/$_sc.sh"
          CMD[2]='--repo'
          [ "$_novalue" -eq 0 ] && CMD[3]="$_repo_posix"
        fi
      else
        if [ "$PWSH_OK" -eq 0 ]; then
          _skip=1
        else
          CMD[0]=$(to_posix "$PWSH_EXE")
          CMD[1]='-NoProfile'
          CMD[2]='-File'
          CMD[3]=$(to_native "$SCR_DIR/$_sc.ps1")
          CMD[4]='--repo'
          [ "$_novalue" -eq 0 ] && CMD[5]="$_repo_native"
        fi
      fi
      if [ "$_skip" -eq 1 ]; then
        : > "$_out_file"
        : > "$_err_file"
      else
        _t0=$(now_ms)
        run_timed "$_tmo" "$_out_file" "$_err_file" "${CMD[@]}"
        _t1=$(now_ms)
        _ms=$((_t1 - _t0))
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$_id" "$_sc" "$_impl" "$_skip" "$RUN_TIMEDOUT" "$RUN_EXIT" "$_ms" "$_out_base" "$_err_base" \
        >> "$MANIFEST"
      RUN_COUNT=$((RUN_COUNT + 1))
      if [ "$VERBOSE" -eq 1 ]; then
        if [ "$_skip" -eq 1 ]; then
          printf '[run] %s|%s|%s SKIP\n' "$_id" "$_sc" "$_impl" >&2
        elif [ "$RUN_TIMEDOUT" -eq 1 ]; then
          printf '[run] %s|%s|%s TIMEOUT %sms\n' "$_id" "$_sc" "$_impl" "$_ms" >&2
        else
          printf '[run] %s|%s|%s exit=%s %sms\n' "$_id" "$_sc" "$_impl" "$RUN_EXIT" "$_ms" >&2
        fi
      fi
    done
  done
done

# ============ 汇总元信息 ============
GIT_SHA=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null | tr -d '\r\n')
GIT_DIRTY=0
if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then GIT_DIRTY=1; fi
WHEN=$(date +%Y-%m-%dT%H:%M:%S)
STAMP=$(date +%Y%m%d-%H%M%S)

# ============ 断言引擎（python，逻辑逐条对齐 run_evals.ps1） ============
ENGINE_PY="$RUN_DIR/engine.py"
cat > "$ENGINE_PY" <<'PYENGINE_EOF'
"""attention evals 断言引擎：严格 JSON + parity + 断言表。

逐条对齐 evals/run_evals.ps1，包括几处 PowerShell 特有的语义：
  * -eq 对字符串不区分大小写（Equals/Contains 则区分）；
  * -match 是不区分大小写的正则搜索；
  * Select-Object -Unique 对字符串区分大小写（已实测），Group-Object 不区分；
  * JsonDocument.Parse 拒绝裸控制字符/NaN，而 ConvertFrom-Json 更宽松
    —— 因此"严格 JSON"与"可解析"是两个独立结论。
"""
import argparse
import json
import os
import re
import sys


def read_text(path):
    try:
        with open(path, 'rb') as f:
            b = f.read()
    except OSError:
        return ''
    s = b.decode('utf-8', errors='replace')
    if s.startswith('\ufeff'):  # .ps1 用 Get-Content -Raw，解码时会吃掉 BOM
        s = s[1:]
    return s


def _reject_const(name):
    raise ValueError('非法 JSON 常量: %s' % name)


def parse_json(text):
    """返回 (parsed, strict_ok)。

    strict 对应 .ps1 的 [System.Text.Json.JsonDocument]::Parse（RFC 8259）；
    宽松那一档对应 .ps1 的 ConvertFrom-Json（允许字符串内裸控制字符）。
    """
    if text is None or text.strip() == '':
        return None, False
    try:
        return json.loads(text, parse_constant=_reject_const), True
    except Exception:
        pass
    try:
        return json.loads(text, strict=False, parse_constant=_reject_const), False
    except Exception:
        return None, False


def ps_str(v):
    if v is None:
        return ''
    if v is True:
        return 'True'
    if v is False:
        return 'False'
    if isinstance(v, str):
        return v
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return str(int(v))
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, list):
        return ' '.join(ps_str(x) for x in v)
    if isinstance(v, dict):
        return '@{' + '; '.join('%s=%s' % (k, ps_str(x)) for k, x in v.items()) + '}'
    return str(v)


def ps_val_str(v):
    """[string]$c.value"""
    return ps_str(v)


def ps_eq(a, b):
    """模拟 PowerShell `$a -eq [string]$b`：左操作数类型决定转换，字符串比较不区分大小写。"""
    if isinstance(a, bool):
        lb = b.strip().lower()
        if lb == 'true':
            return a is True
        if lb == 'false':
            return a is False
        return False
    if isinstance(a, (int, float)):
        try:
            return float(a) == float(b.strip())
        except ValueError:
            return False
    if isinstance(a, str):
        return a.lower() == b.lower()
    return False


def ps_truthy(v):
    if v is True:
        return True
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return v == 1
    if isinstance(v, str):
        return v.strip().lower() == 'true'
    return False


def ps_falsy(v):
    if v is False:
        return True
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return v == 0
    if isinstance(v, str):
        return v.strip().lower() == 'false'
    return False


def get_raw_value(doc, path):
    """run_evals.ps1 的 Get-RawValue：点号路径，[] 展开每个元素。

    注意 PS 的 $next += $val 语义：RHS 是数组时按元素拼接（展开一层，
    但不再递归展开数组元素）；展开分支里的 foreach + += 会再多展开一层。
    """
    segs = path.split('.')
    cur = [doc]
    ok = True
    for seg0 in segs:
        seg = seg0
        expand = False
        if seg.endswith('[]'):
            expand = True
            seg = seg[:-2]
        nxt = []
        for o in cur:
            if o is None:
                continue
            if not isinstance(o, dict) or seg not in o:
                ok = False
                break
            val = o[seg]
            if expand:
                if isinstance(val, list):
                    for e in val:
                        if isinstance(e, list):
                            nxt.extend(e)
                        else:
                            nxt.append(e)
                elif val is not None:
                    nxt.append(val)
            else:
                if isinstance(val, list):
                    nxt.extend(val)
                else:
                    nxt.append(val)
        if not ok:
            break
        cur = nxt
    return ok, cur


def flatten(values):
    out = []
    for v in values:
        if isinstance(v, list):
            out.extend(v)
        else:
            out.append(v)
    return out


def ukey(v):
    if isinstance(v, bool):
        return ('bool', v)
    if isinstance(v, (int, float)):
        return ('num', float(v))
    if isinstance(v, str):
        return ('str', v)
    return ('json', json.dumps(v, sort_keys=True, ensure_ascii=False))


def dup_names(flat):  # Group-Object 不区分大小写
    order = []
    seen = {}
    for v in flat:
        k = ps_str(v).lower()
        if k not in seen:
            seen[k] = [0, ps_str(v)]
            order.append(k)
        seen[k][0] += 1
    return ','.join(seen[k][1] for k in order if seen[k][0] > 1)


def canon(v):
    # 保留键序：ps1 的 ConvertTo-Json 按属性顺序序列化，parity 是顺序敏感的
    return json.dumps(v, ensure_ascii=False, separators=(',', ':'))


def compare_parity(a, b):
    if not isinstance(a, dict) or not isinstance(b, dict):
        ca, cb = canon(a), canon(b)
        return None if ca == cb else '文档不同: sh=%s ps1=%s' % (ca, cb)
    ka = sorted(a.keys())
    kb = sorted(b.keys())
    if ka != kb:
        return '字段集不同: sh=[%s] ps1=[%s]' % (','.join(ka), ','.join(kb))
    diffs = []
    for k in ka:
        ca, cb = canon(a[k]), canon(b[k])
        if ca != cb:
            diffs.append('%s: sh=%s ps1=%s' % (k, ca, cb))
    if diffs:
        return ' ; '.join(diffs)
    return None


def eval_op(op, flat, value):
    joined = ','.join(ps_str(v) for v in flat)
    if op == 'is_true':
        return (len(flat) == 1 and ps_truthy(flat[0])), '值=%s' % joined
    if op == 'is_false':
        return (len(flat) == 1 and ps_falsy(flat[0])), '值=%s' % joined
    if op == 'is_null':
        return (len(flat) >= 1 and all(v is None for v in flat)), '值=%s' % joined
    if op == 'is_empty_array':
        return (len(flat) == 0), '元素数=%d' % len(flat)
    if op == 'is_nonempty_array':
        return (len(flat) > 0), '元素数=%d' % len(flat)
    if op == 'equals':
        v = ps_val_str(value)
        return (len(flat) >= 1 and any(ps_eq(x, v) for x in flat)), '值=%s' % joined
    if op == 'contains':
        v = ps_val_str(value)
        return any(ps_eq(x, v) or (v in ps_str(x)) for x in flat), '值=%s' % joined
    if op == 'not_contains':
        v = ps_val_str(value)
        return (not any(ps_eq(x, v) or (v in ps_str(x)) for x in flat)), '值=%s' % joined
    if op == 'matches':
        v = ps_val_str(value)
        try:
            rx = re.compile(v, re.IGNORECASE)
        except re.error:
            rx = None
        return (rx is not None and any(rx.search(ps_str(x)) for x in flat)), '值=%s' % joined
    if op == 'count_gte':
        try:
            n = int(value)
        except (TypeError, ValueError):
            n = 0
        return (len(flat) >= n), '元素数=%d 期望>=%s' % (len(flat), ps_str(value))
    if op == 'unique_array':
        keys = [ukey(x) for x in flat]
        if len(set(keys)) == len(keys):
            return True, 'ok'
        return False, '重复项: %s' % dup_names(flat)
    return False, '未知 op: %s' % op


def load_runs(manifest_path, run_dir):
    runs = {}
    rows = []
    for line in read_text(manifest_path).splitlines():
        if not line.strip():
            continue
        parts = line.split('\t')
        if len(parts) != 9:
            raise SystemExit('manifest 行格式异常: %r' % line)
        fixture, script, impl, skip, timedout, exit_s, ms_s, out_base, err_base = parts
        raw = read_text(os.path.join(run_dir, out_base))
        err = read_text(os.path.join(run_dir, err_base))
        parsed, strict = parse_json(raw)
        run = {
            'fixture': fixture, 'script': script, 'impl': impl,
            'skip': skip == '1', 'timedout': timedout == '1',
            'exit': None if exit_s == 'null' else int(exit_s),
            'ms': int(ms_s), 'raw': raw, 'stderr': err,
            'parsed': parsed, 'strict': strict,
        }
        runs[(fixture, script, impl)] = run
        rows.append(run)
    return runs, rows


def build_rows(spec, runs, ids, scripts):
    out = []
    for c in spec.get('checks', []):
        op = c.get('op')
        fx = c.get('fixtures')
        if fx == '*' or not fx:
            fx_list = list(ids)
        elif isinstance(fx, list):
            fx_list = fx
        else:
            fx_list = [fx]
        sc = c.get('script')
        if sc == '*':
            sc_list = list(scripts)
        elif isinstance(sc, list):
            sc_list = sc
        else:
            sc_list = [sc]
        im = c.get('impl')
        if im == '*':
            im_list = ['sh', 'ps1']
        elif isinstance(im, list):
            im_list = im
        else:
            im_list = [im]

        def add(fixture, script, impl, ok, detail):
            out.append({'id': c.get('id'), 'fixture': fixture, 'script': script,
                        'impl': impl, 'op': op, 'pass': bool(ok),
                        'detail': detail, 'note': c.get('note')})

        for f in fx_list:
            for s in sc_list:
                if op == 'parity':
                    a = runs.get((f, s, 'sh'))
                    b = runs.get((f, s, 'ps1'))
                    if a is None or b is None:
                        continue
                    if a['skip'] or b['skip']:
                        who = 'bash' if a['skip'] else 'pwsh'
                        add(f, s, 'sh+ps1', False, 'SKIP(%s 不可用)' % who)
                        continue
                    if a['timedout'] or b['timedout']:
                        add(f, s, 'sh+ps1', False, 'TIMEOUT')
                        continue
                    if a['parsed'] is None or b['parsed'] is None:
                        add(f, s, 'sh+ps1', False, 'JSON 解析失败（见 strict_json 检查）')
                        continue
                    d = compare_parity(a['parsed'], b['parsed'])
                    add(f, s, 'sh+ps1', d is None, d if d else 'ok')
                    continue
                for i in im_list:
                    run = runs.get((f, s, i))
                    if run is None:
                        continue
                    if run['skip']:
                        who = 'bash' if i == 'sh' else 'pwsh'
                        add(f, s, i, False, 'SKIP(%s 不可用)' % who)
                        continue
                    if op == 'strict_json':
                        ok = run['strict']
                        det = 'ok' if ok else '非法 JSON: ' + re.sub(r'\s+', ' ', run['raw']).strip()[:160]
                        add(f, s, i, ok, det)
                        continue
                    if op == 'no_hang':
                        ok = not run['timedout']
                        det = ('超过 %ss 未退出（疑似死循环）' % c.get('timeout_seconds')) if run['timedout'] \
                            else ('退出于 %sms' % run['ms'])
                        add(f, s, i, ok, det)
                        continue
                    if op == 'raw_not_contains':
                        v = ps_val_str(c.get('value'))
                        hit = bool(run['raw']) and (v in run['raw'])
                        add(f, s, i, not hit, '原始输出含敏感值' if hit else 'ok')
                        continue
                    if run['timedout'] or run['parsed'] is None:
                        add(f, s, i, False, '无有效 JSON 输出')
                        continue
                    path = c.get('path', '')
                    found, values = get_raw_value(run['parsed'], path)
                    if not found:
                        add(f, s, i, False, '字段不存在: %s' % path)
                        continue
                    ok, det = eval_op(op, flatten(values), c.get('value'))
                    add(f, s, i, ok, det)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--spec', required=True)
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--run-dir', required=True)
    ap.add_argument('--ids', required=True)
    ap.add_argument('--scripts', required=True)
    ap.add_argument('--results-dir', required=True)
    ap.add_argument('--repo', required=True)
    ap.add_argument('--when', required=True)
    ap.add_argument('--stamp', required=True)
    ap.add_argument('--git-sha', default='')
    ap.add_argument('--git-dirty', default='0')
    ap.add_argument('--bash-available', default='0')
    ap.add_argument('--pwsh-available', default='0')
    ap.add_argument('--engine', default='')
    ap.add_argument('--no-write', default='0')
    ap.add_argument('--json', default='0')
    args = ap.parse_args()

    spec_text = read_text(args.spec)
    try:
        spec = json.loads(spec_text)
    except Exception as exc:
        print('无法解析断言表 %s: %s' % (args.spec, exc), file=sys.stderr)
        return 2
    ids = [ln.strip() for ln in read_text(args.ids).splitlines() if ln.strip()]
    scripts = args.scripts.split()
    try:
        runs, run_rows = load_runs(args.manifest, args.run_dir)
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return 2

    results = build_rows(spec, runs, ids, scripts)
    failed = [r for r in results if not r['pass']]
    summary = {
        'when': args.when,
        'repo': args.repo,
        'git_sha': args.git_sha or None,
        'git_dirty': args.git_dirty == '1',
        'bash': 'available' if args.bash_available == '1' else 'unavailable',
        'pwsh': 'available' if args.pwsh_available == '1' else 'unavailable',
        'engine': args.engine,
        'fixtures': len(ids),
        'runs': len(run_rows),
        'checks_total': len(results),
        'checks_passed': len(results) - len(failed),
        'checks_failed': len(failed),
        'failures': [{'id': r['id'], 'fixture': r['fixture'], 'script': r['script'],
                      'impl': r['impl'], 'op': r['op'], 'detail': r['detail']}
                     for r in failed],
    }

    if args.no_write != '1':
        os.makedirs(args.results_dir, exist_ok=True)
        path = os.path.join(args.results_dir, '%s-%s.json' % (args.stamp, args.git_sha or ''))
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            json.dump({'summary': summary, 'results': results}, f, ensure_ascii=False, indent=2)
            f.write('\n')
        print('results -> %s' % path)

    if args.json == '1':
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 1 if failed else 0

    print('')
    print('=' * 68)
    print('checks: %d passed / %d failed / %d total   (bash: %s, pwsh: %s, engine: %s)' % (
        summary['checks_passed'], summary['checks_failed'], summary['checks_total'],
        summary['bash'], summary['pwsh'], summary['engine']))
    if failed:
        groups = {}
        for r in failed:
            groups.setdefault(r['fixture'], []).append(r)
        print('')
        print('失败项（按 fixture 分组）：')
        for fx in sorted(groups.keys()):
            print('  [%s]' % fx)
            for r in groups[fx]:
                print('      %-34s %-6s %s' % (r['id'], r['impl'], r['detail']))
    print('=' * 68)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
PYENGINE_EOF

IDS_FILE="$RUN_DIR/ids.txt"
: > "$IDS_FILE"
for _id in ${ALL_IDS[@]+"${ALL_IDS[@]}"}; do
  printf '%s\n' "$_id" >> "$IDS_FILE"
done

run_py "$(to_native "$ENGINE_PY")" \
  --spec "$(to_native "$SPEC_FILE")" \
  --manifest "$(to_native "$MANIFEST")" \
  --run-dir "$(to_native "$RUN_DIR")" \
  --ids "$(to_native "$IDS_FILE")" \
  --scripts "${SCRIPTS[*]}" \
  --results-dir "$(to_native "$RESULTS_DIR")" \
  --repo "$(to_native "$REPO_ROOT")" \
  --when "$WHEN" \
  --stamp "$STAMP" \
  --git-sha "$GIT_SHA" \
  --git-dirty "$GIT_DIRTY" \
  --bash-available "$BASH_OK" \
  --pwsh-available "$PWSH_OK" \
  --engine "$ENGINE_DESC" \
  --no-write "$NO_WRITE" \
  --json "$JSON_OUT"
RC=$?

if [ "$KEEP_TEMP" -eq 1 ]; then
  printf '[info] 临时运行目录（--keep-temp）: %s\n' "$RUN_DIR" >&2
fi
exit "$RC"
