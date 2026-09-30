#!/usr/bin/env bash
# attention 采集脚本共享 JSON 助手（bash）。各脚本开头：source "$(dirname "$0")/_lib.sh"
# 只读，绝不改仓库。JSON 契约见 references/scan-recipes.md。

# 确定性口径：按字节序排序、ASCII 大小写折叠，三平台（macOS bash 3.2 / Linux / Git-bash）一致。
export LC_ALL=C
# 无人值守：绝不为凭据弹交互（只读采集，卡在提示符等于死循环）。
export GIT_TERMINAL_PROMPT=0
export GIT_PAGER=cat

# 控制字符常量。必须用变量而不是在 ${...} 里写 $'\r'：bash 在
# "$( ... "${v%$'\r'}" ... )" 这种嵌套里解析不出闭合括号（实测会静默取到空值）。
CR=$'\r'
TAB=$'\t'

# 所有 git 调用一律禁用颜色（契约「颜色」条）：用户全局 color.ui=always 会给
# `git branch --merged` 等输出注入 ANSI 转义，使分支名比对整体失效（静默漏报剪枝候选）。
git() { command git -c color.ui=never "$@"; }
git_ok() { git "$@" >/dev/null 2>&1; }

# ---------- JSON 原语 ----------

# JSON 字符串转义。RFC 8259 禁止字符串内出现裸控制字符：`\t`/`\r`/`\n` 只是最常见的三个，
# 其余 <0x20（如 CRLF 文件里残留的 \r、\v、\f）同样非法，一律写成 \u00XX。
jes() {
  local s="$1" out="" i n c code
  n=${#s}
  i=0
  while [ "$i" -lt "$n" ]; do
    c=${s:$i:1}
    case "$c" in
      '\') out="$out\\\\" ;;
      '"')  out="$out\\\"" ;;
      [[:cntrl:]]) code=$(printf '%d' "'$c"); out="$out$(printf '\\u%04x' "$code")" ;;
      *)    out="$out$c" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# stdin=换行分隔值 -> JSON 字符串数组；空输入 -> []。取值处统一剥离行尾 CR。
jarr_str() {
  local first=1 e out='['
  while IFS= read -r e || [ -n "$e" ]; do
    e=${e%$CR}
    [ -z "$e" ] && continue
    if [ $first -eq 1 ]; then first=0; else out+=','; fi
    out+="\"$(jes "$e")\""
  done
  out+=']'
  printf '%s' "$out"
}

# 字符串（空 -> null）
jstr() { if [ -n "$1" ]; then printf '"%s"' "$(jes "$1")"; else printf 'null'; fi; }

# 变量（换行分隔）-> 数组
lines_str() { printf '%s\n' "$1" | jarr_str; }

# 去重（保序无关，全脚本统一用排序后输出）
sort_u() { sort -u; }

# 读文件全部内容（无尾换行问题）
read_all() { cat "$1" 2>/dev/null; }

# ---------- 值提取 ----------

# 剥离行尾 CR（CRLF 输入的统一处理点）
stripr() { printf '%s' "${1%$CR}"; }

# 从 URL 解析主机名（解析不出 -> 空）
host_of_url() {
  local u="$1" rest=""
  case "$u" in
    *://*)
      rest="${u#*://}"
      # 去掉 userinfo（最后一个 @ 且位于第一个 / 之前）
      case "$rest" in
        *@*) local head="${rest%%/*}"; case "$head" in *@*) rest="${head##*@}${rest#"$head"}";; esac;;
      esac
      rest="${rest%%/*}"
      printf '%s' "${rest%%:*}"
      ;;
    *@*:*)
      rest="${u#*@}"
      printf '%s' "${rest%%:*}"
      ;;
    *) printf '' ;;
  esac
}

# URL 脱敏：去掉 userinfo 里的凭据（scheme://***@host/path）
mask_url() {
  local u="$1"
  case "$u" in
    *://*@*) printf '%s' "${u%%://*}://***@${u#*://*@}" ;;
    *://*)   printf '%s' "$u" ;;
    *@*:*)   printf '%s' "***@${u#*@}" ;;
    *)       printf '%s' "$u" ;;
  esac
}

