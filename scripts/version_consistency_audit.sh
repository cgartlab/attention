#!/usr/bin/env bash
# Audit version-bearing files for consistency + collect release signals (read-only).
# Contract: references/scan-recipes.md §3.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then
  cat <<'USAGE'
Usage: bash version_consistency_audit.sh [--repo <path>] [--defaultBranch <name>]
                                         [--target-version <x.y.z>] [--since-tag <tag>] [--help]

Read-only: detect version files across ecosystems, read their versions, report
consistency, and collect release signals. Prints one JSON object. Never edits files.

Options:
  --repo <path>            Repository path (default: current directory). Must exist and
                           be a directory, otherwise prints
                           {"is_git":false,"error":"repo path not found"} and exits 0.
  --defaultBranch <name>   Override the auto-detected default branch.
  --target-version <x.y.z> The version the caller intends to release (echoed back; null
                           when not given). The script never guesses user intent.
  --since-tag <tag>        Start of the commit range scanned for release signals
                           (default: git describe --tags --abbrev=0, i.e. all commits
                           when no tag exists).
  --help, -h               Print this usage and exit 0.

Fields: is_git, version_files, inherited_version_files, distinct_versions, consistent,
go_mod_present, monorepo_mode, packages, target_version, release_signals, release_involved,
changed_files, warnings.
USAGE
  exit 0
fi
check_repo
git_ok rev-parse --is-inside-work-tree || not_git
enter_root
resolve_default

warns=""
warn_add() { warns+="$1"$'\n'; }

changed=$(changed_raw "$DEFAULT" | norm_changed)

# ---- 文件池：git ls-files ∪ git ls-files --others --exclude-standard（尊重 .gitignore）----
pool=$( { git ls-files -z 2>/dev/null; git ls-files --others --exclude-standard -z 2>/dev/null; } \
        | z2nl | tr -d '\r' | sed 's|\\|/|g' | awk 'NF' | sort -u )

# 硬编码排除目录：按路径段判断（不依赖 \\ 分隔符，Linux 上同样生效）。
# vendor/third_party/Pods/bower_components 必须在表里：第三方内嵌依赖常未被 .gitignore
# 排除，实测 vendor/sub/Cargo.toml 会被 git ls-files 收进来、当成自有版本文件，报假"不一致"。
seg_excluded() {
  case "/$1/" in
    */node_modules/*|*/.git/*|*/target/*|*/dist/*|*/build/*|*/.venv/*|*/venv/*|*/__pycache__/*|*/obj/*|*/bin/*|\
*/vendor/*|*/third_party/*|*/Pods/*|*/bower_components/*) return 0;;
  esac
  return 1
}

cand=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  seg_excluded "$f" && continue
  base=${f##*/}
  keep=0
  case "$base" in
    package.json|package-lock.json|npm-shrinkwrap.json|Cargo.toml|Cargo.lock|pyproject.toml|\
