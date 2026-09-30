#!/usr/bin/env bash
# Gather signals for next-step development suggestions (read-only). Contract: references/scan-recipes.md §5.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then
  cat <<'USAGE'
Usage: bash next_steps_analysis.sh [--repo <path>] [--defaultBranch <name>] [--help]

Read-only signal collection for next-step suggestions, as one JSON object.

Options:
  --repo <path>            Repository path (default: current directory). Must exist and
                           be a directory, otherwise prints
                           {"is_git":false,"error":"repo path not found"} and exits 0.
  --defaultBranch <name>   Override the auto-detected default branch (used for
                           behind_default).
  --help, -h               Print this usage and exit 0.

Fields: is_git, default_branch, behind_default, recent_commits, is_github,
remote_url_masked, gh_authed, gh_query_state, open_issues, open_prs, todo_fixme,
branches, test_commands, missing_core_docs, warnings.
USAGE
  exit 0
fi
check_repo
git_ok rev-parse --is-inside-work-tree || not_git
enter_root
resolve_default

warns=""
warn_add() { warns+="$1"$'\n'; }

recent_commits=$(git log --oneline -n 15 2>/dev/null | awk 'NF' | jarr_str)

# 远端 host 判定按主机名（不得对整条 URL 子串匹配：路径含 github.com 的自建 GitLab 会被误判）
remote_line=$(git remote -v 2>/dev/null | awk 'NR==1')
remote_url=""
[ -n "$remote_line" ] && remote_url=$(printf '%s' "$remote_line" | awk '{print $2}')
host=$(host_of_url "$remote_url")
is_github=false
case "$host" in
  github.com|*.github.com) is_github=true;;
esac
remote_url_masked="null"
[ -n "$remote_url" ] && remote_url_masked="\"$(jes "$(mask_url "$remote_url")")\""

gh_authed=false; gh_hosts=""
if command -v gh >/dev/null 2>&1; then
  gh_status=$(gh auth status 2>&1); gh_rc=$?
  if [ $gh_rc -eq 0 ]; then gh_authed=true; fi
  gh_hosts=$(printf '%s\n' "$gh_status" | grep -oE 'Logged in to [A-Za-z0-9._-]+' 2>/dev/null | awk '{print $4}' | sort -u)
fi
if [ "$gh_authed" = true ] && [ -n "$host" ] && [ -n "$gh_hosts" ]; then
  printf '%s\n' "$gh_hosts" | grep -Fxq -- "$host" || warn_add "gh-host-mismatch"
fi

# 查询失败 -> null + gh-query-failed（绝不输出 []，那会被读成"确实没有开放 issue/PR"）
issues="null"; prs="null"; gh_state="not-applicable"
if [ "$is_github" = true ] && [ "$gh_authed" = true ]; then
  iout=$(gh issue list --state open --limit 20 2>/dev/null); irc=$?
  pout=$(gh pr list --state open --limit 20 2>/dev/null); prc=$?
  if [ $irc -eq 0 ] && [ $prc -eq 0 ]; then
    gh_state="ok"
    issues=$(printf '%s\n' "$iout" | awk 'NF' | jarr_str)
    prs=$(printf '%s\n' "$pout" | awk 'NF' | jarr_str)
  else
    gh_state="unavailable"
    warn_add "gh-query-failed"
  fi
fi

# --untracked 必须放在 pattern 之前（否则 git 把它当 revision 报 fatal）；
# 排除表按仓库根锚定（:(exclude,top)），--repo 指向子目录时排除依然生效。
tout=$(git grep --untracked -n -E -e 'TODO|FIXME|XXX|HACK' -- . \
  ':(exclude,top)*.md' ':(exclude,top)*.markdown' ':(exclude,top)*.json' ':(exclude,top)*.rst' \
  ':(exclude,top)scripts/next_steps_analysis.ps1' ':(exclude,top)scripts/next_steps_analysis.sh' 2>/dev/null)
grc=$?
[ $grc -gt 1 ] && warn_add "git-grep-failed"
todos=$(printf '%s\n' "$tout" | head -30 | awk 'NF' | jarr_str)

branches_raw=$(git for-each-ref --format='%(refname:short)%09%(committerdate:iso-strict)' refs/heads 2>/dev/null | sort)
branches_out="["; b_sep=""
while IFS=$TAB read -r b d; do
  [ -z "$b" ] && continue
  d=${d%$CR}
  branches_out+="${b_sep}{\"branch\":\"$(jes "$b")\",\"last_commit\":\"$(jes "$d")\"}"; b_sep=","
done <<< "$branches_raw"
branches_out+="]"

tc_out="["; tc_sep=""; tc_names=""
tc_add() {
  [ -n "$1" ] || return 0
  [ -n "$2" ] || return 0
  printf '%s\n' "$tc_names" | grep -Fxq -- "$1" && return 0
  tc_names+="$1"$'\n'
  tc_out+="${tc_sep}{\"name\":\"$(jes "$1")\",\"script\":\"$(jes "$2")\"}"; tc_sep=","
}
if [ -f package.json ]; then
  for k in test lint build check typecheck format; do
    tc_add "$k" "$(json_at package.json "scripts.$k")"
  done
fi
if [ -f Makefile ]; then
  for t in test lint build check; do
    grep -Eq "^$t[[:space:]]*:" Makefile 2>/dev/null && tc_add "$t" "make $t"
  done
fi
if [ -f pyproject.toml ]; then
  for t in pytest ruff mypy; do
    grep -q "$t" pyproject.toml 2>/dev/null && tc_add "$t" "$t"
  done
fi
tc_out+="]"

behind="null"
if [ -n "$DEFAULT" ] && git_ok rev-parse --verify "refs/remotes/origin/$DEFAULT"; then
  cnt=$(git rev-list --count "origin/$DEFAULT..HEAD" 2>/dev/null)
  [ -n "$cnt" ] && behind="$cnt"
fi

# 缺失核心文档：顶层普通文件前缀精确匹配，区分大小写（与 Linux 上 git 行为对齐）
topfiles=""
for f in *; do [ -f "$f" ] && topfiles+="$f"$'\n'; done
missing_raw=""
for e in README CHANGELOG LICENSE AGENTS CONTRIBUTING; do
  n=$(printf '%s\n' "$topfiles" | awk -v p="$e" 'index($0, p) == 1 { c++ } END { print c + 0 }')
  [ "$n" -eq 0 ] && missing_raw+="$e"$'\n'
done

printf '{"is_git":true,"default_branch":%s,"behind_default":%s,"recent_commits":%s,"is_github":%s,"remote_url_masked":%s,"gh_authed":%s,"gh_query_state":"%s","open_issues":%s,"open_prs":%s,"todo_fixme":%s,"branches":%s,"test_commands":%s,"missing_core_docs":%s,"warnings":%s}\n' \
  "$(jstr "$DEFAULT")" "$behind" "$recent_commits" "$is_github" "$remote_url_masked" "$gh_authed" \
  "$gh_state" "$issues" "$prs" "$todos" "$branches_out" "$tc_out" \
  "$(printf '%s\n' "$missing_raw" | awk 'NF' | jarr_str)" "$(printf '%s\n' "$warns" | jarr_str)"