# ---------- JSON 值扫描器（无 python3/jq 时的兜底） ----------
# 输出 "点分路径<US>值" 行，覆盖脚本所需的顶层键与一层嵌套（scripts.test / packages.version）。
# 语义与真 JSON 解析器对齐；仅当输入不是 JSON 时才降级。
_json_pairs() {
  awk '
    function hexval(h,   i, c, v, r) {
      r = 0
      for (i = 1; i <= length(h); i++) {
        c = tolower(substr(h, i, 1))
        v = index("0123456789abcdef", c) - 1
        if (v < 0) return -1
        r = r * 16 + v
      }
      return r
    }
    { line[NR] = $0 }
    END {
      s = ""
      for (k = 1; k <= NR; k++) s = s (k > 1 ? "\n" : "") line[k]
      n = length(s); i = 1; depth = 0
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\"") {
          j = i + 1; buf = ""
          while (j <= n) {
            d = substr(s, j, 1)
            if (d == "\\") {
              e = substr(s, j + 1, 1)
              if (e == "n") buf = buf "\n"
              else if (e == "t") buf = buf "\t"
              else if (e == "r") buf = buf "\r"
              else if (e == "b") buf = buf "\b"
              else if (e == "f") buf = buf "\f"
              else if (e == "u") {
                hv = hexval(substr(s, j + 2, 4))
                if (hv > 0) { buf = buf sprintf("%c", hv); j += 4 }
              }
              else buf = buf e
              j += 2
              continue
            }
            if (d == "\"") break
            buf = buf d
            j++
          }
          k = j + 1
          while (k <= n && substr(s, k, 1) ~ /[ \t\r\n]/) k++
          if (substr(s, k, 1) == ":") { keyat[depth] = buf; i = k + 1; continue }
          p = ""
          for (d = 1; d <= depth; d++) {
            if (keyat[d] != "") p = p (p == "" ? "" : ".") keyat[d]
          }
          printf "%s\001%s\n", p, buf
          i = j + 1
          continue
        }
        if (c == "{" || c == "[") { depth++; keyat[depth] = ""; i++; continue }
        if (c == "}" || c == "]") { keyat[depth] = ""; depth--; if (depth < 0) depth = 0; i++; continue }
        i++
      }
    }
  '
}

# 取 JSON 点分路径的字符串值（取不到 -> 空）
json_at() {
  local f="$1" path="$2" sep
  sep=$(printf '\001')
  [ -f "$f" ] || return 0
  _json_pairs < "$f" 2>/dev/null | awk -F"$sep" -v k="$path" '$1 == k { print substr($0, length($1) + 2); exit }'
}

# 是否有可用的真 JSON 解析器（按"能否执行"探测，不按文件是否存在）
have_json_parser() {
  if command -v jq >/dev/null 2>&1 && jq -e . /dev/null >/dev/null 2>&1; then return 0; fi
  if command -v python3 >/dev/null 2>&1 && printf 'import json' | python3 -c 'import json' >/dev/null 2>&1; then return 0; fi
  return 1
}

# ---------- 默认分支探测 ----------

