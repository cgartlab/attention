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
vf_out="["; vf_sep=""; versions=""
add_vf() { local f="$1" eco="$2" v="$3"; [ -n "$v" ] || return; vf_out+="${vf_sep}{\"file\":\"$(jes "$(normpath "$f")")\",\"ecosystem\":\"$eco\",\"version\":\"$(jes "$v")\"}"; vf_sep=","; versions+="$v"$'\n'; }

find_versions() { find . -type f $1 -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/__pycache__/*' -not -path '*/obj/*' -not -path '*/bin/*' 2>/dev/null; }

while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -m1 -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null | sed -E 's/.*"([^"]*)"$/\1/')
  add_vf "$f" node "$v"
done < <(find_versions '-name package.json')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -m1 -E '^[[:space:]]*version[[:space:]]*=[[:space:]]*"' "$f" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
  add_vf "$f" rust "$v"
done < <(find_versions '-name Cargo.toml')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -m1 -E '^[[:space:]]*version[[:space:]]*=[[:space:]]*"' "$f" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
  add_vf "$f" python "$v"
done < <(find_versions '-name pyproject.toml')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -oE 'version[[:space:]]*=[[:space:]]*"[^"]+"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  add_vf "$f" python "$v"
done < <(find_versions '-name setup.py')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -oE '<version>[^<]+</version>' "$f" 2>/dev/null | head -1 | sed -E 's/<\/?version>//g')
  add_vf "$f" jvm "$v"
done < <(find_versions '-name pom.xml')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -E '^version[[:space:]]*=[[:space:]]*' "$f" 2>/dev/null | head -1 | sed -E 's/^version[[:space:]]*=[[:space:]]*//')
  add_vf "$f" jvm "$v"
done < <(find_versions '-name gradle.properties')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -oE '<Version>[^<]+</Version>' "$f" 2>/dev/null | head -1 | sed -E 's/<\/?Version>//g')
  [ -z "$v" ] && v=$(grep -oE '<PackageVersion>[^<]+</PackageVersion>' "$f" 2>/dev/null | head -1 | sed -E 's/<\/?PackageVersion>//g')
  add_vf "$f" dotnet "$v"
done < <(find_versions '-name *.csproj')
while IFS= read -r f; do [ -n "$f" ] || continue
  v=$(grep -oE '\.version[[:space:]]*=[[:space:]]*"[^"]+"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  add_vf "$f" ruby "$v"
done < <(find_versions '-name *.gemspec')
vf_out+="]"

go_mod_present=false; find . -type f -name go.mod -not -path '*/.git/*' 2>/dev/null | grep -q . && go_mod_present=true

distinct=$(printf '%s' "$versions" | awk 'NF' | sort -u)
distinct_count=$(printf '%s\n' "$distinct" | grep -c . )
consistent=true; [ "$distinct_count" -gt 1 ] && consistent=false
distinct_json=$(printf '%s\n' "$distinct" | jarr_str)

release_involved=false
check_rel() {
  local fp="$1" fb; fb=$(basename "$fp"); local c cb
  for c in "${changed_arr[@]:-}"; do
    [ -z "$c" ] && continue
    cb=$(basename "$c")
    if [[ "$fp" == *"$c" ]] || [[ "$c" == *"$fp" ]] || [ "$cb" = "$fb" ]; then release_involved=true; return; fi
  done
}
# re-scan version files to test release involvement (paths normalized relative)
for spec in 'package.json:node' 'Cargo.toml:rust' 'pyproject.toml:python' 'setup.py:python' 'pom.xml:jvm' 'gradle.properties:jvm' '*.csproj:dotnet' '*.gemspec:ruby'; do
  pat=${spec%%:*}
  while IFS= read -r f; do [ -n "$f" ] || continue
    v=$(grep -m1 -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null)  # presence proxy
    # only count as version file if it actually has a version (any extraction non-empty)
    hasv=false
    case "$pat" in
      package.json) grep -q '"version"' "$f" 2>/dev/null && hasv=true;;
      Cargo.toml|pyproject.toml) grep -qE '^[[:space:]]*version[[:space:]]*=' "$f" 2>/dev/null && hasv=true;;
      setup.py) grep -qE 'version[[:space:]]*=' "$f" 2>/dev/null && hasv=true;;
      pom.xml) grep -q '<version>' "$f" 2>/dev/null && hasv=true;;
      gradle.properties) grep -qE '^version[[:space:]]*=' "$f" 2>/dev/null && hasv=true;;
      *.csproj) grep -qE '<(Package)?Version>' "$f" 2>/dev/null && hasv=true;;
      *.gemspec) grep -qE '\.version[[:space:]]*=' "$f" 2>/dev/null && hasv=true;;
    esac
    [ "$hasv" = true ] && check_rel "$(normpath "$f")"
    [ "$release_involved" = true ] && break
  done < <(find_versions "-name $pat")
  [ "$release_involved" = true ] && break
done

changed_json=$(printf '%s\n' "$changed" | jarr_str)
printf '{"is_git":true,"version_files":%s,"distinct_versions":%s,"consistent":%s,"go_mod_present":%s,"release_involved":%s,"changed_files":%s}\n' \
  "$vf_out" "$distinct_json" "$consistent" "$go_mod_present" "$release_involved" "$changed_json"