#!/usr/bin/env bash
# Snapshot git working-tree state as JSON (read-only). Contract: references/scan-recipes.md §1.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then echo "Usage: bash git_state_snapshot.sh [--repo <path>] [--defaultBranch <name>]"; echo "Read-only snapshot; prints one JSON object."; exit 0; fi
[ -n "$REPO" ] && cd "$REPO"
git_ok rev-parse --is-inside-work-tree || not_git

root=$(git rev-parse --show-toplevel 2>/dev/null)
branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
detached=false; [ -z "$branch" ] && detached=true
head_short=$(git rev-parse --short HEAD 2>/dev/null)
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

[ -z "$DEFAULT" ] && DEFAULT=$(detect_default)

staged=$(git diff --cached --name-only --no-renames -z 2>/dev/null | z2nl | jarr_str)
unstaged=$(git diff --name-only --no-renames -z 2>/dev/null | z2nl | jarr_str)
untracked=$(git ls-files --others --exclude-standard -z 2>/dev/null | z2nl | jarr_str)
stash_count=$(git stash list 2>/dev/null | grep -c . )

recent="[]"
cc=$(git rev-list --count HEAD 2>/dev/null)
if [ -n "$cc" ] && [ "$cc" -eq "$cc" ] 2>/dev/null && [ "$cc" -gt 0 ]; then
  n=$cc; [ "$n" -gt 10 ] && n=10
  recent=$(git diff --name-only --no-renames "HEAD~$n..HEAD" 2>/dev/null | jarr_str)
fi

unpushed="[]"
if [ -n "$DEFAULT" ]; then
  od="origin/$DEFAULT"; range=""
  if git_ok rev-parse --verify "refs/remotes/$od"; then range="$od..HEAD"; elif [ -n "$upstream" ]; then range="@{u}..HEAD"; fi
  if [ -n "$range" ]; then unpushed=$(git log --oneline "$range" 2>/dev/null | jarr_str); fi
fi

jstr() { [ -n "$1" ] && printf '"%s"' "$(jes "$1")" || printf 'null'; }
printf '{"is_git":true,"repo_root":%s,"current_branch":%s,"detached":%s,"head_short":%s,"upstream":%s,"ahead":%s,"behind":%s,"default_branch":%s,"staged":%s,"unstaged":%s,"untracked":%s,"stash_count":%s,"recent_changed_files":%s,"unpushed_commits":%s}\n' \
  "$(jstr "$root")" "$(jstr "$branch")" "$detached" "$(jstr "$head_short")" "$(jstr "$upstream")" "$ahead" "$behind" "$(jstr "$DEFAULT")" "$staged" "$unstaged" "$untracked" "$stash_count" "$recent" "$unpushed"