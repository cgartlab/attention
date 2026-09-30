#!/usr/bin/env bash
# Smoke-test: run all 5采集 scripts on a repo, verify each emits a single valid-looking JSON line (read-only).
# Stricter than presence: output line must start with {"is_git" and end with }.
REPO=""; HELP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --help|-h) HELP=1; shift;;
    *) shift;;
  esac
done
if [ $HELP -eq 1 ]; then echo "Usage: bash smoke_test.sh [--repo <path>]"; echo "Runs all 5采集 scripts; verifies each emits a JSON line starting {\"is_git\" ending }."; exit 0; fi
[ -n "$REPO" ] && cd "$REPO"
base="$(cd "$(dirname "$0")" && pwd)"
names="git_state_snapshot branch_cleanup_audit version_consistency_audit core_docs_relevance_scan next_steps_analysis"
pass=0; fail=0
for n in $names; do
  out=$(bash "$base/$n.sh" --repo "$PWD" 2>/dev/null)
  if printf '%s\n' "$out" | grep -qE '^\{"is_git".*\}$'; then echo "[OK]   $n"; pass=$((pass+1)); else echo "[FAIL] $n"; fail=$((fail+1)); fi
done
echo "smoke_test: $pass passed, $fail failed (repo: $PWD)"
[ "$fail" -gt 0 ] && exit 1 || exit 0