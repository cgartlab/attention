# Changelog

本项目所有重要变更记录于此。格式参考 [Keep a Changelog](https://keepachangelog.com/)，版本号遵循 [语义化版本](https://semver.org/)。

> 版本策略：技能尚不完善，当前保持 0.1.0；以下未发布变更记于 [Unreleased]，待通用化成熟后由用户决定再切版本号。

## [Unreleased]

### Added
- **P1 脚本解耦**：scripts/ 新增 bash（.sh）实现，与 PowerShell（.ps1）并行，覆盖 5 个采集脚本 + 共享助手 `scripts/_lib.sh`（无 bash-4 特性，兼容 macOS bash 3.2；GNU/BSD date）。
- `references/scan-recipes.md`：5 个脚本的 git 命令配方 + JSON 契约（单一事实源），.sh 与 .ps1 都照此对齐；含无脚本回退 3 步流程与依赖边界审计。
- `references/environment-and-prereqs.md` §6：Phase 0 shell 探测与路径选择（bash→.sh / pwsh→.ps1 / 无脚本回退）。
- `docs/DEVELOPMENT-PLAN.md`：跨 harness 通用化开发计划（P1–P5，版本贯穿保持 0.1.0）。
- 默认分支 master -> main。
- **P2 Agent Skills 标准对齐**：README 增加 `npx skills add cgartlab/lizheng` 安装路径与 skills.sh / Agent Skills 兼容徽章；确认 frontmatter（name+description）符合开放标准。
- **P5 多宿主 PR 指引**：`references/pr-and-remote-hosts.md` 扩为按宿主给真实 CLI + Web 回退——GitLab(`glab mr`)、Gitea/Codeberg(`tea pulls`)、Azure DevOps(`az repos pr`)、Bitbucket(Web)，不编造命令。
- **新能力 missing_core_docs**：`next_steps_analysis` 增加 `missing_core_docs` 信号，检测期望核心文档（README/CHANGELOG/LICENSE/AGENTS/CONTRIBUTING）中无匹配顶层文件者，让它出现在下一步建议里（.ps1 + .sh + scan-recipes 契约成对更新）。
- `AGENTS.md`：机器面 repo 指引（脚本黑盒/安全分层/报告大白话/版本策略/成对改脚本/自检），已被系统识别为 workspace 指令。
- `scripts/smoke_test.ps1` + `scripts/smoke_test.sh`：一键冒烟回归检查（跑 5 个采集脚本、验合法 JSON），pwsh 与 bash 成对；AGENTS.md 自检指向它。

### Changed
- 收尾报告改用大白话：主叙事面向项目作者（含刚入行的开发者），禁止字段名 / 命令串 / JSON 键进入主叙事，原始技术信号另放末尾"📋 技术细节（可选）"小节，主叙事必须能独立读懂。SKILL.md 的 Phase 4 新增"报告语言原则"小节并说明原因。

### Fixed
- TODO 扫描排除自身源文件（`scripts/next_steps_analysis.ps1` 与 `.sh`），消除自指假阳性（dogfood 发现 P1 引入 .sh 后 .ps1 只排除 .ps1 导致自指 .sh，已修：两变体都排除两文件）。
- `AGENTS.md` 自检行更新此前因 `-like` 用半角冒号而行用全角冒号静默未生效，已用字面 .Replace 修正并指向 smoke_test。

### Notes
- bash（.sh）实现**已在 git-bash 验证通过**：`bash scripts/smoke_test.sh --repo <path>` 在 lizheng + 4 个 eval fixture（clean/dirty/version/non-github）各 5/5；version_consistency_audit 的 .sh 与 .ps1 输出一致（parity 确认）。bash 位于 Git for Windows 的 bin\bash.exe（常不在 PATH，见 environment-and-prereqs §6 Windows 回退）。
- `npx skills add cgartlab/lizheng` 安装路径需仓库推送到 GitHub 后方可验证；当前未推送（按计划推迟建远程）。

## [0.1.0] - 2026-09-29

首个可用版本。

### Added
- 立正核心工作流：Phase 0 前置探测 -> Phase 1 状态快照 -> Phase 2 干净/脏态分流 -> Phase 3A 干净同步 / 3B 脏态修复 -> Phase 4 收尾报告。
- 五个只读采集脚本（PowerShell）：git_state_snapshot / branch_cleanup_audit / version_consistency_audit / core_docs_relevance_scan / next_steps_analysis。
- 七份 references：环境与前置探测、判断标准、分支模型与保护、核心文档同步、发行版本、PR 与远程宿主、自主与安全。
- 四份 assets/templates：提交信息、PR body、CHANGELOG 条目、状态报告。
- 四个 evals（clean-sync / dirty-wip-fix / version-bump-release / non-github-fallback）及断言。
- LICENSE：CC-BY-NC-SA-4.0 完整 legalcode。