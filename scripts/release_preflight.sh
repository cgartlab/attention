#!/usr/bin/env bash
# 发布前自检（preflight）——与 scripts/release_preflight.ps1 成对，判据一致。
# 只读：不改文件、不提交、不打 tag、不推送；失败即退出 1。
# 用法: bash scripts/release_preflight.sh [--repo <path>] [--skip-tests] [--allow-default-branch]
set -u

REPO=""; SKIP_TESTS=0; ALLOW_DEFAULT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) if [ $# -ge 2 ]; then REPO="$2"; shift 2; else echo "[FAIL] --repo 缺少取值"; exit 1; fi ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --allow-default-branch) ALLOW_DEFAULT=1; shift ;;
    --help|-h)
      echo "Usage: bash release_preflight.sh [--repo <path>] [--skip-tests] [--allow-default-branch]"
      echo "只读的发布前自检：工作区/分支/版本一致性/CHANGELOG/三层校验/冒烟。失败即退出 1。"
      exit 0 ;;
    *) shift ;;
  esac
done

if [ -n "$REPO" ]; then
  if [ ! -d "$REPO" ]; then echo "[FAIL] --repo path not found: $REPO"; exit 1; fi
  cd "$REPO" || exit 1
fi
BASE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$BASE/.." && pwd)

PY=""
for cand in "${ATTENTION_EVAL_PYTHON:-}" python3 python; do
  [ -z "$cand" ] && continue
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'print(1)' >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
  for p in /c/Users/*/AppData/Roaming/uv/python/*/python.exe /usr/bin/python3 /usr/local/bin/python3; do
    [ -x "$p" ] || continue
    if "$p" -c 'print(1)' >/dev/null 2>&1; then PY="$p"; break; fi
  done
fi

pass=0; fail=0
check() { # $1=name $2=0/1 $3=detail
  if [ "$2" = "0" ]; then printf '[OK]   %s %s\n' "$1" "${3:+— $3}"; pass=$((pass+1))
  else printf '[FAIL] %s %s\n' "$1" "${3:+— $3}"; fail=$((fail+1)); fi
}

# 1) 工作区干净
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$dirty" = "0" ]; then check "工作区干净" 0 ""; else check "工作区干净" 1 "$dirty 处改动未提交（发布前必须先提交）"; fi

# 2) 分支
branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
# 默认分支：按契约梯子（origin/HEAD → 本地 main/master/develop/trunk），**不要**用 init.defaultBranch
default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
if [ -z "$default" ]; then
  for b in main master develop trunk; do
    if git show-ref --verify --quiet "refs/heads/$b"; then default="$b"; break; fi
  done
fi
[ -z "$default" ] && default=main
if [ "$branch" = "$default" ] && [ "$ALLOW_DEFAULT" != "1" ]; then
  check "分支状态" 1 "当前在默认分支 $default（发版建议走 PR；确要在此发版请加 --allow-default-branch）"
else
  check "分支状态" 0 "当前 ${branch:--}（默认分支 $default）"
fi

# 3) 版本一致性
vraw=$(bash "$BASE/version_consistency_audit.sh" --repo "$ROOT" 2>/dev/null)
if [ -n "$PY" ] && [ -n "$vraw" ]; then
  vout=$(printf '%s' "$vraw" | PYTHONIOENCODING=utf-8 "$PY" -c 'import json,sys
d=json.loads(sys.stdin.buffer.read().decode("utf-8"))
c=d.get("consistent")
print("%s\t%s" % ("null" if c is None else str(c).lower(), ",".join("%s=%s" % (f.get("file"), f.get("version")) for f in (d.get("version_files") or []))))' 2>/dev/null)
  cons=$(printf '%s' "$vout" | cut -f1); files=$(printf '%s' "$vout" | cut -f2)
  case "$cons" in
    true)  check "版本一致性" 0 "consistent=true；files=[$files]" ;;
    false) check "版本一致性" 1 "consistent=false：$files（发布前必须一致）" ;;
    *)     check "版本一致性" 1 "consistent=null（无版本文件 → 无从判定，不算通过）；files=[$files]" ;;
  esac
else
  check "版本一致性" 1 "无可用 JSON 解析器（设 ATTENTION_EVAL_PYTHON）或无输出 → 无从判定"
fi

# 4) CHANGELOG [Unreleased]
if [ -f CHANGELOG.md ]; then
  if grep -q '^## \[Unreleased\]' CHANGELOG.md; then
    cnt=$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f && /^- /{c++} END{print c+0}' CHANGELOG.md)
    if [ "$cnt" -gt 0 ]; then check "CHANGELOG [Unreleased] 就绪" 0 "$cnt 条待发布条目"; else check "CHANGELOG [Unreleased] 就绪" 1 '[Unreleased] 存在但没有条目'; fi
  else
    check "CHANGELOG [Unreleased] 就绪" 1 '找不到 [Unreleased] 段'
  fi
else
  check "CHANGELOG [Unreleased] 就绪" 1 'CHANGELOG.md 不存在'
fi

# 5) 三层校验 + 6) 冒烟
if [ "$SKIP_TESTS" = "1" ]; then
  echo '[SKIP] 三层校验（--skip-tests）'; echo '[SKIP] 冒烟（--skip-tests）'
else
  tmp="${TMPDIR:-/tmp}/attention-preflight-$$"
  ev=$(bash "$ROOT/evals/run_evals.sh" --fixtures-dir "$tmp" --no-write 2>&1); evc=$?
  line=$(printf '%s' "$ev" | grep -E '^checks:' | tail -1)
  check "三层校验（严格 JSON + parity + 断言表）" "$([ $evc -eq 0 ] && echo 0 || echo 1)" "$line"
  sm=$(bash "$BASE/smoke_test.sh" --repo "$ROOT" 2>&1); smc=$?
  sline=$(printf '%s' "$sm" | grep -E 'smoke_test:' | tail -1)
  check "冒烟（双实现语义断言）" "$([ $smc -eq 0 ] && echo 0 || echo 1)" "$sline"
fi

echo ''
echo '================================================================'
echo "release_preflight: $pass passed / $fail failed"
echo '================================================================'
[ "$fail" -gt 0 ] && exit 1
exit 0
