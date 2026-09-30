#!/usr/bin/env bash
# Gather signals for next-step suggestions (read-only). Contract: references/scan-recipes.md §5.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then echo "Usage: bash next_steps_analysis.sh [--repo <path>]"; echo "Read-only signals: recent commits, issues/PRs, TODOs, branches, test commands."; exit 0; fi
[ -n "$REPO" ] && cd "$REPO"
git_ok rev-parse --is-inside-work-tree || not_git

recent_commits=$(git log --oneline -n 15 2>/dev/null | jarr_str)

remote=$(git remote -v 2>/dev/null)
is_github=false; printf '%s\n' "$remote" | grep -q 'github\.com' && is_github=true
gh_authed=false; command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && gh_authed=true

issues="[]"; prs="[]"
if [ "$is_github" = true ] && [ "$gh_authed" = true ]; then
  issues=$(gh issue list --state open --limit 20 2>/dev/null | jarr_str)
  prs=$(gh pr list --state open --limit 20 2>/dev/null | jarr_str)
fi

todos=$(git grep -n -E 'TODO|FIXME|XXX|HACK' -- . ':(exclude)*.md' ':(exclude)*.markdown' ':(exclude)*.json' ':(exclude)*.txt' ':(exclude)*.rst' ':(exclude)scripts/next_steps_analysis.ps1' ':(exclude)scripts/next_steps_analysis.sh' 2>/dev/null | head -30 | jarr_str)

branches_out="["; b_sep=""
while IFS=$'\t' read -r b d; do
  [ -z "$b" ] && continue
  branches_out+="${b_sep}{\"branch\":\"$(jes "$b")\",\"last_commit\":\"$(jes "$d")\"}"; b_sep=","
done < <(git for-each-ref --format='%(refname:short)%09%(committerdate:iso-strict)' refs/heads 2>/dev/null)
branches_out+="]"

tc_out="["; tc_sep=""
if [ -f package.json ]; then
  for k in test lint build check typecheck format; do
    s=$(grep -m1 -o "\"$k\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" package.json 2>/dev/null | sed -E "s/.*:[[:space:]]*\"([^\"]*)\".*/\1/")
    if [ -n "$s" ]; then tc_out+="${tc_sep}{\"name\":\"$k\",\"script\":\"$(jes "$s")\"}"; tc_sep=","; fi
  done
fi
if [ -f Makefile ]; then
  for t in test lint build check; do
    if grep -Eq "^$t[[:space:]]*:" Makefile; then tc_out+="${tc_sep}{\"name\":\"$t\",\"script\":\"make $t\"}"; tc_sep=","; fi
  done
fi
if [ -f pyproject.toml ]; then
  for t in pytest ruff mypy; do
    if grep -q "$t" pyproject.toml 2>/dev/null; then tc_out+="${tc_sep}{\"name\":\"$t\",\"script\":\"$t\"}"; tc_sep=","; fi
  done
fi
tc_out+="]"

default=$(detect_default)
behind="null"
if [ -n "$default" ]; then od="origin/$default"
  if git_ok rev-parse --verify "refs/remotes/$od"; then cnt=$(git rev-list --count "$od..HEAD" 2>/dev/null); [ -n "$cnt" ] && [ "$cnt" -eq "$cnt" ] 2>/dev/null && behind="$cnt"; fi
fi
dj="null"; [ -n "$default" ] && dj="\"$(jes "$default")\""
printf '{"is_git":true,"default_branch":%s,"behind_default":%s,"recent_commits":%s,"is_github":%s,"gh_authed":%s,"open_issues":%s,"open_prs":%s,"todo_fixme":%s,"branches":%s,"test_commands":%s}\n' \
  "$dj" "$behind" "$recent_commits" "$is_github" "$gh_authed" "$issues" "$prs" "$todos" "$branches_out" "$tc_out"