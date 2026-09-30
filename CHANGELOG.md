# Changelog

本项目所有重要变更记录于此。格式参考 [Keep a Changelog](https://keepachangelog.com/)，版本号遵循 [语义化版本](https://semver.org/)。

> 版本策略：技能尚不完善，当前保持 0.1.0；以下未发布变更记于 [Unreleased]，待通用化成熟后由用户决定再切版本号。

## [Unreleased]

### Added
- **P0-1/P1 落地（第二轮，生态调研吸收）**：`branch_cleanup_audit` 的**本地/远程合并基准分离**（本地用本地默认分支、远程用 `origin/<默认分支>`）＋基准守卫（`local_merge_base`/`remote_merge_base`/`remote_base_unverified`）；`protected_from_rulesets`（`gh api repos/{o}/{r}/rules/branches/{branch}`，任何失败静默降级）；`git config --get-all cleanup.protect` 多值持久化；`remote_merged_candidates[].tip_sha`（供 `--force-with-lease` 删除使用）。`version_consistency_audit` 增加 `vendor|third_party|Pods|bower_components` 路径段排除、`inherited_version_files`（Cargo workspace 两种继承写法）、`packages` 真正填充。
- `references/common-pitfalls.md`：**"做了但没生效"类坑**（.gitignore 无前导斜杠会匹配任意层级、对已跟踪文件无效、`git check-ignore` 默认跳过已跟踪路径、`git add` 拒绝忽略文件、删除远程分支不带 lease 会丢别人的提交），每条附实测命令与现象。
- `docs/research/p2-verification.md`（1091 行）：对生态调研的**独立复核**——patch-id 口径纠错（survey 的"整段 vs 逐 commit"只对 squash 有效）、`gh` rules 端点纠偏、lease 数据丢失复现、worktree 判定、LICENSE 识别机制复刻（含 ±1% 边界不确定度声明）、`gitignore_consistency_audit` 的成本取舍。
- `assets/templates/status-report.md` 新增"✅ 你如何复核"小节：给出用户可复制粘贴的**只读**复核命令表。- **P6 度量基建（`evals/`）**：14 个 fixture（F1–F14）+ 40 条断言 + 双实现 runner（`fixtures.ps1`/`fixtures.sh`、`run_evals.ps1`/`run_evals.sh`），三层校验——严格 JSON（RFC 8259，拒绝裸控制字符）、`.sh`/`.ps1` 逐字段 parity、断言表。fixture 生成在系统临时目录（F1 是"非 git 目录"负例，放在仓库内会因向上找到本仓库而失效）。结果入库到 `evals/results/`。
- **P6 契约新增字段**：`has_remote`/`remote_host`/`unpushed_branches`/`default_branch_source`、`remote_reachable`、`release_signals`/`monorepo_mode`/`packages`/`target_version`、`docs_stale_candidates`、`remote_url_masked`/`gh_query_state`，以及各脚本的 `warnings[]`；`docs_needing_update` 更名 `docs_mentioning_changes`（旧名会被读成"文档无需更新"）；`consistent` 在无版本文件时为 `null`（空集"一致"是空洞真值）。
- **P6 新增文档与模板**：`references/version-file-inventory.md`（跨生态版本文件与 lockfile 详表）、`references/changelog-sections.md`（Keep a Changelog 六类分节表 + `hidden`/`skip` 语义 + 条目溯源守则）、`assets/templates/plan-table.md`（修复计划表）、`docs/QUALITY-AUDIT.md`（审计记录与回归清单）。
- **P6 脚本新参数**：`version_consistency_audit --target-version/--since-tag`；`next_steps_analysis --defaultBranch` 真正生效。- **P1 脚本解耦**：scripts/ 新增 bash（.sh）实现，与 PowerShell（.ps1）并行，覆盖 5 个采集脚本 + 共享助手 `scripts/_lib.sh`（无 bash-4 特性，兼容 macOS bash 3.2；GNU/BSD date）。
- `references/scan-recipes.md`：5 个脚本的 git 命令配方 + JSON 契约（单一事实源），.sh 与 .ps1 都照此对齐；含无脚本回退 3 步流程与依赖边界审计。
- `references/environment-and-prereqs.md` §6：Phase 0 shell 探测与路径选择（bash→.sh / pwsh→.ps1 / 无脚本回退）。
- `docs/DEVELOPMENT-PLAN.md`：跨 harness 通用化开发计划（P1–P5，版本贯穿保持 0.1.0）。
- 默认分支 master -> main。
- **P2 Agent Skills 标准对齐**：README 增加 `npx skills add cgartlab/attention` 安装路径与 skills.sh / Agent Skills 兼容徽章；确认 frontmatter（name+description）符合开放标准。
- **P5 多宿主 PR 指引**：`references/pr-and-remote-hosts.md` 扩为按宿主给真实 CLI + Web 回退——GitLab(`glab mr`)、Gitea/Codeberg(`tea pulls`)、Azure DevOps(`az repos pr`)、Bitbucket(Web)，不编造命令。
- **新能力 missing_core_docs**：`next_steps_analysis` 增加 `missing_core_docs` 信号，检测期望核心文档（README/CHANGELOG/LICENSE/AGENTS/CONTRIBUTING）中无匹配顶层文件者，让它出现在下一步建议里（.ps1 + .sh + scan-recipes 契约成对更新）。
- `AGENTS.md`：机器面 repo 指引（脚本黑盒/安全分层/报告大白话/版本策略/成对改脚本/自检），已被系统识别为 workspace 指令。
- `scripts/smoke_test.ps1` + `scripts/smoke_test.sh`：一键冒烟回归检查（跑 5 个采集脚本、验合法 JSON），pwsh 与 bash 成对；AGENTS.md 自检指向它。
- **生态调研**（`docs/ecosystem-survey.md` 主文档 + `docs/ecosystem-research/` 三份详报，共约 1700 行）：5 路并行取证 + 一手实测复核。覆盖同类 Agent Skill（git-repo-hygiene 等 23 个）、分支清理 CLI 9 个、版本/CHANGELOG 工具 7 个、守门工具链 8 个。含可信度分级（【实测】/【源码行】/【文档原文】/【待复核】/【推断】）与 4 级优先级可吸收清单（P0 3 项 / P1 6 项 / P2 8 项 / P3 5 项）。关键结论：立正是唯一具备 9 维能力全链路的 skill，但存在 3 项可实测证实的实现缺陷（`release_involved` 在 .ps1 恒 false、Cargo workspace 继承版本漏检、vendor/ 未排除）+ 1 项数据丢失风险（远程合并判定误用本地 base）。

### Changed
- **远程分支删除改为带 lease**：`git push origin --force-with-lease=<branch>:<sha> --delete <branch>`（`<sha>` 取审计时的 `tip_sha`）。不带 lease 的删除会在"等你确认"的窗口里**静默丢掉他人推送的提交**（已用裸仓库 + 两个 clone 复现数据丢失）；lease 的 refname 必须与分支完全同名，删除不存在的远程分支视为幂等成功。
- `docs/ecosystem-survey.md` 顶部加**勘误指针**（正文保留原样以维持可追溯性），指向 `docs/research/p2-verification.md`。
- 文档数字同步：19 个 fixture、65 条断言、493 checks。- **P6 SKILL.md 去冗余 + 补缺口**：删除全部内联"速查副本"（历次硬伤——force push 范围被窄化、受保护名单漏项、核心文档集三处不一致——**全部发生在副本一侧**），改为"路由 + 三条铁律"；新增 **Phase 2.5 意图分流**（工作区干净但用户明示发版/提 PR 时也走门槛与交付步骤——此前这类请求在字面流程里无家可归）；Phase 3B 补 **新建工作分支** 步骤；三道确认补 **非交互 fallback**（无 `ask_user_question` 时把计划写出来并**停下等确认**，禁止自批）；新增幂等、逐步 verify、开 PR 前查重、远程 URL 脱敏；报告新增可发布判定（READY / NOT READY / BLOCKED）与 CRITICAL/WARNING/SUGGESTION 分级。
- **P6 打包层**：`description` 补英文触发句（英文 harness 触发面）；新增 `compatibility` 字段（spec 六字段白名单之一）。过程中一度因该字段值含未加引号的 `": "` 导致 frontmatter 解析失败、skill 从技能目录消失——已改正。教训：改 frontmatter 后必须验证得能被加载。
- **P6 文档分层**：每条规则只在**一个**文件里给完整定义，其余只写路由，消除"同一规则两处写法不同"的漂移源。
- **P6 判定改为可判定**：远程剪枝从"远端已无对应 ref"（`fetch --prune` 之后恒假）改为"无开放 PR"，`gh_query_state != ok` 时降级为只报告；陈旧阈值明确为 `age_days > 30`；`unpushed_commits=null` 明确为"不可判定，不得判干净"；`git push` 明确属远程不可逆且**计划门槛不覆盖**；`git tag` 拆分本地/远程。- **内部代号 lizheng → attention**：仓库目录、skill frontmatter 的 `name`（`SKILL.md`）、evals 的 `skill_name`、安装路径（`~/.dsh/skills/attention`、`~/.claude/skills/attention`）、仓库地址（`cgartlab/attention`）与徽章、README/AGENTS/docs/references 中的代号引用全部对齐。中文名「立正」与触发词不变（去掉已失效的 "lizheng" 触发词）；`.gitignore` 的本地临时目录 `__lzsnap_test/` 同步改为 `__attention_test/`；版本仍为 0.1.0。
- 收尾报告改用大白话：主叙事面向项目作者（含刚入行的开发者），禁止字段名 / 命令串 / JSON 键进入主叙事，原始技术信号另放末尾"📋 技术细节（可选）"小节，主叙事必须能独立读懂。SKILL.md 的 Phase 4 新增"报告语言原则"小节并说明原因。

### Fixed
- **修 P6 引入的回归**：P6 把"本地合并判定"也统一改用 `origin/<默认分支>`，导致"本地已合并、尚未推送"的分支被**漏报成空集**（假阴性）。现本地用本地默认分支、远程用 `origin/<默认分支>`，并加基准守卫与 `remote-base-unverified` 警告。
- `vendor/` 未排除导致的假"版本不一致"（第三方内嵌依赖里的清单文件被当成自有版本文件）。
- Cargo workspace 成员继承版本不可见、`packages` 恒为空。- **P6 脚本 16 项成对修复**（`.sh` + `.ps1`，逐条对应 `evals/script-assertions.json` 的断言）：`--repo` 无效不再静默分析当前目录（改为明确报错）、`--repo` 漏值不再死循环、`.sh` 不再输出非法 JSON（裸控制字符）、`release_involved` 不再恒 false 且新增 `release_signals`、`package.json` 只取顶层 version、`todo_fixme` 覆盖未跟踪文件、所有 git 调用加 `-c color.ui=never`（修 `color.ui=always` 导致剪枝候选静默变空）、版本扫描尊重 `.gitignore`、宿主按主机名判定并脱敏、数组去重排序与大小写口径两实现统一、`recent_changed_files` 修根提交与合并提交边界（计数改用 `--first-parent`）。
- **P6 验证声明纠正**：`docs/VALIDATION.md` 中"`.sh` 与 `.ps1` 输出一致（parity 确认）"这一声明**已被实测证伪**（同仓库同参数下路径形态、数组顺序、取值位置均不同），现已删除；parity 改由 `evals/` 的断言真实保证。
- **P6 自检升级**：`smoke_test.{ps1,sh}` 改为双实现都跑 + 负例断言——此前 `.ps1` 版在**非 git 目录**上也会 5/5 通过，且两套冒烟互不交叉（`.ps1` 只测 `.ps1`），parity 永不可能被测到。- TODO 扫描排除自身源文件（`scripts/next_steps_analysis.ps1` 与 `.sh`），消除自指假阳性（dogfood 发现 P1 引入 .sh 后 .ps1 只排除 .ps1 导致自指 .sh，已修：两变体都排除两文件）。
- `AGENTS.md` 自检行更新此前因 `-like` 用半角冒号而行用全角冒号静默未生效，已用字面 .Replace 修正并指向 smoke_test。

- version_consistency_audit.sh 质量修复：去掉重复的 release_involved 二次扫描（改为首次扫描收集路径内联计算，与 .ps1 一致、更少代码）；修 find_versions 通配符模式未加引号导致 *.csproj 被 bash 预展开、漏掉子目录匹配的潜在 bug（现 -name "$1" 加引号）。已验 parity 与 .csproj 子目录用例。
### Notes
- **P6 验证方式**：`pwsh -NoProfile -File evals/run_evals.ps1` 与 `bash evals/run_evals.sh` —— 366/366 通过（14 fixture × 5 脚本 × 双实现 + 负例），两套 runner 均由独立实现写成并互相校验。改前同一套断言为红色（在原始 HEAD 上实测 **106 failed / 366**，证据 `evals/results/20260930-233235-ef75840-BASELINE-head.json`）。
- **不可测边界（诚实声明）**：远程操作、真实 GitHub PR 创建、`npx skills add` 安装链路在本开发环境**无法验证**——不把"跑不了"写成"通过"。详见 `docs/VALIDATION.md`。
- `docs/ecosystem-survey.md` 的 P0–P3 可吸收清单尚未逐项落地。该调研独立实测确认的三项缺陷（`release_involved` 恒 false、`vendor/` 未排除、远程合并判定误用本地 base）已由本次 P6 修复覆盖；**Cargo workspace 成员继承版本**已在后续一轮补齐（`inherited_version_files` + `packages`，fixture F16 覆盖两种写法 `version.workspace = true` 与 `version = { workspace = true }`）。
- `npx skills add cgartlab/attention` 安装路径需仓库推送到 GitHub 后方可验证；当前未推送（按计划推迟建远程）。

## [0.1.0] - 2026-09-29

首个可用版本。

### Added
- 立正核心工作流：Phase 0 前置探测 -> Phase 1 状态快照 -> Phase 2 干净/脏态分流 -> Phase 3A 干净同步 / 3B 脏态修复 -> Phase 4 收尾报告。
- 五个只读采集脚本（PowerShell）：git_state_snapshot / branch_cleanup_audit / version_consistency_audit / core_docs_relevance_scan / next_steps_analysis。
- 七份 references：环境与前置探测、判断标准、分支模型与保护、核心文档同步、发行版本、PR 与远程宿主、自主与安全。
- 四份 assets/templates：提交信息、PR body、CHANGELOG 条目、状态报告。
- 四个 evals（clean-sync / dirty-wip-fix / version-bump-release / non-github-fallback）及断言。
- LICENSE：CC-BY-NC-SA-4.0 完整 legalcode。
