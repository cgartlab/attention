#!/usr/bin/env bash
# Scan core docs for references to changed source files (read-only). Contract: references/scan-recipes.md §4.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then
  cat <<'USAGE'
Usage: bash core_docs_relevance_scan.sh [--repo <path>] [--defaultBranch <name>] [--help]

Read-only scan of core docs against the change set, printed as one JSON object.
This is a LOW-PRECISION hint, not a verdict on whether docs need updating.

Options:
  --repo <path>            Repository path (default: current directory). Must exist and
                           be a directory, otherwise prints
                           {"is_git":false,"error":"repo path not found"} and exits 0.
  --defaultBranch <name>   Override the auto-detected default branch.
  --help, -h               Print this usage and exit 0.

Fields: is_git, core_docs, changed_files, changed_basenames, docs_mentioning_changes,
docs_stale_candidates, warnings.
USAGE
  exit 0
fi
check_repo
git_ok rev-parse --is-inside-work-tree || not_git
enter_root
resolve_default

changed=$(changed_raw "$DEFAULT" | norm_changed | sort -u)
changed_basenames=$(printf '%s\n' "$changed" | awk -F/ 'NF { print $NF }' | awk 'NF' | sort -u)

# 核心文档：顶层普通文件（前缀匹配，区分大小写）+ docs/**/*.md（排序后前 50 个）
core_raw=""
for f in *; do
  [ -f "$f" ] || continue
  case "$f" in
    README*|CHANGELOG*|CHANGES*|HISTORY*|CONTRIBUTING*|LICENSE*|AGENTS*|CLAUDE*) core_raw+="$f"$'\n';;
  esac
done
if [ -d docs ]; then
  docs_list=$(find docs -type f -name '*.md' 2>/dev/null | sed 's|\\|/|g' | tr -d '\r' | awk 'NF' | sort -u | head -50)
  core_raw+="$docs_list"$'\n'
fi
core_docs=$(printf '%s\n' "$core_raw" | awk 'NF' | sort -u)

cd_out="["; cd_sep=""; mention_out="["; mention_sep=""; stale_raw=""
while IFS= read -r doc; do
  [ -z "$doc" ] && continue
  exists=false; [ -f "$doc" ] && exists=true
  cd_out+="${cd_sep}{\"file\":\"$(jes "$doc")\",\"exists\":$exists}"; cd_sep=","
  [ "$exists" = true ] || continue
  refs_out="["; refs_sep=""; has_ref=0
  while IFS= read -r bn; do
    [ -z "$bn" ] && continue
    # 字面匹配、不区分大小写（grep -F -i；-e 防止 basename 以 - 开头）
    if grep -Fqi -e "$bn" "$doc" 2>/dev/null; then
      refs_out+="${refs_sep}\"$(jes "$bn")\""; refs_sep=","; has_ref=1
    fi
  done <<< "$changed_basenames"
  refs_out+="]"
  if [ $has_ref -eq 1 ]; then
    mention_out+="${mention_sep}{\"doc\":\"$(jes "$doc")\",\"references\":$refs_out}"; mention_sep=","
  elif [ -n "$changed" ] && ! printf '%s\n' "$changed" | grep -Fxq -- "$doc"; then
    # 未出现在变更集、也没提到任何变更文件的核心文档 -> 请人工确认是否需要更新。
    # **变更集为空时必须输出 []**：什么都没改就谈不上「陈旧」（否则会把全部核心文档
    # 都列出来，等于对着一个干净仓库刷十几条无意义提示）。
    stale_raw+="$doc"$'\n'
  fi
done <<< "$core_docs"
cd_out+="]"; mention_out+="]"
docs_stale=$(printf '%s\n' "$stale_raw" | awk 'NF' | sort -u)

printf '{"is_git":true,"core_docs":%s,"changed_files":%s,"changed_basenames":%s,"docs_mentioning_changes":%s,"docs_stale_candidates":%s,"warnings":[]}\n' \
  "$cd_out" "$(printf '%s\n' "$changed" | jarr_str)" "$(printf '%s\n' "$changed_basenames" | jarr_str)" \
  "$mention_out" "$(printf '%s\n' "$docs_stale" | jarr_str)"
