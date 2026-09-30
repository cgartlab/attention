#!/usr/bin/env bash
# Audit branches for cleanup candidates (read-only). Contract: references/scan-recipes.md §2.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then echo "Usage: bash branch_cleanup_audit.sh [--repo <path>] [--defaultBranch <name>]"; echo "Read-only audit; prints one JSON object. Does not delete anything."; exit 0; fi
[ -n "$REPO" ] && cd "$REPO"
git_ok rev-parse --is-inside-work-tree || not_git
[ -z "$DEFAULT" ] && DEFAULT=$(detect_default)
[ -z "$DEFAULT" ] && DEFAULT="main"

current=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
protected=("main" "master" "develop" "dev" "trunk" "prod" "production" "gh-pages" "gh-readonly")
[ -n "$current" ] && protected+=("$current")
[ -n "$DEFAULT" ] && protected+=("$DEFAULT")
is_protected() {
  case "$1" in release/*) return 0;; esac
  local p
  for p in "${protected[@]}"; do [ "$p" = "$1" ] && return 0; done
  return 1
}

locals=$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
merged=$(git branch --merged "$DEFAULT" 2>/dev/null | sed 's/^[* ]*//; s/[[:space:]]*$//')
is_merged() { printf '%s\n' "$merged" | grep -Fxq -- "$1"; }

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

remote_heads_raw=$(git ls-remote origin 2>/dev/null)
remote_exists() { printf '%s\n' "$remote_heads_raw" | grep -Fq -- "refs/heads/$1"; }
rrefs=$(git for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null | grep -E '^origin/' | grep -v '^origin/HEAD$')
rmerged=$(git branch -r --merged "$DEFAULT" 2>/dev/null | sed 's/^[* ]*//; s/[[:space:]]*$//')
rm_out="["; rm_sep=""
while IFS= read -r r; do
  [ -z "$r" ] && continue
  short="${r#origin/}"
  case "$short" in 'HEAD ->'*) continue;; esac
  is_protected "$short" && continue
  if printf '%s\n' "$rmerged" | grep -Fxq -- "origin/$short"; then
    rexists=false; if remote_exists "$short"; then rexists=true; fi
    rm_out+="${rm_sep}{\"branch\":\"$(jes "$short")\",\"tracking_ref\":\"$(jes "$r")\",\"remote_exists\":$rexists}"; rm_sep=","
  fi
done <<< "$rrefs"
rm_out+="]"

pjstr() { [ -n "$1" ] && printf '"%s"' "$(jes "$1")" || printf 'null'; }
printf '{"is_git":true,"default_branch":%s,"current_branch":%s,"protected":%s,"local_merged_candidates":%s,"local_stale_unmerged_report":%s,"remote_merged_candidates":%s}\n' \
  "$(pjstr "$DEFAULT")" "$(pjstr "$current")" "$(printf '%s\n' "${protected[@]}" | jarr_str)" "$lm_out" "$ls_out" "$rm_out"