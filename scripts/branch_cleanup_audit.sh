#!/usr/bin/env bash
# Audit branches for cleanup candidates (read-only). Contract: references/scan-recipes.md §2.
source "$(dirname "$0")/_lib.sh"
parse_args "$@"
if [ $HELP -eq 1 ]; then
  cat <<'USAGE'
Usage: bash branch_cleanup_audit.sh [--repo <path>] [--defaultBranch <name>] [--help]

Read-only audit of branch cleanup candidates as a single JSON object. Lists only;
it never deletes anything.

Options:
  --repo <path>            Repository path (default: current directory). Must exist
                           and be a directory, otherwise prints
                           {"is_git":false,"error":"repo path not found"} and exits 0.
  --defaultBranch <name>   Override the auto-detected default branch.
  --help, -h               Print this usage and exit 0.

Fields: is_git, default_branch, default_branch_source, current_branch, remote_reachable,
protected_from_rulesets, local_merge_base, remote_merge_base, remote_base_unverified,
protected, local_merged_candidates, local_stale_unmerged_report, remote_merged_candidates,
warnings.
USAGE
  exit 0
fi
check_repo
git_ok rev-parse --is-inside-work-tree || not_git
enter_root

warns=""
warn_add() { warns+="$1"$'\n'; }

resolve_default

current=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)

# ---------- 静态受保护名单 ----------
# 内置 ∪ release/* 通配（自解释，字面量也进数组）∪ 当前分支 ∪ 默认分支 ∪ cleanup.protect
prot_raw="main
master
develop
dev
trunk
prod
production
gh-pages
gh-readonly
release/*"
[ -n "$current" ] && prot_raw+=$'\n'"$current"
[ -n "$DEFAULT" ] && prot_raw+=$'\n'"$DEFAULT"

# 持久化保护名单：必须用 --get-all（--get 只回最后一个值，多值会静默丢）。
# 退出码 1 = 该键不存在 —— 正常情况，不算错误（静默忽略）；>=2 才是真读取失败，
# 记 protect-config-unreadable 后继续（绝不因此失败、也绝不因此漏掉静态名单）。
prot_cfg=$(git config --get-all cleanup.protect 2>/dev/null); prot_rc=$?
if [ "$prot_rc" -eq 0 ]; then
  prot_raw+=$'\n'"$prot_cfg"
elif [ "$prot_rc" -gt 1 ]; then
  warn_add "protect-config-unreadable"
fi

protected=$(printf '%s\n' "$prot_raw" | tr -d '\r' | awk 'NF' | sort -u)

locals=$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | awk 'NF' | sort -u)

# 静态判定：用于 protected 字段与 local_stale_unmerged_report（后者是报告、不是删除候选，
# 且规则集只对"候选分支 ∪ 默认分支"求值，见下）。
is_protected_static() {
  case "$1" in release/*) return 0;; esac
  printf '%s\n' "$protected" | grep -Fxq -- "$1"
}

# ---------- 合并基准 ----------
# 本地合并必须用**本地默认分支**：本地已合并但尚未推送时用 origin/<default> 会把
# 可安全删除的分支漏报（假阴性）；删本地分支不丢内容，因为提交已在本地默认分支里。
# 远程合并必须用 **origin/<default>**：用本地分支作基准会在「本地已合并、远程尚未
# 收到」时误判为已合并，删远程分支就丢数据。
local_merge_base=""; remote_merge_base=""; remote_base_unverified=true
if [ -n "$DEFAULT" ] && git_ok rev-parse --verify --quiet "refs/heads/$DEFAULT"; then
  local_merge_base="$DEFAULT"
fi
# 基准守卫：用 origin/<default> 前先验证该 ref 存在；不存在 → 远程候选一律为空 + 警告
if [ -n "$DEFAULT" ] && git_ok rev-parse --verify --quiet "refs/remotes/origin/$DEFAULT"; then
  remote_merge_base="origin/$DEFAULT"
  remote_base_unverified=false
else
  warn_add "remote-base-unverified"
fi
[ -z "$local_merge_base" ] && [ -z "$remote_merge_base" ] && warn_add "default-branch-unavailable"

merged=""; rmerged=""
if [ -n "$local_merge_base" ]; then
  # 提到循环外（原先每个分支都重跑一次 git branch --merged）
  merged=$(git branch --merged "$local_merge_base" 2>/dev/null | sed 's/^[* ]*//; s/[[:space:]]*$//' | awk 'NF')
