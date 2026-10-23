# Changelog

本项目所有重要变更记录于此。格式参考 [Keep a Changelog](https://keepachangelog.com/)，版本号遵循 [语义化版本](https://semver.org/)。

> 版本策略：技能尚不完善，当前保持 0.1.0；以下未发布变更记于 [Unreleased]，待通用化成熟后由用户决定再切版本号。

## [Unreleased]

### Added
- **仓库转为公开（public），并补齐"公开可用"所需的一切**：README 徽章与安装说明改为公开口径（恢复 skills.sh 徽章、`checks` 557）；`npx skills add cgartlab/attention` **实测通过**（克隆公开仓库 → 识别 1 个 skill → 非交互安装到检测到的 harness）。
- **把"在用打包副本"的知识增量收进仓库**（此前仓库落后于正在被加载的副本，公开即等于发布更弱的版本）：`references/common-pitfalls.md` 7 条 → **19 条**（含"CI job 几秒零步骤失败 = 计费/额度"、"合并冲突的 PR 根本不触发 workflow"、"数字类陈述在多份文档里同时腐烂"、"只更新流程不更新任务清单"）；`judgment-criteria.md` 新增「被 main 取代的分支（superseded）」判定（与「无价值分支」区分：前者废弃、后者剪枝）；`environment-and-prereqs.md` 补"退出 0 但输出为空 = 不可用"（Windows 商店存根）；`release-versioning.md` 补"维护者指定版本号与语义冲突"的处置；`core-docs-sync.md` 补"开发计划/任务清单也是核心文档"与"文档里的命令示例是可执行断言"；`SKILL.md` 补"续做"触发、"作用域=当前仓库"、已 staged 改动危险、远程动作验收看目标端、追加提交后同步 PR 描述。
- **Phase 3C 值守循环（issue / PR）**：立正从"一次性收拾仓库"扩到"持续值守"——巡检 open issue → 按 triage 门选一个 → 查重（三条线索）→ 无 PR 则实现开 PR / 有 PR 则逐行评审并在隔离 worktree 实跑 → 过合并门四层 → 合并、或按判据评论/关闭。每轮只处理一个对象，幂等键为 issue 编号，进度只维护**一条**标记评论。流程单一事实源：`references/issue-pr-loop.md`。
- `references/judgment-criteria.md` 新增四组判定：**issue triage 门**（A 动作意图 / B 内容可执行 / C 未被占用，含 P0/P1 倾斜与 stale 规则）、**UI 视觉改动白名单**（强 UI / 疑似 UI / 边界，判定只看 diff 路径）、**合并门四层**（客观信号 / 内容门 / 授权门 / 动作门）、**PR/issue 关闭判据**（重复 / 已被默认分支覆盖 / 方向冲突 / 不可复现，且"先评论后关闭"）。
- `references/autonomy-and-safety.md` 动作档位表补齐三档：`gh pr merge`（须过合并门 + 有授权）、`gh pr close`/`gh issue close`(须先评论)、`gh issue/pr comment`/`gh pr review`（对外发言，需确认）；禁止清单新增五条（强 UI 自动合并、无授权合并、未评论关闭、未经确认对外发言、用旧截图冒充）。

### 裁定写入（用户逐条拍板的口径）
- **合并方式固定 squash**（`gh pr merge --squash`），不探测、不随仓库风格漂移。
- **授权来源只两条**：当前对话明说 > PR 带 `auto-merge` 标签；不引入仓库内授权配置文件。
- **UI 截图证据落独立分支** `attention/evidence-pr-<n>`（`docs/evidence/pr-<n>/`，raw URL 内联进 PR），不进默认分支。
- **不做定时值守**：一轮一件，下一轮必须由用户发起；被委派/无人值守时最高只能到 `PR READY`。
- **带图文档不算 UI**：任意 `.md` 里新增/修改图片引用 → 可自动合并；仅"文件名本身是视觉规范"（`design`/`visual`/`brand`/`logo`/`icon`/`theme`）仍按强 UI。
- 两个新模板：`assets/templates/pr-review.md`（逐行评审清单：结构 / 逻辑 / 跨平台双实现 / 验证 / 文档事实 / 安全 / 视觉，含"失败路径被吞"这类真实事故条目）、`assets/templates/issue-pr-comment.md`（进度 / 阻塞 / 关闭理由 / 合并证据 + 强 UI 等待确认四种骨架）。
- `assets/templates/status-report.md` 新增"本轮对象"一节（对象 / 做了什么 / 证据 / 结论 / 视觉判定）。

### Changed
- **脏态的提交权改为由意图决定**：用户要求"收拾/提交这个仓库"→ 按计划表提交；值守循环轮次里出现未提交改动 → 一律不提交、不 stash、不 pull，先问用户。此前循环沿用 3B 的自动提交，与"未提交改动禁止提交"的直接诉求冲突。
- `SKILL.md` 的职责边界随之调整为三段：一次性收拾止于"已推送 / PR 已开"；值守循环在授权门通过时可走到"已合并"；"已部署 / 用户可见"始终不在范围内。

### Docs
- **任务列表（`docs/DEVELOPMENT-PLAN.md`）新增 P7 阶段**：P1–P6 进度补齐，P7 记为 🔶 部分完成——规则与清单已交付（PR #19），代码阶段按用户裁定暂缓（零新增脚本），端到端验证受 GitHub Actions 计费阻塞；并列出可判定验收条件与"P7 仍未覆盖"（批量处理 / 定时值守 / 非 GitHub 宿主）。
- **核心文档同步**：`README.md` 补值守循环的触发说明与目录注释、断言数 81→83；`CONTRIBUTING.md` 硬规矩补"值守动作有独立档位、UI 永不自动合并"，PR 检查清单补逐行评审与截图两项；`docs/QUALITY-AUDIT.md` 新增 D12（fixture 生成静默失败 → 152 条假失败，属"失败不可见"类）。
- `AGENTS.md` 现状读数更新：规则仍 6 条，Phase 由 6 个增至 7 个（流程可以长，规则只减不增）。

## [0.1.1](https://github.com/cgartlab/attention/compare/v0.1.0...v0.1.1) - 2026-10-03
> **一句话概括**：本版把“交付策略”“信号去噪”“worktree 报告”写入规范，并更新 logo 与 app icon、修复文档勘误。对使用者：脏态判定更准确、worktree 报告更完整、品牌标识更清晰。**无需立即行动，常规拉取即可。**

### Added
- `assets/logo.svg` 重建为干净版（保留作者手绘的两条曲线 path + 双向渐变填充，去编辑器冗余，加 `prefers-color-scheme: dark` 深色适配与 `<title>` 无障碍标签）。
- 新增 `assets/app-icon.svg`（1024×1024、iOS 圆角矩形 `rx=228`、暗色底 + 蓝色渐变 A）。
- README 顶部居中展示 logo + 更新徽章组（移除私有仓库上失效的 skills.sh 徽章，加 release/CI/shell/runtime/checks 静态徽章与说明）。
- `branch_cleanup_audit` 新增 `worktree_branches(str[])` 报告字段（[#6](https://github.com/cgartlab/attention/pull/6)）：取 `git worktree list --porcelain` 的 `branch refs/heads/<name>` 行。**只报告、不作为删除判据**——`git branch -d` 与 `-D` 本身都拒绝删除被 worktree 检出的分支（实测确认），故这是报告层改进而非安全修复。

### Changed
- **交付策略（新规则）**：立正在其他项目上跑时，诊断阶段纳入排查过程中发现的小毛病（非用户主诉但真实存在）；最终交付物只有 PR（不创建 Issue）；收尾报告包含 PR 合并顺序建议（按依赖与风险排序）。
- `docs/ecosystem-survey.md` 正文两处内联勘误（[#5](https://github.com/cgartlab/attention/pull/5)，原句保留以维持可追溯）：§4.2 patch-id 口径"同时抓 squash + rebase"**只对 squash 成立**（多 commit rebase 需两侧逐 commit；cherry-pick 必然误报才是"只报告不删"的真正理由）；§4.5 rulesets 用法（列表端点不返回 `rules`/`conditions`，正确端点是 `rules/branches/{branch}`；分支不存在返回 `[]`+200 陷阱）。

### Fixed
- 采集信号去噪（[#4](https://github.com/cgartlab/attention/pull/4)）：`todo_fixme` 排除 `evals/` 测试数据（本仓库自身 6 条假阳性 → 0，fixture 里的 "TODO" 字样本就是测试数据）；`core_docs` 排除 `docs/research/` 与 `docs/ecosystem-research/` 调研目录（否则调研备忘被当核心文档，`docs_stale_candidates` 与 `docs_mentioning_changes` 充满噪音）。
- worktree 扫描的 PowerShell 实现改用 `GitOut`（[#6](https://github.com/cgartlab/attention/pull/6) 的 CI 双 job 全红根因）：`Git1` 只返回命令输出的**首行**，而 `git worktree list --porcelain` 首行是 `worktree <path>`、`branch refs/heads/<name>` 在后续行，导致 `.ps1` 恒返回空数组、与 `.sh` 的真实值持续 parity 失败。典型的"两套实现看着对称、助手语义却不同"。

## [0.1.0] - 2026-10-01

> **一句话概括**：首次公开发布（0.1.0），一次性并入此前 2026-09-29 内部初版以来的全部工作，包括商业级发布流水线、P0/P1 缺陷修复、P6 度量基建与契约、脚本 .sh/.ps1 解耦，以及代号从 lizheng 到 attention 的全面对齐。**你不需要做任何事——这是初始发布记录，供以后升级参考。**

首次公开发布（此前未对外发布过任何版本，故本次发布涵盖自 2026-09-29 内部初版以来的全部工作）。


### Added
- **发布流水线（商业级门禁与发布）**：新增 GitHub Actions 双 OS × 双 shell 门禁（`.github/workflows/ci.yml`：Windows 跑 pwsh runner、Linux 跑 bash runner，并含"非 git 目录必须判失败"的负例）；发布前只读闸门 `scripts/release_preflight.ps1|sh`（成对、判据一致：工作区干净 / 分支 / 版本一致性 / `[Unreleased]` / 三层校验 / 冒烟）；社区标准文件 `SECURITY.md`（含安全边界与私密漏洞上报）、`CONTRIBUTING.md`、`.github/CODEOWNERS`、`.github/dependabot.yml`。- **"立正巡自己"暴露并修掉的 4 处缺陷**（第三轮，来自对 attention 自身仓库跑一遍完整工作流）：
  - **无远程仓库被判成脏态**：`has_remote=false` 时 `unpushed_branches` 现输出 `[]`（没有远程就没有"未推送分支"概念），`unpushed_commits` 的 `null` 语义区分为**不适用**（新增 `no-remote` 警告），判定侧明确"纯本地仓库只看未提交改动"。此前会把一个完全干净的纯本地仓库判成脏态，然后去推送一个不存在的远程。
  - **空变更集时文档"陈旧候选"误报全部核心文档**：`docs_stale_candidates` 在变更集为空时现输出 `[]`（实测此前对本仓库列出全部 12 份核心文档）。
  - **`XXX` 误匹配临时文件模板**：todo pattern 改为 `TODO|FIXME|HACK|(^|[^X])XXX([^X]|$)`，不再命中 `mktemp ...XXXXXX`（实测 8 条命中里 2 条是这类假阳性）。
  - **看不见自己**：版本承载文件清单新增 `SKILL.md`（Agent Skill 的 frontmatter `metadata.version`），`test_commands` 新增识别 `evals/run_evals.*` 与 `scripts/smoke_test.*`（此前 `version_files=[]`+`consistent=null`、`test_commands=[]`）。
- **`references/common-pitfalls.md` 增补第 6 节**：删除远程分支不带 lease 会静默丢掉确认窗口内他人推送的提交（附复现与三个陷阱）。- **P0-1/P1 落地（第二轮，生态调研吸收）**：`branch_cleanup_audit` 的**本地/远程合并基准分离**（本地用本地默认分支、远程用 `origin/<默认分支>`）＋基准守卫（`local_merge_base`/`remote_merge_base`/`remote_base_unverified`）；`protected_from_rulesets`（`gh api repos/{o}/{r}/rules/branches/{branch}`，任何失败静默降级）；`git config --get-all cleanup.protect` 多值持久化；`remote_merged_candidates[].tip_sha`（供 `--force-with-lease` 删除使用）。`version_consistency_audit` 增加 `vendor|third_party|Pods|bower_components` 路径段排除、`inherited_version_files`（Cargo workspace 两种继承写法）、`packages` 真正填充。
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

- **吸收 neat-freak 的治理机制（第三轮）**：`references/common-pitfalls.md` 新增第 7 条"同类问题第三次出现 → 散文约束不够，该上机制"——判据为同一规则被违反 3 次即属结构性缺口，应换成机器可判的 check/hook/test；同时明确**立正只建议、不擅自装钩子**（装钩子改用户开发流程，属本地变更需计划批准，且可能与其既有 pre-commit 框架冲突）与对应报告话术。

- **发布流水线（商业级门禁与发布）**：新增 GitHub Actions 双 OS × 双 shell 门禁（`.github/workflows/ci.yml`：Windows 跑 pwsh runner、Linux 跑 bash runner，并含"非 git 目录必须判失败"的负例）；发布前只读闸门 `scripts/release_preflight.ps1|sh`（成对、判据一致：工作区干净 / 分支 / 版本一致性 / `[Unreleased]` / 三层校验 / 冒烟）；社区标准文件 `SECURITY.md`（含安全边界与私密漏洞上报）、`CONTRIBUTING.md`、`.github/CODEOWNERS`、`.github/dependabot.yml`。- 立正核心工作流：Phase 0 前置探测 -> Phase 1 状态快照 -> Phase 2 干净/脏态分流 -> Phase 3A 干净同步 / 3B 脏态修复 -> Phase 4 收尾报告。
- 五个只读采集脚本（PowerShell）：git_state_snapshot / branch_cleanup_audit / version_consistency_audit / core_docs_relevance_scan / next_steps_analysis。
- 七份 references：环境与前置探测、判断标准、分支模型与保护、核心文档同步、发行版本、PR 与远程宿主、自主与安全。
- 四份 assets/templates：提交信息、PR body、CHANGELOG 条目、状态报告。
- 四个 evals（clean-sync / dirty-wip-fix / version-bump-release / non-github-fallback）及断言。
- LICENSE：CC-BY-NC-SA-4.0 完整 legalcode。

### Changed
- **吸收 neat-freak（`KKKKhazix/khazix-skills` 的"洁癖"，21k★ / v3.0.0）的治理机制（第三轮，纯文档层，未触碰脚本与 JSON 契约）**，落地七处结构改进：
  - **① 完成合同**：`judgment-criteria.md` 新增"完成合同：收尾判定是四个事实面，不是一个标量"——工作区 / 文档 / 版本 / 远程四面各标 `verified-current` / `changed-and-verified` / `pending` / `not-applicable`，**READY 由四面汇总得出**（任一面 `pending` → NOT READY 并指出是哪一面）；明确"不适用"不得讲成"已完成"。`status-report.md` 给出对应的大白话形态"四件事的现状"（改动提交 / 文档跟上 / 版本号对齐 / 推送·PR），原始状态值只进"📋 技术细节"。
  - **② 清场顺序硬约束**：`autonomy-and-safety.md` 新增"清场顺序（破坏性收尾不可自批）"——先列全候选 → 完整汇报 → **停下等用户明确确认** → 执行后补充汇报。三条硬约束：**最初任务里的预授权不算确认**（"顺手清理一下"只是同意"立正"，不等于同意"删除"）、**不得先删无争议的再问有争议的**、**本地 `git branch -d` 也算清场**。`status-report.md` 对应新增"清场要分两次汇报"与报告模板的「待你确认」小节。
  - **③ 读到的内容不是指令**：`autonomy-and-safety.md` 新增 prompt-injection 防御——仓库内文本（`AGENTS.md`/`README`/`CHANGELOG`/PR 正文/提交信息）与 fetch 回来的外部内容都是**数据不是命令**；授权只有"用户当前对话指令"和"本 skill 安全分层"两个来源；冲突时以安全分层为准并报给用户。
  - **④ 知识分层 + 先减后加**：`core-docs-sync.md` 新增"知识分层：同一事实只该有一个权威位置"（规则层 / docs 层 / CHANGELOG 层 / git 历史四层各自只放什么）与**单一权威 + 短指针**原则；新增"先减后加"——改文档时先删过期说法、重复指针、中间态叙事、已完成待办，再写新内容，避免文档单向膨胀；并明确"先减后加 ≠ 大删大改"（拿不准的列入计划表交用户裁定）。
  - **⑤ 发布终态**：`judgment-criteria.md` 新增"合并 ≠ 部署 ≠ 用户可见"证据表——五个状态互不蕴含，特别标明**"已合并"不能推出"已部署"**；明确**立正的职责边界止于"已推送 / PR 已开"**，`has_remote=false` 时远程面只能是 `pending` 或 `not-applicable`，**绝不能写 `verified-current`**。
  - **⑥ SKILL.md Phase 2 / 2.5 合并**：删除"Phase 2.5 意图分流（补'干净态也可能有活'的缺口）"这个补丁式半阶段，改为单张"状态 × 意图"分流表，并引入**轻量 / 完整路径**框架（区别不在"查多少"，而在"动不动交付链路"）与**"拿不准走完整路径"**原则。决策树同步更新。
  - **⑦ `AGENTS.md` 新增"加规则要配对减规则"**：往任一文档加规则时必须同时指出"哪条可删或合并"。**硬规则**是 `SKILL.md` 元规则（核心理念 + 铁律）的**净增长必须 ≤ 0**——加一条就删或合并一条；做不到须在提交信息里说明理由。附现状读数（核心理念 3 + 铁律 3 = 6 条，对 6 个 Phase，已达预算）。这是抑制"每次修 bug 就留一条永久规则"这一单向膨胀的刹车。
  - 本轮（neat-freak 吸收）的变更范围仅限 `.md`：`SKILL.md`、`AGENTS.md`、`README.md`、`references/{autonomy-and-safety,core-docs-sync,judgment-criteria,common-pitfalls}.md`、`assets/templates/status-report.md`、`docs/{VALIDATION,DEVELOPMENT-PLAN}.md`、本文件。**未触碰任何脚本、`scan-recipes.md` 契约或 `evals/script-assertions.json` 断言**，故本轮无需同步断言表。
- **远程分支删除改为带 lease**：`git push origin --force-with-lease=<branch>:<sha> --delete <branch>`（`<sha>` 取审计时的 `tip_sha`）。不带 lease 的删除会在"等你确认"的窗口里**静默丢掉他人推送的提交**（已用裸仓库 + 两个 clone 复现数据丢失）；lease 的 refname 必须与分支完全同名，删除不存在的远程分支视为幂等成功。
- `docs/ecosystem-survey.md` 顶部加**勘误指针**（正文保留原样以维持可追溯性），指向 `docs/research/p2-verification.md`。
- 文档数字同步：21 个 fixture、81 条断言、553 checks（后续轮次继续增长）。- **P6 SKILL.md 去冗余 + 补缺口**：删除全部内联"速查副本"（历次硬伤——force push 范围被窄化、受保护名单漏项、核心文档集三处不一致——**全部发生在副本一侧**），改为"路由 + 三条铁律"；新增 **Phase 2.5 意图分流**（工作区干净但用户明示发版/提 PR 时也走门槛与交付步骤——此前这类请求在字面流程里无家可归）；Phase 3B 补 **新建工作分支** 步骤；三道确认补 **非交互 fallback**（无 `ask_user_question` 时把计划写出来并**停下等确认**，禁止自批）；新增幂等、逐步 verify、开 PR 前查重、远程 URL 脱敏；报告新增可发布判定（READY / NOT READY / BLOCKED）与 CRITICAL/WARNING/SUGGESTION 分级。
- **P6 打包层**：`description` 补英文触发句（英文 harness 触发面）；新增 `compatibility` 字段（spec 六字段白名单之一）。过程中一度因该字段值含未加引号的 `": "` 导致 frontmatter 解析失败、skill 从技能目录消失——已改正。教训：改 frontmatter 后必须验证得能被加载。
- **P6 文档分层**：每条规则只在**一个**文件里给完整定义，其余只写路由，消除"同一规则两处写法不同"的漂移源。
- **P6 判定改为可判定**：远程剪枝从"远端已无对应 ref"（`fetch --prune` 之后恒假）改为"无开放 PR"，`gh_query_state != ok` 时降级为只报告；陈旧阈值明确为 `age_days > 30`；`unpushed_commits=null` 明确为"不可判定，不得判干净"；`git push` 明确属远程不可逆且**计划门槛不覆盖**；`git tag` 拆分本地/远程。- **内部代号 lizheng → attention**：仓库目录、skill frontmatter 的 `name`（`SKILL.md`）、evals 的 `skill_name`、安装路径（`~/.dsh/skills/attention`、`~/.claude/skills/attention`）、仓库地址（`cgartlab/attention`）与徽章、README/AGENTS/docs/references 中的代号引用全部对齐。中文名「立正」与触发词不变（去掉已失效的 "lizheng" 触发词）；`.gitignore` 的本地临时目录 `__lzsnap_test/` 同步改为 `__attention_test/`；版本仍为 0.1.0。
- 收尾报告改用大白话：主叙事面向项目作者（含刚入行的开发者），禁止字段名 / 命令串 / JSON 键进入主叙事，原始技术信号另放末尾"📋 技术细节（可选）"小节，主叙事必须能独立读懂。SKILL.md 的 Phase 4 新增"报告语言原则"小节并说明原因。

- **`SKILL.md` 按"加规则要配对减规则"做了一次净减**：把散落在各节的条文下沉到 references/templates（逐条核对其内容均有权威定义、无丢失），只保留**核心理念 3 条 + 三条铁律 3 条 = 6 条**（对 6 个 Phase，已达预算；原为 10 条元规则 + 15 条各节条文）。文件 188 → ~160 行，保留"路由 + 流程"结构。
- **Agent Skill 版本承载位置**写入 `references/version-file-inventory.md`（`SKILL.md` frontmatter、`.claude-plugin/plugin.json`）。
- **判定与流程口径**：`has_remote=false` 时"未推送提交/分支"两条不参与脏态判定（`judgment-criteria.md`）；Phase 3A 明确"没有配远程"与"远程连不上"是两件事。
### Fixed
- **修 P6 引入的回归**：P6 把"本地合并判定"也统一改用 `origin/<默认分支>`，导致"本地已合并、尚未推送"的分支被**漏报成空集**（假阴性）。现本地用本地默认分支、远程用 `origin/<默认分支>`，并加基准守卫与 `remote-base-unverified` 警告。
- `vendor/` 未排除导致的假"版本不一致"（第三方内嵌依赖里的清单文件被当成自有版本文件）。
- Cargo workspace 成员继承版本不可见、`packages` 恒为空。- **P6 脚本 16 项成对修复**（`.sh` + `.ps1`，逐条对应 `evals/script-assertions.json` 的断言）：`--repo` 无效不再静默分析当前目录（改为明确报错）、`--repo` 漏值不再死循环、`.sh` 不再输出非法 JSON（裸控制字符）、`release_involved` 不再恒 false 且新增 `release_signals`、`package.json` 只取顶层 version、`todo_fixme` 覆盖未跟踪文件、所有 git 调用加 `-c color.ui=never`（修 `color.ui=always` 导致剪枝候选静默变空）、版本扫描尊重 `.gitignore`、宿主按主机名判定并脱敏、数组去重排序与大小写口径两实现统一、`recent_changed_files` 修根提交与合并提交边界（计数改用 `--first-parent`）。
- **P6 验证声明纠正**：`docs/VALIDATION.md` 中"`.sh` 与 `.ps1` 输出一致（parity 确认）"这一声明**已被实测证伪**（同仓库同参数下路径形态、数组顺序、取值位置均不同），现已删除；parity 改由 `evals/` 的断言真实保证。
- **P6 自检升级**：`smoke_test.{ps1,sh}` 改为双实现都跑 + 负例断言——此前 `.ps1` 版在**非 git 目录**上也会 5/5 通过，且两套冒烟互不交叉（`.ps1` 只测 `.ps1`），parity 永不可能被测到。- TODO 扫描排除自身源文件（`scripts/next_steps_analysis.ps1` 与 `.sh`），消除自指假阳性（dogfood 发现 P1 引入 .sh 后 .ps1 只排除 .ps1 导致自指 .sh，已修：两变体都排除两文件）。
- `AGENTS.md` 自检行更新此前因 `-like` 用半角冒号而行用全角冒号静默未生效，已用字面 .Replace 修正并指向 smoke_test。

- version_consistency_audit.sh 质量修复：去掉重复的 release_involved 二次扫描（改为首次扫描收集路径内联计算，与 .ps1 一致、更少代码）；修 find_versions 通配符模式未加引号导致 *.csproj 被 bash 预展开、漏掉子目录匹配的潜在 bug（现 -name "$1" 加引号）。已验 parity 与 .csproj 子目录用例。
- **修 `gh_authed` 的既存 flake**：两套实现原先用会联网的 `gh auth status` 退出码判定登录态，并发/繁忙时偶发非 0 → 被写成事实性的"未认证"并连带翻转 `gh-host-mismatch` 警告，违反"没查成必须留痕"的契约。现改用**本地无网络探测**（`gh auth token` 退出码）；网络可达性由 `remote_reachable`/`gh_query_state` 单独表达。
### Notes
- **P6 验证方式**：`pwsh -NoProfile -File evals/run_evals.ps1` 与 `bash evals/run_evals.sh` —— 366/366 通过（14 fixture × 5 脚本 × 双实现 + 负例），两套 runner 均由独立实现写成并互相校验。改前同一套断言为红色（在原始 HEAD 上实测 **106 failed / 366**，证据 `evals/results/20260930-233235-ef75840-BASELINE-head.json`）。
- **不可测边界（诚实声明）**：远程操作、真实 GitHub PR 创建、`npx skills add` 安装链路在本开发环境**无法验证**——不把"跑不了"写成"通过"。详见 `docs/VALIDATION.md`。
- `docs/ecosystem-survey.md` 的 P0–P3 可吸收清单尚未逐项落地。该调研独立实测确认的三项缺陷（`release_involved` 恒 false、`vendor/` 未排除、远程合并判定误用本地 base）已由本次 P6 修复覆盖；**Cargo workspace 成员继承版本**已在后续一轮补齐（`inherited_version_files` + `packages`，fixture F16 覆盖两种写法 `version.workspace = true` 与 `version = { workspace = true }`）。
- `npx skills add cgartlab/attention` 安装路径需仓库推送到 GitHub 后方可验证；当前未推送（按计划推迟建远程）。
