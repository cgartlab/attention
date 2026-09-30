#!/usr/bin/env bash
# Audit version-bearing files for consistency (read-only). Contract: references/scan-recipes.md §3.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then echo "Usage: bash version_consistency_audit.sh [--repo <path>] [--defaultBranch <name>]"; echo "Read-only: version files, consistency, release involvement."; exit 0; fi
[ -n "$REPO" ] && cd "$REPO"
git_ok rev-parse --is-inside-work-tree || not_git
[ -z "$DEFAULT" ] && DEFAULT=$(detect_default)

changed=$(changed_set "$DEFAULT" | norm_changed)
changed_arr=()
while IFS= read -r c; do [ -n "$c" ] && changed_arr+=("$c"); done <<< "$changed"

normpath() { printf '%s' "$1" | sed 's|\\|/|g' | sed 's|^\./||'; }
vf_out="["; vf_sep=""; versions=""; vf_paths=""
add_vf() { local f="$1" eco="$2" v="$3"; [ -n "$v" ] || return; local np; np=$(normpath "$f"); vf_out+="${vf_sep}{\"file\":\"$(jes "$np")\",\"ecosystem\":\"$eco\",\"version\":\"$(jes "$v")\"}"; vf_sep=","; versions+="$v"$'\n'; vf_paths+="$np"$'\n'; }

# 按名找版本文件；pattern 加引号，使 *.csproj 这类通配符原样传给 find（不被 bash 预先展开）
find_versions() { find . -type f -name "$1" -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/__pycache__/*' -not -path '*/obj/*' -not -path '*/bin/*' 2>/dev/null; }

while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -m1 -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null | sed -E 's/.*"([^"]*)"$/\1/')
  add_vf "$f" node "$v"
done < <(find_versions 'package.json')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -m1 -E '^[[:space:]]*version[[:space:]]*=[[:space:]]*"' "$f" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
  add_vf "$f" rust "$v"
done < <(find_versions 'Cargo.toml')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -m1 -E '^[[:space:]]*version[[:space:]]*=[[:space:]]*"' "$f" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
  add_vf "$f" python "$v"
done < <(find_versions 'pyproject.toml')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -oE 'version[[:space:]]*=[[:space:]]*"[^"]+"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  add_vf "$f" python "$v"
done < <(find_versions 'setup.py')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -oE '<version>[^<]+</version>' "$f" 2>/dev/null | head -1 | sed -E 's/<\/?version>//g')
  add_vf "$f" jvm "$v"
done < <(find_versions 'pom.xml')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -E '^version[[:space:]]*=[[:space:]]*' "$f" 2>/dev/null | head -1 | sed -E 's/^version[[:space:]]*=[[:space:]]*//')
  add_vf "$f" jvm "$v"
done < <(find_versions 'gradle.properties')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -oE '<Version>[^<]+</Version>' "$f" 2>/dev/null | head -1 | sed -E 's/<\/?Version>//g')
  [ -z "$v" ] && v=$(grep -oE '<PackageVersion>[^<]+</PackageVersion>' "$f" 2>/dev/null | head -1 | sed -E 's/<\/?PackageVersion>//g')
  add_vf "$f" dotnet "$v"
done < <(find_versions '*.csproj')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -oE '\.version[[:space:]]*=[[:space:]]*"[^"]+"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  add_vf "$f" ruby "$v"
done < <(find_versions '*.gemspec')
vf_out+="]"

go_mod_present=false; find . -type f -name 'go.mod' -not -path '*/.git/*' 2>/dev/null | grep -q . && go_mod_present=true

distinct=$(printf '%s' "$versions" | awk 'NF' | sort -u)
distinct_count=$(printf '%s\n' "$distinct" | grep -c . )
consistent=true; [ "$distinct_count" -gt 1 ] && consistent=false
distinct_json=$(printf '%s\n' "$distinct" | jarr_str)

# release_involved：用首次扫描收集的版本文件路径 × 变更集内联计算（不再重复扫描）
release_involved=false
check_rel() {
  local fp="$1" fb; fb=$(basename "$fp"); local c cb
  for c in "${changed_arr[@]:-}"; do
    [ -z "$c" ] && continue
    cb=$(basename "$c")
    if [[ "$fp" == *"$c" ]] || [[ "$c" == *"$fp" ]] || [ "$cb" = "$fb" ]; then release_involved=true; return; fi
  done
}
while IFS= read -r fp; do
  [ -z "$fp" ] && continue
  check_rel "$fp"
  [ "$release_involved" = true ] && break
done <<< "$vf_paths"

changed_json=$(printf '%s\n' "$changed" | jarr_str)
printf '{"is_git":true,"version_files":%s,"distinct_versions":%s,"consistent":%s,"go_mod_present":%s,"release_involved":%s,"changed_files":%s}\n' \
  "$vf_out" "$distinct_json" "$consistent" "$go_mod_present" "$release_involved" "$changed_json"