fi
if [ -n "$remote_merge_base" ]; then
  rmerged=$(git branch -r --merged "$remote_merge_base" 2>/dev/null | sed 's/^[* ]*//; s/[[:space:]]*$//' | awk 'NF')
fi
is_merged() { printf '%s\n' "$merged" | grep -Fxq -- "$1"; }
is_rmerged() { printf '%s\n' "$rmerged" | grep -Fxq -- "$1"; }

# ---------- 本地候选（按静态名单；规则集结果回来后统一过滤）----------
now_epoch=$(date +%s)
lm_pre=""; ls_out="["; ls_sep=""
while IFS= read -r b; do
  [ -z "$b" ] && continue
  if is_merged "$b"; then
    if ! is_protected_static "$b"; then lm_pre+="$b"$'\n'; fi
  else
    dateStr=$(git log -1 --format='%cI' "$b" 2>/dev/null)
    age_days=""
    if [ -n "$dateStr" ]; then
      cdt=$(epoch_of "$dateStr")
      if [ -n "$cdt" ]; then age_days=$(( (now_epoch - cdt) / 86400 )); fi
    fi
    if [ -n "$age_days" ] && [ "$age_days" -gt 30 ] && ! is_protected_static "$b" && [ "$b" != "$current" ]; then
      ls_out+="${ls_sep}{\"branch\":\"$(jes "$b")\",\"last_commit\":\"$(jes "$dateStr")\",\"age_days\":$age_days}"; ls_sep=","
    fi
  fi
done <<< "$locals"
ls_out+="]"

# 远端可达性：失败即 remote_reachable=false + 告警（不得当成"没有可剪枝的远端分支"）
remote_heads_raw=$(git ls-remote origin 2>/dev/null); ls_rc=$?
remote_reachable=false
if [ $ls_rc -eq 0 ]; then remote_reachable=true; else warn_add "remote-unreachable"; fi
# 精确匹配：无锚定子串会让 refs/heads/feat 误配 refs/heads/feat-x
remote_exists() { printf '%s\n' "$remote_heads_raw" | awk '{print $2}' | grep -Fxq -- "refs/heads/$1"; }

# ---------- 远程候选（按静态名单）----------
rrefs=$(git for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null | grep -E '^origin/' | grep -v '^origin/HEAD$' | awk 'NF' | sort -u)
rm_pre=""
while IFS= read -r r; do
  [ -z "$r" ] && continue
  short="${r#origin/}"
  is_protected_static "$short" && continue
  # 远程基准未验证时 rmerged 恒为空 → 远程候选一律为空（宁可不删）
  if [ -n "$remote_merge_base" ] && is_rmerged "$r"; then
    rexists=false; if remote_exists "$short"; then rexists=true; fi
    # tip_sha：删除时必须作为 --force-with-lease 的期望值，否则确认窗口内他人推的提交会被静默删掉
    tip=$(git rev-parse "refs/remotes/origin/$short" 2>/dev/null | tr -d '\r\n')
    rm_pre+="$short$TAB$r$TAB$rexists$TAB$tip"$'\n'
  fi
done <<< "$rrefs"

# ---------- 仓库侧保护分支（gh rules/branches） ----------
# 只对「候选分支 ∪ 默认分支」逐个查 rules/branches/<branch>：该端点返回该分支**实际生效**
# 的 active 规则（含 org 级），已过滤 enforcement（active/evaluate/disabled）并已展开
# ref 匹配（~DEFAULT_BRANCH、refs/heads/*/**/* 等）。含 .type=="deletion" 即视为受保护。
#   · 列表端点 /rulesets 不返回 rules/conditions（实测），故不用它；
#   · 陷阱：分支不存在时该端点返回 200 + []（不是 404），所以必须先验证分支真的存在，
#     否则「分支名拼错/已被删」会被当成「没有保护」。
# 任何失败都静默降级：protected_from_rulesets=[] + rulesets-unavailable 警告，绝不整体失败，
# 也绝不把「查不到」当成「没有保护分支」——protected 的静态部分只是下界。
is_github_host() {
  case "$1" in github.com|*.github.com) return 0;; esac
  return 1
}
# GitHub URL -> owner/repo（仅在宿主判定为 GitHub 后才用得上）
remote_slug() {
  local u="$1" rest
  [ -n "$u" ] || return 0
  u=${u%/}; u=${u%.git}
  case "$u" in
    *://*)
      rest=${u#*://}
      case "$rest" in *@*) rest=${rest#*@};; esac
      printf '%s' "${rest#*/}"
      ;;
    *@*:*) printf '%s' "${u#*:}" ;;
    *) return 0 ;;
  esac
}

