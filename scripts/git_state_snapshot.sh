#!/usr/bin/env bash
# Snapshot git working-tree state as JSON (read-only). Contract: references/scan-recipes.md §1.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then
  cat <<'USAGE'
Usage: bash git_state_snapshot.sh [--repo <path>] [--defaultBranch <name>] [--help]

Read-only snapshot of one repository as a single JSON object on stdout.

Options:
  --repo <path>            Repository path (default: current directory).
                           Must exist and be a directory, otherwise the script
                           prints {"is_git":false,"error":"repo path not found"}
                           and exits 0 -- it never silently falls back to the
                           current directory.
  --defaultBranch <name>   Override the auto-detected default branch.
  --help, -h               Print this usage and exit 0.

Fields: is_git, repo_root, has_remote, remote_host, current_branch, detached,
head_short, upstream, ahead, behind, default_branch, default_branch_source,
staged, unstaged, untracked, stash_count, recent_changed_files,
unpushed_commits, unpushed_branches, warnings.
Never mutates the repository.
USAGE
  exit 0
fi
check_repo
git_ok rev-parse --is-inside-work-tree || not_git
enter_root

warns=""
warn_add() { warns+="$1"$'\n'; }

root=$(git rev-parse --show-toplevel 2>/dev/null)
branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
detached=false; [ -z "$branch" ] && detached=true

head_short=$(git rev-parse --short HEAD 2>/dev/null)
[ -z "$head_short" ] && warn_add "head-unborn"

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
[ "$upstream" = "HEAD" ] && upstream=""

ahead="null"; behind="null"
if [ -n "$upstream" ]; then
  counts=$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
  if [ -n "$counts" ]; then
    behind=$(printf '%s' "$counts" | awk '{print $1}')
    ahead=$(printf '%s' "$counts" | awk '{print $2}')
  fi
fi

# 远端主机：origin 优先，否则第一个 remote（契约 §1）
has_remote=false; remote_host=""
remotes=$(git remote 2>/dev/null)
if [ -n "$remotes" ]; then
  has_remote=true
  url=$(git remote get-url origin 2>/dev/null)
  if [ -z "$url" ]; then
    first=$(printf '%s\n' "$remotes" | head -1)
    url=$(git remote get-url "$first" 2>/dev/null)
  fi
  remote_host=$(host_of_url "$url")
fi

resolve_default

staged=$(git diff --cached --name-only --no-renames -z 2>/dev/null | z2nl | norm_changed | jarr_str)
unstaged=$(git diff --name-only --no-renames -z 2>/dev/null | z2nl | norm_changed | jarr_str)
untracked=$(git ls-files --others --exclude-standard -z 2>/dev/null | z2nl | norm_changed | jarr_str)
stash_count=$(git stash list 2>/dev/null | grep -c . )
[ -z "$stash_count" ] && stash_count=0

# 近期变更文件：n = min(10, 第一父链提交数-1)。n==0（仅根提交）时回退 `git show --name-only HEAD`。
# 必须 --first-parent：rev-list --count 会计入侧分支提交，而 HEAD~n 只走第一父链（审计发现）。
recent="[]"
cc=$(git rev-list --count --first-parent HEAD 2>/dev/null)
if [ -n "$cc" ] && [ "$cc" -gt 0 ] 2>/dev/null; then
  n=$((cc - 1)); [ "$n" -gt 10 ] && n=10
  if [ "$cc" -eq 1 ]; then
    recent=$(git show --name-only --format= -z HEAD 2>/dev/null | z2nl | norm_changed | jarr_str)
  else
    recent=$(git diff --name-only --no-renames -z "HEAD~$n..HEAD" 2>/dev/null | z2nl | norm_changed | jarr_str)
  fi
fi

# 未推送提交：origin/<default> 优先，其次 upstream；两者都不存在 -> null。
# null 有两种语义，必须靠 has_remote 区分：has_remote=false -> **不适用**（没有远程可推，
# 加 no-remote 警告）；has_remote=true 但取不到可比 ref -> **不可判定**。不得输出 []。
if [ "$has_remote" = false ]; then warn_add "no-remote"; fi
unpushed="null"
range=""
if [ -n "$DEFAULT" ] && git_ok rev-parse --verify "refs/remotes/origin/$DEFAULT"; then
  range="origin/$DEFAULT..HEAD"
elif [ -n "$upstream" ] && git_ok rev-parse --verify "$upstream"; then
  range="$upstream..HEAD"
fi
if [ -n "$range" ]; then
  unpushed=$(git log --oneline "$range" 2>/dev/null | jarr_str)
fi

# 未推送分支：tip 不被任何 refs/remotes/* 覆盖的本地分支。
# **has_remote=false 时必须输出 []**：没有远程就没有「未推送分支」这一概念。
# 否则一个完全干净的纯本地仓库会输出 ["main"]，配合判定条款会被判成脏态，
# 进而去尝试推送一个不存在的远程（实测本仓库即如此）。
unpushed_branches="[]"
if [ "$has_remote" = true ]; then
  unpushed_shas=$(git rev-list --branches --not --remotes 2>/dev/null)
  ub_raw=""
  while IFS=' ' read -r sha name; do
    [ -z "$name" ] && continue
    if printf '%s\n' "$unpushed_shas" | grep -Fxq -- "$sha"; then ub_raw+="$name"$'\n'; fi
  done <<< "$(git for-each-ref --format='%(objectname) %(refname:short)' refs/heads 2>/dev/null)"
  unpushed_branches=$(printf '%s\n' "$ub_raw" | sort -u | jarr_str)
fi

printf '{"is_git":true,"repo_root":%s,"has_remote":%s,"remote_host":%s,"current_branch":%s,"detached":%s,"head_short":%s,"upstream":%s,"ahead":%s,"behind":%s,"default_branch":%s,"default_branch_source":%s,"staged":%s,"unstaged":%s,"untracked":%s,"stash_count":%s,"recent_changed_files":%s,"unpushed_commits":%s,"unpushed_branches":%s,"warnings":%s}\n' \
  "$(jstr "$root")" "$has_remote" "$(jstr "$remote_host")" "$(jstr "$branch")" "$detached" \
  "$(jstr "$head_short")" "$(jstr "$upstream")" "$ahead" "$behind" "$(jstr "$DEFAULT")" \
  "\"$(jes "$DEFAULT_SOURCE")\"" "$staged" "$unstaged" "$untracked" "$stash_count" "$recent" \
  "$unpushed" "$unpushed_branches" "$(printf '%s\n' "$warns" | jarr_str)"
