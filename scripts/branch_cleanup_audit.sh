#!/usr/bin/env bash
# Audit branches for cleanup candidates (read-only). Contract: references/scan-recipes.md §2.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then
  cat <<'USAGE'
Usage: bash branch_cleanup_audit.sh [--repo <path>] [--defaultBranch <name>] [--help]

Read-only audit of branch cleanup candidates as a single JSON object. Lists only;
it never deletes anything.

Options:
  --repo <path>            Repository path (default: current directory). Must exist
                           and be a directory, otherwise prints
                           {"is_git":false,"error":"repo path not found"} and exits 0.
  --defaultBranch <name>   Override the auto-detected default branch.
  --help, -h               Print this usage and exit 0.

Fields: is_git, default_branch, default_branch_source, current_branch,
remote_reachable, protected, local_merged_candidates,
local_stale_unmerged_report, remote_merged_candidates, warnings.
USAGE
  exit 0
fi
check_repo
git_ok rev-parse --is-inside-work-tree || not_git
enter_root

warns=""
warn_add() { warns+="$1"$'\n'; }

resolve_default

current=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)

# 受保护名单：内置 ∪ release/* 通配 ∪ 当前分支 ∪ 默认分支，去重后排序
prot_raw="main
master
develop
dev
trunk
prod
production
gh-pages
gh-readonly
release/*"
[ -n "$current" ] && prot_raw+=$'\n'"$current"
[ -n "$DEFAULT" ] && prot_raw+=$'\n'"$DEFAULT"
protected=$(printf '%s\n' "$prot_raw" | awk 'NF' | sort -u)

is_protected() {
  case "$1" in release/*) return 0;; esac
  printf '%s\n' "$protected" | grep -Fxq -- "$1"
}

locals=$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | awk 'NF' | sort -u)

# 合并基准：优先 origin/<default> 形态（避免本地无同名分支时 unknown revision），
# 回退本地 <default>。两者都取不到 -> 合并判定整体跳过并告警（不假装没有候选）。
merged_base=""
if [ -n "$DEFAULT" ]; then
  if git_ok rev-parse --verify "refs/remotes/origin/$DEFAULT"; then merged_base="origin/$DEFAULT"
  elif git_ok rev-parse --verify "refs/heads/$DEFAULT"; then merged_base="$DEFAULT"
  fi
fi
[ -z "$merged_base" ] && warn_add "default-branch-unavailable"

merged=""; rmerged=""
if [ -n "$merged_base" ]; then
  # 提到循环外（原先每个分支都重跑一次 git branch -r --merged）
  merged=$(git branch --merged "$merged_base" 2>/dev/null | sed 's/^[* ]*//; s/[[:space:]]*$//' | awk 'NF')
  rmerged=$(git branch -r --merged "$merged_base" 2>/dev/null | sed 's/^[* ]*//; s/[[:space:]]*$//' | awk 'NF')
fi
is_merged() { printf '%s\n' "$merged" | grep -Fxq -- "$1"; }
is_rmerged() { printf '%s\n' "$rmerged" | grep -Fxq -- "$1"; }

now_epoch=$(date +%s)
lm_out="["; lm_sep=""; ls_out="["; ls_sep=""
while IFS= read -r b; do
  [ -z "$b" ] && continue
  if is_merged "$b"; then
    if ! is_protected "$b"; then lm_out+="${lm_sep}\"$(jes "$b")\""; lm_sep=","; fi
  else
    dateStr=$(git log -1 --format='%cI' "$b" 2>/dev/null)
    age_days=""
    if [ -n "$dateStr" ]; then
      cdt=$(epoch_of "$dateStr")
      if [ -n "$cdt" ]; then age_days=$(( (now_epoch - cdt) / 86400 )); fi
    fi
    if [ -n "$age_days" ] && [ "$age_days" -gt 30 ] && ! is_protected "$b" && [ "$b" != "$current" ]; then
      ls_out+="${ls_sep}{\"branch\":\"$(jes "$b")\",\"last_commit\":\"$(jes "$dateStr")\",\"age_days\":$age_days}"; ls_sep=","
    fi
  fi
done <<< "$locals"
lm_out+="]"; ls_out+="]"

# 远端可达性：失败即 remote_reachable=false + 告警（不得当成"没有可剪枝的远端分支"）
remote_heads_raw=$(git ls-remote origin 2>/dev/null); ls_rc=$?
remote_reachable=false
if [ $ls_rc -eq 0 ]; then remote_reachable=true; else warn_add "remote-unreachable"; fi
# 精确匹配：无锚定子串会让 refs/heads/feat 误配 refs/heads/feat-x
remote_exists() { printf '%s\n' "$remote_heads_raw" | awk '{print $2}' | grep -Fxq -- "refs/heads/$1"; }

rrefs=$(git for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null | grep -E '^origin/' | grep -v '^origin/HEAD$' | awk 'NF' | sort -u)
rm_out="["; rm_sep=""
while IFS= read -r r; do
  [ -z "$r" ] && continue
  short="${r#origin/}"
  is_protected "$short" && continue
  if [ -n "$rmerged" ] && is_rmerged "$r"; then
    rexists=false; if remote_exists "$short"; then rexists=true; fi
    rm_out+="${rm_sep}{\"branch\":\"$(jes "$short")\",\"tracking_ref\":\"$(jes "$r")\",\"remote_exists\":$rexists}"; rm_sep=","
  fi
done <<< "$rrefs"
rm_out+="]"

printf '{"is_git":true,"default_branch":%s,"default_branch_source":"%s","current_branch":%s,"remote_reachable":%s,"protected":%s,"local_merged_candidates":%s,"local_stale_unmerged_report":%s,"remote_merged_candidates":%s,"warnings":%s}\n' \
  "$(jstr "$DEFAULT")" "$(jes "$DEFAULT_SOURCE")" "$(jstr "$current")" "$remote_reachable" \
  "$(printf '%s\n' "$protected" | jarr_str)" "$lm_out" "$ls_out" "$rm_out" \
  "$(printf '%s\n' "$warns" | jarr_str)"