rname=""
if git remote get-url origin >/dev/null 2>&1; then rname="origin"
else rname=$(git remote 2>/dev/null | awk 'NF{print; exit}'); fi
rurl=""
[ -n "$rname" ] && rurl=$(git remote get-url "$rname" 2>/dev/null)
rhost=$(host_of_url "$rurl")

rulesets_ok=0; protected_rulesets=""
if command -v gh >/dev/null 2>&1 && is_github_host "$rhost"; then
  slug=$(remote_slug "$rurl")
  if [ -n "$slug" ]; then
    qset=$( { printf '%s\n' "$lm_pre"
              printf '%s\n' "$rm_pre" | cut -f1
              [ -n "$DEFAULT" ] && printf '%s\n' "$DEFAULT"; } | tr -d '\r' | awk 'NF' | sort -u )
    rulesets_ok=1; qn=0
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      # 分支必须真的存在于远端：ls-remote 成功时以它为准（权威）；ls-remote 不可用时
      # 退回 remote-tracking ref（契约不允许用"远端已无该 ref"否掉候选，见 §2 尾注）。
      if [ "$remote_reachable" = true ]; then
        remote_exists "$b" || continue
      else
        git_ok rev-parse --verify --quiet "refs/remotes/origin/$b" || continue
      fi
      qn=$((qn + 1))
      # 硬上限：超过即视为"没能查完"，降级告警（宁可不给结论，也不给半截结论）
      if [ "$qn" -gt 100 ]; then rulesets_ok=0; break; fi
      if ans=$(gh api "repos/$slug/rules/branches/$b" \
                --jq 'any(.[]; .type=="deletion")' 2>/dev/null); then
        case "$ans" in true) protected_rulesets+="$b"$'\n';; esac
      else
        rulesets_ok=0; break
      fi
    done <<< "$qset"
  fi
fi
if [ "$rulesets_ok" -eq 1 ]; then
  protected_rulesets=$(printf '%s\n' "$protected_rulesets" | tr -d '\r' | awk 'NF' | sort -u)
else
  protected_rulesets=""
  warn_add "rulesets-unavailable"
fi
is_rule_protected() {
  [ -n "$protected_rulesets" ] || return 1
  printf '%s\n' "$protected_rulesets" | grep -Fxq -- "$1"
}

# ---------- 输出候选（过滤掉规则集覆盖的分支）----------
lm_out="["; lm_sep=""
while IFS= read -r b; do
  [ -n "$b" ] || continue
  is_rule_protected "$b" && continue
  lm_out+="${lm_sep}\"$(jes "$b")\""; lm_sep=","
done <<< "$lm_pre"
lm_out+="]"

rm_out="["; rm_sep=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  IFS=$TAB read -r short tr rex tip <<< "$line"
  is_rule_protected "$short" && continue
  rm_out+="${rm_sep}{\"branch\":\"$(jes "$short")\",\"tracking_ref\":\"$(jes "$tr")\",\"remote_exists\":$rex,\"tip_sha\":$(jstr "$tip")}"; rm_sep=","
done <<< "$rm_pre"
rm_out+="]"

printf '{"is_git":true,"default_branch":%s,"default_branch_source":"%s","current_branch":%s,"remote_reachable":%s,"protected_from_rulesets":%s,"local_merge_base":%s,"remote_merge_base":%s,"remote_base_unverified":%s,"protected":%s,"local_merged_candidates":%s,"local_stale_unmerged_report":%s,"remote_merged_candidates":%s,"warnings":%s}\n' \
  "$(jstr "$DEFAULT")" "$(jes "$DEFAULT_SOURCE")" "$(jstr "$current")" "$remote_reachable" \
  "$(printf '%s\n' "$protected_rulesets" | jarr_str)" "$(jstr "$local_merge_base")" "$(jstr "$remote_merge_base")" "$remote_base_unverified" \
  "$(printf '%s\n' "$protected" | jarr_str)" "$lm_out" "$ls_out" "$rm_out" \
  "$(printf '%s\n' "$warns" | jarr_str)"