setup.py|setup.cfg|pom.xml|gradle.properties|build.gradle|build.gradle.kts|Directory.Build.props|\
composer.json|pubspec.yaml|mix.exs|MODULE.bazel|DESCRIPTION|Chart.yaml|Package.swift|go.mod) keep=1;;
    *.csproj|*.gemspec|*.opam) keep=1;;
  esac
  case "$f" in lib/*version.rb) keep=1;; esac
  [ $keep -eq 1 ] && cand+="$f"$'\n'
done <<< "$pool"
cand=$(printf '%s\n' "$cand" | awk 'NF' | sort -u)

# ---------- Cargo workspace 预扫描 ----------
# Cargo.toml 的 [workspace].members 列表（每行一个模式；支持多行数组，含 `packages/*` 通配）
cargo_members() {
  awk '
    {
      if (!inarr) {
        if ($0 !~ /^[ \t]*members[ \t]*=/) next
        i = index($0, "[")
        if (i == 0) next
        inarr = 1
        line = substr($0, i + 1)
      } else { line = $0 }
      s = line
      while (match(s, /"[^"]*"/)) {
        print substr(s, RSTART + 1, RLENGTH - 2)
        s = substr(s, RSTART + RLENGTH)
      }
      if (index(line, "]") > 0) exit
    }
  ' "$1" 2>/dev/null
}

# 成员写 `version.workspace = true` 或 `version = { workspace = true }` 时没有字面版本
cargo_inherits_version() {
  grep -qE '^[[:space:]]*version[[:space:]]*\.[[:space:]]*workspace[[:space:]]*=[[:space:]]*true' "$1" 2>/dev/null && return 0
  grep -qE '^[[:space:]]*version[[:space:]]*=[[:space:]]*\{[^}]*workspace[[:space:]]*=[[:space:]]*true' "$1" 2>/dev/null && return 0
  return 1
}

# 展开 workspace members：`packages/*` 之类通配按实际含 Cargo.toml 的目录展开
expand_member() { # <rootdir> <pattern>
  local d="$1" p="$2" base m
  case "$p" in ''|!*) return 0;; esac
  if [ "$d" = "." ]; then base="./$p"; else base="$d/$p"; fi
  case "$p" in
    *'*'*|*'?'*)
      # shellcheck disable=SC2086  # 故意让 shell 展开通配
      for m in $base; do
        [ -d "$m" ] && [ -f "$m/Cargo.toml" ] && printf '%s\n' "${m#./}"
      done
      ;;
    *)
      [ -d "$base" ] && [ -f "$base/Cargo.toml" ] && printf '%s\n' "${base#./}"
      ;;
  esac
  return 0
}

# 预先建立：workspace 根清单集合、成员目录 -> 根清单映射（规则集/继承都要用）
member_owner=""; cargo_ws_roots=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "${f##*/}" in Cargo.toml) ;; *) continue;; esac
  grep -qE '^\[workspace\]' "$f" 2>/dev/null || continue
  cargo_ws_roots+="$f"$'\n'
  d=${f%/*}; [ "$d" = "$f" ] && d="."
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    while IFS= read -r md; do
      [ -n "$md" ] || continue
      member_owner+="$md$TAB$f"$'\n'
    done <<< "$(expand_member "$d" "$m")"
  done <<< "$(cargo_members "$f")"
done <<< "$cand"

# 兜底 provider：路径最浅的 [workspace] 清单（成员模式没命中该成员目录时用）
fallback_root=$(printf '%s\n' "$cargo_ws_roots" | awk 'NF{n=gsub(/\//,"/"); print n "\t" $0}' | sort -k1,1n -k2,2 | head -1 | cut -f2)

vf_out="["; vf_sep=""; versions=""; vf_paths=""
add_vf() {
  local f="$1" eco="$2" v="$3"
  v=${v%$CR}
  [ -n "$v" ] || return 0
  vf_out+="${vf_sep}{\"file\":\"$(jes "$f")\",\"ecosystem\":\"$eco\",\"version\":\"$(jes "$v")\"}"
  vf_sep=","
  versions+="$v"$'\n'
  vf_paths+="$f"$'\n'
}

go_present=false; pkg_count=0; py_count=0; cargo_ws=false; pkg_dirs=""; inherited_paths=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  base=${f##*/}
  case "$base" in
    package.json)
      pkg_count=$((pkg_count + 1))
      d=${f%/*}; [ "$d" = "$f" ] && d="."
      [ "$d" != "." ] && pkg_dirs+="$d"$'\n'
      add_vf "$f" node "$(json_at "$f" version)" ;;
    package-lock.json|npm-shrinkwrap.json)
      v=$(json_at "$f" version); [ -z "$v" ] && v=$(json_at "$f" packages.version)
      add_vf "$f" node-lock "$v" ;;
    Cargo.toml)
      grep -qE '^\[workspace\]' "$f" 2>/dev/null && cargo_ws=true
      if cargo_inherits_version "$f"; then
        # 继承版本：进 inherited_version_files，**不计入** version_files/distinct_versions
        #（否则会凭空多出一个空版本，且成员版本来源不可见）
        inherited_paths+="$f"$'\n'
      else
        add_vf "$f" rust "$(grab_q "$f" '^[[:space:]]*version[[:space:]]*=[[:space:]]*')"
      fi
      ;;
    Cargo.lock)
      rn=""
      [ -f Cargo.toml ] && rn=$(grab_q Cargo.toml '^[[:space:]]*name[[:space:]]*=[[:space:]]*')
      add_vf "$f" rust-lock "$(cargo_lock_version "$rn" "$f")" ;;
    pyproject.toml)
      py_count=$((py_count + 1))
      d=${f%/*}; [ "$d" = "$f" ] && d="."
      [ "$d" != "." ] && pkg_dirs+="$d"$'\n'
      add_vf "$f" python "$(grab_q "$f" '^[[:space:]]*version[[:space:]]*=[[:space:]]*')" ;;
    setup.py) add_vf "$f" python "$(grab_q "$f" 'version[[:space:]]*=[[:space:]]*')" ;;
    setup.cfg) add_vf "$f" python "$(grab_after_eq "$f" '^[[:space:]]*version[[:space:]]*=')" ;;
    pom.xml) add_vf "$f" jvm "$(grab_xml "$f" version)" ;;
    gradle.properties) add_vf "$f" jvm "$(grab_after_eq "$f" '^[[:space:]]*version[[:space:]]*=')" ;;
    build.gradle|build.gradle.kts) add_vf "$f" jvm "$(grab_q "$f" 'version[[:space:]]*=[[:space:]]*')" ;;
    Directory.Build.props)
      v=$(grab_xml "$f" Version); [ -z "$v" ] && v=$(grab_xml "$f" VersionPrefix)
      add_vf "$f" dotnet "$v" ;;
    *.csproj)
      v=$(grab_xml "$f" Version); [ -z "$v" ] && v=$(grab_xml "$f" VersionPrefix)
      add_vf "$f" dotnet "$v" ;;
    *.gemspec) add_vf "$f" ruby "$(grab_q "$f" '\.version[[:space:]]*=[[:space:]]*')" ;;
    composer.json) add_vf "$f" php "$(json_at "$f" version)" ;;
    pubspec.yaml) add_vf "$f" dart "$(grab_after_colon "$f" '^[[:space:]]*version[[:space:]]*:')" ;;
    mix.exs) add_vf "$f" elixir "$(grab_q "$f" '^[[:space:]]*version[[:space:]]*:')" ;;
    MODULE.bazel) add_vf "$f" bazel "$(grab_q "$f" 'version[[:space:]]*=[[:space:]]*')" ;;
    DESCRIPTION) add_vf "$f" r "$(grab_after_colon "$f" '^Version[[:space:]]*:')" ;;
    Chart.yaml) add_vf "$f" helm "$(grab_after_colon "$f" '^[[:space:]]*version[[:space:]]*:')" ;;
    *.opam) add_vf "$f" ocaml "$(grab_q "$f" '^[[:space:]]*version[[:space:]]*:')" ;;
    Package.swift) add_vf "$f" swift "$(grab_q "$f" 'version[[:space:]]*=[[:space:]]*')" ;;
    go.mod) go_present=true ;;
  esac
  case "$f" in lib/*version.rb) add_vf "$f" ruby "$(grab_q "$f" '[Vv][Ee][Rr][Ss][Ii][Oo][Nn][[:space:]]*=')" ;; esac
done <<< "$cand"
vf_out+="]"

# ---------- Cargo workspace 继承（inherits_from = 提供版本的根清单）----------
inh_out="["; inh_sep=""
while IFS= read -r mf; do
  [ -n "$mf" ] || continue
  mdir=${mf%/*}; [ "$mdir" = "$mf" ] && mdir="."
  provider=""
  while IFS=$TAB read -r md rm; do
    [ -n "$md" ] || continue
    if [ "$md" = "$mdir" ]; then provider="$rm"; break; fi
  done <<< "$member_owner"
  [ -n "$provider" ] || provider="$fallback_root"
  inh_out+="${inh_sep}{\"file\":\"$(jes "$mf")\",\"inherits_from\":$(jstr "$provider")}"; inh_sep=","
done <<< "$inherited_paths"
inh_out+="]"

vf_count=$(printf '%s\n' "$vf_paths" | grep -c . )
distinct=$(printf '%s\n' "$versions" | awk 'NF' | sort -u)
distinct_count=$(printf '%s\n' "$distinct" | grep -c . )

# 版本文件数为 0 -> consistent=null（空集"一致"是空洞真值）+ no-version-files 警告
consistent="true"
if [ "$vf_count" -eq 0 ]; then
  consistent="null"; warn_add "no-version-files"
elif [ "$distinct_count" -gt 1 ]; then
  consistent="false"
fi

# ---- monorepo 检测 ----
monorepo=false
[ "$pkg_count" -gt 1 ] && monorepo=true
[ "$py_count" -gt 1 ] && monorepo=true
[ "$cargo_ws" = true ] && monorepo=true
for m in pnpm-workspace.yaml lerna.json nx.json; do
  [ -f "$m" ] && monorepo=true
done
packages=$( { printf '%s\n' "$pkg_dirs"; printf '%s\n' "$member_owner" | cut -f1; } | tr -d '\r' | awk 'NF' | sort -u )

# ---- 发布信号 ----
crange="HEAD"
if [ -n "$SINCE_TAG" ]; then
  if git_ok rev-parse --verify --quiet "$SINCE_TAG^{commit}"; then crange="$SINCE_TAG..HEAD"
  else warn_add "since-tag-not-found"; fi
else
  tag=$(git describe --tags --abbrev=0 2>/dev/null)
  [ -n "$tag" ] && crange="$tag..HEAD"
fi
commits_log=$(git log --format='%h %s' "$crange" 2>/dev/null)
first_commit() { printf '%s\n' "$commits_log" | grep -m1 -E -e "$1" 2>/dev/null; }

sig_out="["; sig_sep=""
sig_add() {
  [ -n "$1" ] || return 0
  sig_out+="${sig_sep}{\"kind\":\"$(jes "$1")\",\"sample\":\"$(jes "$2")\"}"; sig_sep=","
}

touched=""
while IFS= read -r fp; do
  [ -n "$fp" ] || continue
  if printf '%s\n' "$changed" | grep -Fxq -- "$fp"; then touched="$fp"; break; fi
done <<< "$vf_paths"
[ -n "$touched" ] && sig_add "version-file-touched" "$touched"

l=$(first_commit '^[0-9a-f]+ (chore\(release\)|chore: *release)'); [ -n "$l" ] && sig_add "commit-chore-release" "$l"
l=$(first_commit '^[0-9a-f]+ (feat|fix)!');                     [ -n "$l" ] && sig_add "commit-breaking" "$l"
l=$(first_commit '^[0-9a-f]+ feat(\(|: )');                     [ -n "$l" ] && sig_add "commit-feat" "$l"
l=$(first_commit '^[0-9a-f]+ fix(\(|: )');                      [ -n "$l" ] && sig_add "commit-fix" "$l"

footer=$(git log --format='%h%x09%s%x09%B' "$crange" 2>/dev/null | awk '
  {
    ncols = split($0, parts, "\t")
    if (ncols >= 3) { cur = parts[1] " " parts[2]; n = 0; next }
    if (n <= 20) { if ($0 ~ /BREAKING[- ]CHANGE:/) { print cur; exit } n++ }
  }')
[ -n "$footer" ] && sig_add "breaking-footer" "$footer"

sig_out+="]"
release_involved=false
[ -n "$touched" ] && release_involved=true

tv="null"; [ -n "$TARGET_VERSION" ] && tv="\"$(jes "$TARGET_VERSION")\""
printf '{"is_git":true,"version_files":%s,"inherited_version_files":%s,"distinct_versions":%s,"consistent":%s,"go_mod_present":%s,"monorepo_mode":%s,"packages":%s,"target_version":%s,"release_signals":%s,"release_involved":%s,"changed_files":%s,"warnings":%s}\n' \
  "$vf_out" "$inh_out" "$(printf '%s\n' "$distinct" | jarr_str)" "$consistent" "$go_present" "$monorepo" \
  "$(printf '%s\n' "$packages" | jarr_str)" "$tv" "$sig_out" "$release_involved" \
  "$(printf '%s\n' "$changed" | jarr_str)" "$(printf '%s\n' "$warns" | jarr_str)"
