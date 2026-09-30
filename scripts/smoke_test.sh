#!/usr/bin/env bash
# 冒烟自检：对目标仓库跑全部 5 个采集脚本（两套实现），校验 JSON 与语义正确性。
#
# 与"只要能解析出 is_git 就算过"的旧版不同，本冒烟断言：
#   1) 输出是合法 JSON 且含 is_git；2) is_git 与"该路径是否真在 git 工作树里"（独立判定）一致；
#   3) 在仓库内时 repo_root 必须等于 git 的 toplevel（防"静默分析了别的仓库"，见 docs/QUALITY-AUDIT.md D1）。
# .sh 始终运行；pwsh 可用时（按能否执行探测）同时运行 .ps1 并各自断言；不可用则记 SKIP（不算通过）。
# 用法: bash scripts/smoke_test.sh [--repo <path>]
set -u

REPO_ARG=""
HAVE_REPO_ARG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      if [ $# -ge 2 ]; then REPO_ARG="$2"; shift 2; else HAVE_REPO_ARG=1; shift; fi ;;
    --help|-h)
      echo "Usage: bash scripts/smoke_test.sh [--repo <path>]"
      echo "Runs all 5 collectors (both implementations when pwsh is available) and asserts:"
      echo "  valid JSON; is_git matches reality; repo_root matches git's toplevel."
      exit 0 ;;
    *) shift ;;
  esac
done

if [ "$HAVE_REPO_ARG" -eq 1 ] || { [ -n "$REPO_ARG" ] && [ ! -d "$REPO_ARG" ]; }; then
  printf '[FAIL] --repo path not found: %s\n' "${REPO_ARG:-<missing>}"
  exit 1
fi

BASE=$(cd "$(dirname "$0")" && pwd) || exit 1
if [ -n "$REPO_ARG" ]; then TARGET=$(cd "$REPO_ARG" && pwd -P); else TARGET=$(pwd -P); fi

norm() { printf '%s' "$1" | tr '\\' '/' | tr 'A-Z' 'a-z' | sed -e 's#^/\([a-z]\)/#\1:/#' -e 's#/*$##'; }

IS_REPO=false
if [ "$(git -C "$TARGET" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]; then IS_REPO=true; fi
TOPLEVEL=""
[ "$IS_REPO" = true ] && TOPLEVEL=$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)

echo "target: $TARGET"
echo "git 判定: is_git=$IS_REPO  toplevel=${TOPLEVEL:--}"

# JSON 引擎：按"能否执行"探测（本机 python3/python 可能是 Store 存根）
PY=""
for cand in "${ATTENTION_EVAL_PYTHON:-}" python3 python py; do
  [ -z "$cand" ] && continue
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'print(1)' >/dev/null 2>&1; then PY="$cand"; break; fi
done
# 本机 python3/python 常是 Microsoft Store 别名存根（存在但执行即失败）：再扫常见安装位置
if [ -z "$PY" ]; then
  for p in /c/Users/*/AppData/Roaming/uv/python/*/python.exe /c/Python*/python.exe; do
    [ -x "$p" ] || continue
    if "$p" -c 'print(1)' >/dev/null 2>&1; then PY="$p"; break; fi
  done
fi
[ -n "$PY" ] && echo "[info] JSON 引擎: $PY"

# pwsh 探测：按能否执行
PWSH=""
if command -v pwsh >/dev/null 2>&1 && pwsh -NoProfile -c 'echo ok' >/dev/null 2>&1; then PWSH=pwsh; fi
[ -z "$PWSH" ] && echo "[warn] pwsh 不可用：.ps1 侧记为 SKIP（不算通过）"

to_posix() { printf '%s' "$1" | sed -e 's#\\#/#g' -e 's#^\([A-Za-z]\):#/\L\1#'; }

# pwsh 只认 Windows 形式路径（POSIX 的 /d/... 会被它当成本地盘符下的相对路径）
to_win() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"
  else printf '%s' "$1" | sed -e 's#^/\([a-z]\)/#\1:/#' -e 's#/#\\#g'; fi
}
NAMES="git_state_snapshot branch_cleanup_audit version_consistency_audit core_docs_relevance_scan next_steps_analysis"
pass=0; fail=0; skip=0

check_one() { # $1=label $2=json $3=exit
  label="$1"; out="$2"; code="$3"; reason=""
  if [ -n "$PY" ]; then
    parsed=$(printf '%s' "$out" | PYTHONIOENCODING=utf-8 "$PY" -c 'import json,sys
try:
    # 必须走 buffer + 显式 utf-8：本机 sys.stdin 默认按 GBK 解码，会把 UTF-8 的 JSON 解坏
    d=json.loads(sys.stdin.buffer.read().decode("utf-8"))
except Exception:
    print("__INVALID__"); raise SystemExit
print("%s\t%s\t%s" % (str(d.get("is_git")).lower(), d.get("repo_root") or "", "1" if ("error" in d and d["error"]) else ""))' 2>/dev/null)
    if [ -z "$parsed" ] || [ "$parsed" = "__INVALID__" ]; then reason="非法 JSON"; fi
  else
    # 无解析器：结构检查（best-effort）+ sed 取值
    compact=$(printf '%s' "$out" | tr -d '\r' | tr '\n' ' ' | tr -s ' ')
    case "$compact" in
      \{*\}) : ;;
      *) reason="非法 JSON（结构检查）" ;;
    esac
    g=$(printf '%s' "$compact" | sed -n 's/.*"is_git"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')
    r=$(printf '%s' "$compact" | sed -n 's/.*"repo_root"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    e=$(printf '%s' "$compact" | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    parsed=$(printf '%s\t%s\t%s' "$g" "$r" "$e")
  fi
  if [ -z "$reason" ]; then
    g=$(printf '%s' "$parsed" | cut -f1); r=$(printf '%s' "$parsed" | cut -f2); e=$(printf '%s' "$parsed" | cut -f3)
    if [ -z "$g" ] || [ "$g" = "none" ]; then reason="缺 is_git 字段"
    elif [ "$g" != "$IS_REPO" ]; then reason="is_git=$g 与事实($IS_REPO) 不一致"
    elif [ "$IS_REPO" = true ] && [ -n "$r" ] && [ "$(norm "$r")" != "$(norm "$TOPLEVEL")" ]; then reason="repo_root=$r 与 git toplevel($TOPLEVEL) 不一致（疑似分析了别的仓库）"
    elif [ "$IS_REPO" = false ] && [ -z "$e" ]; then reason="非 git 目录但缺 error 字段"
    elif [ "$code" != "0" ]; then reason="退出码 $code（应恒为 0）"
    fi
  fi
  if [ -n "$reason" ]; then printf '[FAIL] %s — %s\n' "$label" "$reason"; fail=$((fail+1))
  else printf '[OK]   %s\n' "$label"; pass=$((pass+1)); fi
}

for impl in sh ps1; do
  for n in $NAMES; do
    label="$n ($impl)"
    if [ "$impl" = ps1 ] && [ -z "$PWSH" ]; then echo "[SKIP] $label"; skip=$((skip+1)); continue; fi
    if [ "$impl" = sh ]; then
      out=$(bash "$BASE/$n.sh" --repo "$TARGET" 2>/dev/null); code=$?
    else
      out=$("$PWSH" -NoProfile -File "$(to_win "$BASE/$n.ps1")" --repo "$(to_win "$TARGET")" 2>/dev/null); code=$?
    fi
    check_one "$label" "$out" "$code"
  done
done

echo "smoke_test: $pass passed, $fail failed, $skip skipped (repo: $TARGET)"
[ "$fail" -gt 0 ] && exit 1
exit 0
