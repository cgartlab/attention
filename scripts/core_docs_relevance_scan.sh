#!/usr/bin/env bash
# Scan core docs for references to changed source files (read-only). Contract: references/scan-recipes.md §4.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then echo "Usage: bash core_docs_relevance_scan.sh [--repo <path>] [--defaultBranch <name>]"; echo "Read-only: core docs list + docs referencing changed files."; exit 0; fi
[ -n "$REPO" ] && cd "$REPO"
git_ok rev-parse --is-inside-work-tree || not_git
[ -z "$DEFAULT" ] && DEFAULT=$(detect_default)

changed=$(changed_set "$DEFAULT" | norm_changed)
changed_basenames=$(printf '%s\n' "$changed" | awk -F/ '{print $NF}' | awk 'NF' | sort -u)

core_docs=""
for f in README* CHANGELOG* CHANGES* HISTORY* CONTRIBUTING* LICENSE* AGENTS* CLAUDE*; do
  [ -f "$f" ] && core_docs+="$f"$'\n'
done
if [ -d docs ]; then
  while IFS= read -r d; do core_docs+="$d"$'\n'; done < <(find docs -type f -name '*.md' 2>/dev/null | head -50)
fi

cd_out="["; cd_sep=""; need_out="["; need_sep=""
while IFS= read -r doc; do
  [ -z "$doc" ] && continue
  exists=false; [ -f "$doc" ] && exists=true
  cd_out+="${cd_sep}{\"file\":\"$(jes "$doc")\",\"exists\":$exists}"; cd_sep=","
  if [ "$exists" = true ]; then
    refs_out="["; refs_sep=""; has_ref=0
    while IFS= read -r bn; do
      [ -z "$bn" ] && continue
      if grep -Fq -- "$bn" "$doc" 2>/dev/null; then refs_out+="${refs_sep}\"$(jes "$bn")\""; refs_sep=","; has_ref=1; fi
    done <<< "$changed_basenames"
    refs_out+="]"
    if [ $has_ref -eq 1 ]; then need_out+="${need_sep}{\"doc\":\"$(jes "$doc")\",\"references\":$refs_out}"; need_sep=","; fi
  fi
done <<< "$core_docs"
cd_out+="]"; need_out+="]"

changed_json=$(printf '%s\n' "$changed" | jarr_str)
basenames_json=$(printf '%s\n' "$changed_basenames" | jarr_str)
printf '{"is_git":true,"core_docs":%s,"changed_files":%s,"changed_basenames":%s,"docs_needing_update":%s}\n' "$cd_out" "$changed_json" "$basenames_json" "$need_out"