# 输出 "source<TAB>branch"。命令替换在子 shell 里跑，全局变量传不出来，故用单行协议回传。
detect_default() {
  local sym b
  sym=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$sym" ]; then printf 'origin-head\t%s' "${sym#origin/}"; return 0; fi
  sym=$(git ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/{print $2; exit}')
  if [ -n "$sym" ]; then printf 'ls-remote\t%s' "${sym#refs/heads/}"; return 0; fi
  for b in main master develop trunk; do
    if git show-ref --verify --quiet "refs/heads/$b" 2>/dev/null; then printf 'local-ref\t%s' "$b"; return 0; fi
  done
  printf 'unavailable\t'
}

# 统一入口：设置全局 DEFAULT / DEFAULT_SOURCE（探测不到时 DEFAULT 为空、来源 unavailable）
resolve_default() {
  local line
  if [ -n "$DEFAULT" ]; then DEFAULT_SOURCE="explicit"; return 0; fi
  line=$(detect_default)
  DEFAULT_SOURCE=${line%%$TAB*}
  DEFAULT=${line#*$TAB}
}

# ---------- 变更集 ----------

# 变更集原始（staged ∪ unstaged ∪ untracked ∪ origin/<default>..HEAD），NUL 安全
changed_raw() {
  local d="$1" od
  { git diff --cached --name-only --no-renames -z 2>/dev/null
    git diff --name-only --no-renames -z 2>/dev/null
    git ls-files --others --exclude-standard -z 2>/dev/null; } | z2nl
  if [ -n "$d" ]; then
    od="origin/$d"
    if git_ok rev-parse --verify "refs/remotes/$od"; then
      git diff --name-only --no-renames -z "$od..HEAD" 2>/dev/null | z2nl
    fi
  fi
}
# 变更集规范化：去 CR、反斜杠->正斜杠、去空、去重、排序（字节序）
norm_changed() { tr -d '\r' | sed 's|\\|/|g' | awk 'NF' | sort -u; }

z2nl() { tr '\0' '\n'; }

# ---------- 入参 ----------

# 通用入参解析：产出 REPO / REPO_GIVEN / DEFAULT / TARGET_VERSION / SINCE_TAG / HELP
# `--repo` 漏值（$#==1）不得死循环：POSIX shift 越界会失败并使循环条件恒真。
parse_args() {
  REPO=""; REPO_GIVEN=0; DEFAULT=""; TARGET_VERSION=""; SINCE_TAG=""; HELP=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)           if [ $# -ge 2 ]; then REPO="$2"; shift 2; else REPO_GIVEN=1; shift; fi ;;
      --defaultBranch)  if [ $# -ge 2 ]; then DEFAULT="$2"; shift 2; else shift; fi ;;
      --target-version) if [ $# -ge 2 ]; then TARGET_VERSION="$2"; shift 2; else shift; fi ;;
      --since-tag)      if [ $# -ge 2 ]; then SINCE_TAG="$2"; shift 2; else shift; fi ;;
      --help|-h)        HELP=1; shift ;;
      *)                shift ;;
    esac
  done
}

# `--repo` 校验：路径不存在/不是目录/漏值 -> 显式报错并退出 0，绝不静默回退当前目录。
check_repo() {
  if [ "$REPO_GIVEN" = 1 ] || { [ -n "$REPO" ] && [ ! -d "$REPO" ]; }; then
    printf '{"is_git":false,"error":"repo path not found"}\n'
    exit 0
  fi
  if [ -n "$REPO" ]; then
    cd "$REPO" 2>/dev/null || { printf '{"is_git":false,"error":"repo path not found"}\n'; exit 0; }
  fi
}

not_git() { printf '{"is_git":false,"error":"not a git repository"}\n'; exit 0; }

# ISO8601 提交日期 -> epoch（GNU date -d 优先，回退 BSD date -jf；兼容 macOS bash 3.2）
epoch_of() {
  date -d "$1" +%s 2>/dev/null || date -jf '%Y-%m-%dT%H:%M:%S' "${1:0:19}" +%s 2>/dev/null
}

# 统一把工作目录切到仓库根：契约要求 JSON 内路径一律相对仓库根（--repo 指向子目录时同样成立）
enter_root() {
  local r
  r=$(git rev-parse --show-toplevel 2>/dev/null)
  [ -n "$r" ] && cd "$r" 2>/dev/null
  return 0
}

# ---------- 清单/配置文件取值助手 ----------

# 去首尾空白、去尾 CR、去成对引号
clean_val() {
  local s="$1"
  s=${s%$CR}
  s=$(printf '%s' "$s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$s" in
    \"*\") s=${s#\"}; s=${s%\"} ;;
    \'*\') s=${s#\'}; s=${s%\'} ;;
  esac
  printf '%s' "$s"
}

# 第一个匹配行里最先出现的 '...' 或 "..." 内容（无引号则空）
grab_q() {
  local line
  line=$(grep -m1 -E -e "$2" "$1" 2>/dev/null)
  [ -z "$line" ] && return 0
  printf '%s' "${line%$CR}" | sed -nE "s/^[^\"']*[\"']([^\"']*)[\"'].*/\1/p"
}

# 第一个匹配行 `=` 之后的取值
grab_after_eq() {
  local line
  line=$(grep -m1 -E -e "$2" "$1" 2>/dev/null)
  line=${line#*=}
  clean_val "$line"
}

# 第一个匹配行 `:` 之后的取值
grab_after_colon() {
  local line
  line=$(grep -m1 -E -e "$2" "$1" 2>/dev/null)
  line=${line#*:}
  clean_val "$line"
}

# XML 第一个 <tag>...</tag>
grab_xml() {
  local line
  line=$(grep -m1 -oE "<$2>[^<]*</$2>" "$1" 2>/dev/null)
  line=${line#"<$2>"}
  line=${line%"</$2>"}
  printf '%s' "${line%$CR}"
}

# Cargo.lock：取 [[package]] 中 name == 根包名者的 version
cargo_lock_version() {
  local rootname="$1" file="$2"
  [ -n "$rootname" ] || return 0
  awk -v want="$rootname" '
    { line = $0 }
    /^\[\[package\]\]/ {
      if (name == want && ver != "") { print ver; found = 1; exit }
      name = ""; ver = ""; next
    }
    name == "" && line ~ /^[[:space:]]*name[[:space:]]*=/ { v = line; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/^"|"$/, "", v); name = v }
    ver == "" && line ~ /^[[:space:]]*version[[:space:]]*=/ { v = line; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/^"|"$/, "", v); ver = v }
    END { if (!found && name == want && ver != "") print ver }
  ' "$file" 2>/dev/null
}
