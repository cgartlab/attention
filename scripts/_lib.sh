#!/usr/bin/env bash
# lizheng 采集脚本共享 JSON 助手（bash）。各脚本开头：source "$(dirname "$0")/_lib.sh"
# 只读，绝不改仓库。JSON 契约见 references/scan-recipes.md。

# JSON 字符串转义（值内不含嵌入换行——git 单行输出）
jes() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'; }

# stdin=换行分隔值 -> JSON 字符串数组；空输入 -> []
jarr_str() {
  local first=1 e out='['
  while IFS= read -r e || [ -n "$e" ]; do
    [ -z "$e" ] && continue
    [ $first -eq 1 ] && first=0 || out+=','
    out+="\"$(jes "$e")\""
  done
  out+=']'; printf '%s' "$out"
}

z2nl() { tr '\0' '\n'; }                 # git -z 的 NUL 输出 -> 换行分隔
not_git() { printf '{"is_git":false,"error":"not a git repository"}\n'; exit 0; }
git_ok() { git "$@" >/dev/null 2>&1; }

# 默认分支探测（输出名或空）
detect_default() {
  local sym b
  sym=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$sym" ]; then printf '%s' "${sym#origin/}"; return; fi
  for b in main master develop trunk; do
    if git show-ref --verify --quiet "refs/heads/$b" 2>/dev/null; then printf '%s' "$b"; return; fi
  done
}

# ISO8601 提交日期 -> epoch（GNU date -d 优先，回退 BSD date -jf；兼容 macOS bash 3.2）
epoch_of() {
  date -d "$1" +%s 2>/dev/null || date -jf '%Y-%m-%dT%H:%M:%S' "${1:0:19}" +%s 2>/dev/null
}

# 变更集原始（NUL/换行混合 -> 换行）：staged ∪ unstaged ∪ untracked ∪ (origin/<default>..HEAD 若存在)
changed_set() {
  local DEFAULT="$1" od
  { git diff --cached --name-only --no-renames -z 2>/dev/null
    git diff --name-only --no-renames -z 2>/dev/null
    git ls-files --others --exclude-standard -z 2>/dev/null; } | z2nl
  if [ -n "$DEFAULT" ]; then od="origin/$DEFAULT"
    if git_ok rev-parse --verify "refs/remotes/$od"; then git diff --name-only --no-renames "$od..HEAD" 2>/dev/null; fi
  fi
}
# 变更集规范化：反斜杠->正斜杠、去空、去重
norm_changed() { sed 's|\\|/|g' | awk 'NF' | sort -u; }

# 通用入参解析：产出 REPO / DEFAULT / HELP
parse_args() {
  REPO=""; DEFAULT=""; HELP=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) REPO="$2"; shift 2;;
      --defaultBranch) DEFAULT="$2"; shift 2;;
      --help|-h) HELP=1; shift;;
      *) shift;;
    esac
  done
}