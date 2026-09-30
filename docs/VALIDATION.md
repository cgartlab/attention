# 跨 harness 验证记录

立正的 bash（.sh）与 pwsh（.ps1）双实现，已在同一环境跑通并校验输出一致（parity）。

## 验证环境
- **bash**：`C:\Program Files\Git\bin\bash.exe`（GNU bash 5.3.15，cygwin；不在 PATH，由 git 安装目录推导——见 `references/environment-and-prereqs.md` §6 Windows 回退）。
- **pwsh**：PowerShell 7（DSH 环境）。
- **校验方式**：同一 repo 跑 .sh 与 .ps1，`ConvertFrom-Json` 后比关键字段；脚本未跑或 JSON 非法则记 FAIL，不误判 parity。

## 脚本 JSON 合法性（smoke_test）
`bash scripts/smoke_test.sh`（严格版：输出行须以 `{"is_git"` 开头、`}` 结尾）在 lizheng + 4 个 eval fixture（clean / dirty-wip / version / non-github）各 5/5。

## Parity 矩阵（.sh == .ps1）

| 脚本 | 校验路径 | repo | 结果 |
|------|----------|------|------|
| git_state_snapshot | staged / unstaged / untracked（脏态） | parity-dirty fixture | ✅ 一致（staged.txt / README.md / untracked.txt） |
| version_consistency_audit | version_files / distinct / consistent / release_involved | eval-3（package.json + Cargo.toml） | ✅ 一致（node=1.1.0 rust=1.1.0 distinct=[1.1.0] consistent=true） |
| branch_cleanup_audit | merged_candidates + stale age_days | eval-1 pristine（feature/done 已合并 + feature/old 陈旧 91 天） | ✅ 一致（merged=[feature/done]；stale={branch=feature/old, age_days=91}） |
| core_docs_relevance_scan | docs_needing_update references | parity-docref（README 引用变更的 src.js） | ✅ 一致（references=[src.js]，changed_files=[src.js]） |
| next_steps_analysis | recent_commits / todo_fixme / missing_core_docs / branches | lizheng | ✅ 一致（recent=15，missing_core_docs=[CONTRIBUTING]） |

## 关键确认
- **GNU/BSD date→age 移植**（`epoch_of`）：bash 与 pwsh 对 91 天陈旧分支算出相同 `age_days`，跨平台日期处理正确。
- **core_docs basename 匹配**（`grep -Fq`）：bash 与 pwsh 一致检出 README 引用 src.js。
- **第 6 轮深度 parity 抓到 `next_steps_analysis.sh` 一个真 bug**（backtick-n 当 `\n`、重复 printf、漏 `$missing_out` 参），smoke_test 严格化后不再误判。

## 未覆盖（诚实）
- **is_github=true + gh issue/pr 路径**：需真实 GitHub 远程（本环境无；用户暂不建远程）。
- **ahead/behind 非零**：需远程有分叉（本环境远程均 up-to-date，behind=0）。
- **P2 `npx skills add` 安装链路**：需推送到 GitHub 后验证（用户暂不建远程）。