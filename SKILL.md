---
name: attention
description: 立正——任意 Git 项目的"站好队"巡检与修复 skill。当用户说"立正"，或在 git 项目中说"同步/整理/检查/提交这个项目""把项目弄干净""该提交了""开个 PR""让项目归位/就绪/可发布"等同义意图时激活：自动检测开发状态——干净则拉取最新默认分支、清理已合并的无价值分支、给下一步开发方向；有未提交/未推送改动则思考修复计划并自动执行，提交前严格保证核心文档同步真实最新变化、发行版本号一致，完成后开新 PR。即使用户没说"立正"，只要在 git 项目里表达"让项目归位/就绪/可发布"的意图就应使用本 skill。Use this skill whenever the user asks to sync, tidy up, check, commit, or open a PR for a git repository, or asks whether a project is ready to ship — even if they don't say "attention".
license: CC-BY-NC-SA-4.0
compatibility: Requires git (mandatory). gh optional (PR/issue queries; degrades to PR-ready artifacts). Bundled scripts need bash or PowerShell 7 — falls back to running git recipes manually. All analysis is local — no third-party services, no network calls beyond the repo's own remote.
metadata:
  version: "0.1.0"
  date: "2026-09-29"
  reference: "https://github.com/cgartlab/attention"
---

# 立正Skill

任意 Git 项目的"站好队"巡检与修复。一次调用，让项目回到可发布状态：要么干净同步并给出方向，要么把散落的改动想清楚、修好、文档与版本对齐、开成 PR。

## 核心理念

- **状态优先，动作在后**：先看清仓库现在是什么样子，再决定动不动手。干净与脏态走两条完全不同的路，绝不混用。
- **只动该动的**：本地变更可以批，远程不可逆动作必须再确认；永远不 force push、不删受保护分支、不删未合并分支。
- **事实不得编造**：文档同步只反映真实 diff 支撑的变化，版本号只来自真实版本文件，下一步建议只基于真实信号（近期提交、开放 issue/PR、TODO、测试信号）。缺的标 ［待补充：…］，不替用户圆上。
- **两阶段诊断**：脏态修复时，先一次性把问题找全、出清单，再逐条处理——禁止边找边改。
- **门槛即护栏**：文档同步门槛与发行版本门槛放在提交之前，不是提交之后补救。
- **失败必须可见**：采集失败、查询失败、降级都要留痕（`warnings[]` 或字段置 `null`）。把"没查成"写成"没有"是最危险的编造，因为它看起来像事实。
- **幂等**：重复运行不得产生重复提交或重复 PR；发现同意图的分支/PR 存在就报告并停，不叠加。

## 何时使用

- 用户明示"立正"。
- 在 git 项目里，用户说"同步/整理/检查/提交这个项目""把项目弄干净""该提交了""开个 PR""让项目归位/就绪/可发布"等。

## 何时不用

- 非 git 仓库（探测到非 git → 说明并停止，不做任何改动）。
- 用户只是问一个 git 命令怎么写、或只想看某个文件——直接答，别启动整套巡检。

## 不可让渡的三条铁律（本文件**只做路由，不复述细则**）

1. **禁止清单以 `references/autonomy-and-safety.md` 为准**，本文件不重列。
2. **判定定义（干净/脏态、无价值分支、涉及 release、核心文档集、阈值）以 `references/judgment-criteria.md` 为准。**
3. **脚本 JSON 契约以 `references/scan-recipes.md` 为准**（字段名、类型、`null` vs `[]` 语义、路径形态）。

> 为什么把细则全部移出去：本文件此前内联了各 reference 的"速查副本"，而历次漂移**全部发生在副本一侧**——副本把 force push 的禁止范围从"默认分支或受保护分支"窄化成"默认分支"，漏掉 `release/*` 受保护、detached HEAD 禁止提交、禁止自动改 `.git/config` 等条目。副本是唯一保证被加载的文本，于是更弱的规则成了实际执行的规则。**只保留路由，矛盾就没有了生长点。**

## 环境与前置探测（Phase 0，先做）

每次激活先做前置探测，细则见 `references/environment-and-prereqs.md`。六件事：是不是 git 仓库、默认分支、远程宿主、gh 鉴权、项目画像、shell 选择。

两条最容易错、必须照做的：

- **shell 探测要"跑一次"而不是"看文件在不在"**：`C:\Program Files\Git\bin\bash.exe` 在受限沙箱里存在但一启动就失败（cygwin 信号管道被拒）。判据是 `bash -c 'echo ok'` 能否退出 0，不是 `Test-Path`。
- **默认分支不得想当然**：探测不到就按 reference 的梯子回退，仍不确定就问用户——`main` 是猜的，`pull --ff-only` 与剪枝判断会跟着一起错。

## 脚本使用约定

本 skill 在 `scripts/` 下提供黑盒数据采集脚本（bash `.sh` 与 PowerShell `.ps1` 两套）。它们处理确定、重复、可验证的采集，把结构化 JSON 交给你推理。

- **先 `--help`，再调用**。除非 `--help` 不够用，不要读脚本源码——它们存在是为了被调用，不是为了被读进上下文。
- **脚本只做只读采集与候选计算**，绝不自己提交、推送、删分支、开 PR。所有变更动作由你按本工作流显式执行。
- **`--repo` 必须给对**：脚本会校验路径；传错路径会明确报 `repo path not found`，不会退回当前目录。若你看到 `is_git=false`，先确认路径，别当成"仓库有问题"。
- **读 `warnings[]`**：它标记了本次采集的降级（`gh-query-failed`、`remote-unreachable`、`no-version-files`、`partial-parse` 等）。有警告时，相关字段可能是 `null`——**不要把 `null` 讲成"没有"**。
- **双实现**：两套输出同形 JSON（契约见 `references/scan-recipes.md`），按 environment-and-prereqs 探测结果选一条。

## 工作流总览（决策树）

```
Phase 0 前置探测（非 git → 停）
   |
Phase 1 状态快照（黑盒脚本出 JSON）
   |
Phase 2 状态判定：有未提交改动 / 未推送提交 / 未推送分支？
   |
Phase 2.5 意图分流（干净态也可能有活要干：用户明示发版、要开 PR、要提交）
   ├─ 日常同步            → Phase 3A
   ├─ 有改造/交付意图      → Phase 3B 的门槛与交付步骤（即使工作区干净）
   └─ 无事可做            → Phase 3A 的建议部分
   |
Phase 4 收尾报告（含可发布判定）
```

## Phase 1 — 状态快照

先 `--help`，再调用，拿到 JSON 后推理（字段语义见契约，不要凭字段名猜）：

- `scripts/git_state_snapshot` — 分支、upstream、ahead/behind、staged/unstaged/untracked、stash、未推送提交与**未推送分支**、远程信息。
- `scripts/branch_cleanup_audit` — 已合并候选、陈旧未合并（只报告）、受保护名单、远端可达性。
- `scripts/version_consistency_audit` — 版本文件与版本串是否一致、发布信号（`release_signals`）、monorepo 检测。
- `scripts/core_docs_relevance_scan` — 核心文档与变更的交叉引用（**低精度提示**，不是"文档无需更新"的裁决）。
- `scripts/next_steps_analysis` — 下一步建议信号（近期提交、开放 issue/PR、TODO、缺失文档、测试命令）。

> 拿齐四份快照再进 Phase 2。不要边拿边下结论。

## Phase 2 — 状态判定

判定定义见 `references/judgment-criteria.md`，本文件不复述。要点只有一条：**判定要保守**——拿不准归脏态，让人看一眼，而不是默认"应该是干净的"。

## Phase 2.5 — 意图分流（补"干净态也可能有活"的缺口）

状态干净不等于用户没诉求。先分开看：**仓库状态**（Phase 2）与**用户意图**（本节），再决定走哪条路。

| 状态 | 用户意图 | 走法 |
|---|---|---|
| 干净 | 只想同步/看看 | Phase 3A |
| 干净 | 明示发版、要对齐版本号、要开 PR、要提交某处改动 | **Phase 3B 的门槛与交付步骤**（文档门槛 → 版本门槛 → 建分支提交 → 推 PR）；不存在"没有未提交改动所以什么都不做"这一说 |
| 脏 | 任意 | Phase 3B |
| 非 git | 任意 | 说明并停 |

典型例子：用户说"这次改了 package.json 的版本号要发版，把 Cargo 那边也对齐，然后提 PR"，而那个版本改动**已经提交**、工作区是干净的——按状态它属干净态，但用户的诉求是真实交付任务，必须走 3B 的门槛与交付步骤。

## Phase 3A — 干净态处理

1. `git fetch` + 对默认分支 `git pull --ff-only`。只快进：若有分叉（非快进）→ 停止并报告，绝不合并提交、绝不 force。理由：干净态的目标是同步，不是消化本地分叉。
2. **剪枝已合并分支**：用 `branch_cleanup_audit` 的候选——仅删"已完全合并入默认分支 且 不在受保护名单"者。陈旧未合并分支只报告不删（删了会丢工作）。
   - **先列候选、再执行一次轻量确认**：干净态没有计划门槛，而删分支是本地变更动作——把"将删除 / 将保留（附原因）"列成表，用户点头后执行。无交互环境见下方"非交互环境"。
   - 本地：`git branch -d`（`-d` 本身就拒删未合并，作为第二道保险）。远程：按 `references/autonomy-and-safety.md` 做最终确认；远端不可达（`remote_reachable=false`）时**不要**说"没有可清理的远程分支"，要说"没查成"。
3. **下一步建议**：用 `next_steps_analysis` 的信号给可执行方向，只基于真实信号。
4. 若为了 pull 切换过分支，收尾切回原分支。

## Phase 3B — 修复与交付路径

> 本路径同时服务"脏态修复"与"干净态但有交付意图"（Phase 2.5）。若工作区本来就干净，第 1、4 步可能是空转——照走，不要跳过门槛。

1. **诊断**：用 `git_state_snapshot` 归类未提交/未推送改动（WIP 功能 / 构建破损 / 半成品）。两阶段：先诊断全找全，出问题清单，禁止边找边改。
2. **修复计划 + 计划表**：基于 diff 给出具体可发布化计划，并**列成表**（模板见 `assets/templates/plan-table.md`）：将创建 / 将更新 / 将跳过（附原因） / 需你确认。用 `ask_user_question` 呈现，一次批准覆盖后续本地动作（编辑、测试、提交、**本地**分支删除）。**推送不在此列**——push/PR/删远程分支/推 tag 属远程不可逆动作，执行点另做最终确认。
3. **工作分支（必做，不可省）**：若当前分支在受保护名单内（例如你正站在 `main` 上），先 `git switch -c <type>/<slug>`——命名沿用仓库既有习惯（从 `git log` / `git branch` 实测得出，别自创风格）。**禁止直接在默认分支上提交并推送**。无法建分支（detached HEAD、权限不足）→ 停止并报告，不要硬来。
4. **执行修复 + 逐步 verify**：应用编辑，每个改动点后立刻验证（跑测试 / 回读文件 / 重跑相关脚本）再进下一步。跑测试/lint/build，迭代至绿；绿不了就如实报告阻塞器，不硬提交。
5. **文档同步门槛（提交前）**：跑 `core_docs_relevance_scan`，按 `references/core-docs-sync.md` 把核心文档更新到反映真实 diff；写 CHANGELOG 条目时按 `references/changelog-sections.md` 决定分节与可见性（`hidden` / `skip` 是两件事）。**注意该扫描是低精度提示**：`docs_mentioning_changes=[]` 不代表文档已同步（文档只写函数名不写文件名时它必然为空），`docs_stale_candidates` 才是"请人工确认"的清单。只反映真实变化，缺的标 ［待补充：…］。**含未消解 ［待补充］ 的文档要么不进提交，要么在 PR body 显式列为阻塞项。**
6. **发行版本门槛（提交前）**：按 `references/judgment-criteria.md` 的**多层门**判定——脚本给出 `release_signals`（宽口径信号：触及版本文件 / `chore(release)` / `feat!`·`fix!` / `BREAKING CHANGE` footer / `fix:`），**是否真的 bump 由你结合用户意图判定**，并说明理由。判定为需要 bump 时：跑 `version_consistency_audit` 一致 bump 所有版本文件、补 CHANGELOG 条目、记录 tag 计划。`consistent=null`（没有版本文件）时不要声称"版本已一致"。
7. **提交**：按探测到的提交规约（conventional commits 等），一个提交一个意图；body 讲 **WHY**（diff 已经说明 WHAT）。提交信息模板见 `assets/templates/commit-message.md`。
8. **推送与开 PR**：推送前做**远程动作最终确认**。GitHub → `gh pr create`（模板见 `assets/templates/pr-body.md`）；非 GitHub 或 CLI 不可用或远程不可达 → 输出 PR/MR 就绪产物（分支、diff 概览、建议标题/正文、手动指引），**不编造**宿主专属命令。开 PR 前先查是否已有同题开放 issue/PR（`gh_query_state="ok"` 时才作数），避免重复。

## Phase 4 — 收尾报告

用 `assets/templates/status-report.md` 输出：改了什么、清理了什么、PR 链接（或手动指引）、下一步建议，以及**一句可发布判定**（`可发布 / 还差几步 / 被阻塞`，对应模板里的 READY / NOT READY / BLOCKED），关键项按 CRITICAL / WARNING / SUGGESTION 分级。让用户一眼看清这次"立正"做了什么、能不能发。

### 报告语言原则（重要）

报告是给**人**看的——通常是项目作者，其中不少是刚入行的开发者。他们要的是"我的项目现在怎样、我接下来该做什么"，而不是一行行 JSON 字段名或 git 底层命令。一份满是字段名的报告，新手看不懂、老手也得多想一层，对项目质量提升零帮助——报告的价值在于让用户**立刻知道下一步干什么**，大白话是达成这个价值的最低门槛。

- **主叙事用大白话**：把每个发现和动作翻译成"对你的项目意味着什么"。说"我删掉了一个已经合并完、不再需要的旧分支"，而不是把 `local_merged_candidates=[feature/x]` 甩给用户。
- **禁止在主叙事里堆技术凭证**：`is_github=false`、`version_files=[]`、`git symbolic-ref` 这类是后台采集的事实，不是给用户的结论。
- **下一步建议要说人话**：每条 = 现状（大白话）→ 该做什么（大白话）→ 为什么对项目好（大白话）。
- **没做就说没做，并解释为什么**：不写"未执行（无远程）"，写"没连上远程仓库，所以这步跳过了——连上后我帮你同步"。
- **失败要如实说**：远程连不上、gh 没查成、测试没跑起来，都要写成"没查成/没跑成"，不能写成"没有"。
- **技术细节可以留，但分开另放**：给想核对的人留原始信号，放报告末尾一个清晰的"📋 技术细节（可选，新手可跳过）"小节；主叙事必须能独立读懂。
- **脱敏**：写入报告或输出的远程 URL 不得包含凭据（token/用户名密码），用 `remote_url_masked`。

## 安全、幂等与边界情形

- **分层确认模型、永远禁止清单、边界处理**：全部以 `references/autonomy-and-safety.md` 为准（本文件不复述）。其中一条值得在这里重复，因为它是行为底线：**永远不删默认/受保护分支，永远不 force push**。
- **幂等**：执行前先查是否已有同意图的工作分支或开放 PR；有就报告并停，不重复提交、不重复开 PR。
- **非交互环境（delegated / 无人值守 / 无 `ask_user_question`）**：把计划或候选**写在回复里并停下等待确认**，**不得自行批准**。没有交互能力时，只读分析可以照做，一切变更动作与远程动作都必须停在确认点。这是硬规则——把"没人可问"当成"默认同意"会直接绕过分层确认模型。
- **常见边界**（细则见 references）：detached HEAD、零提交仓库、stash、未跟踪半成品、无远程、远程不可达、monorepo。半成品文件**不得删除**；stash 只报告不 `drop`/`apply`。

## references 索引（按需读，别全读）

| 文件 | 何时读 |
|------|--------|
| `references/scan-recipes.md` | **脚本 JSON 契约（单一事实源）**：字段语义、`null` vs `[]`、无脚本回退配方 |
| `references/environment-and-prereqs.md` | Phase 0 探测细则与适配（含 shell 探测、Windows 回退） |
| `references/judgment-criteria.md` | 判定分流、各定义的精确边界、涉及 release 的多层门 |
| `references/branch-model-and-protection.md` | 默认分支探测、受保护名单、剪枝规则 |
| `references/core-docs-sync.md` | 核心文档集、差异驱动更新法、反幻觉与溯源 |
| `references/release-versioning.md` | 各生态版本文件、一致性规则、CHANGELOG |
| `references/changelog-sections.md` | CHANGELOG 分节表、`hidden` vs `skip`、条目溯源要求（写 CHANGELOG 前读） |
| `references/version-file-inventory.md` | 版本文件与 lockfile 的跨生态详表（判断"还有哪个文件要同步"时读） |
| `references/pr-and-remote-hosts.md` | gh PR 模板、非 GitHub 与远程不可达的降级 |
| `references/autonomy-and-safety.md` | 分层确认模型、禁止动作、边界情况 |
| `docs/ecosystem-research/` 与 `docs/ecosystem-survey.md` | **研究备忘，非默认加载**：发布自动化、分支清理、相邻 skill 生态的调研。只在需要对齐行业做法或判断字段边界时读 |

## assets/templates 索引

- `assets/templates/commit-message.md` — 提交信息规约与示例（含 body 讲 WHY）
- `assets/templates/pr-body.md` — PR 描述结构
- `assets/templates/changelog-entry.md` — CHANGELOG 条目结构（Keep a Changelog 六类）
- `assets/templates/plan-table.md` — 修复计划表（将创建/更新/跳过/需确认）
- `assets/templates/status-report.md` — 收尾报告结构（含可发布判定）

## scripts 索引（黑盒，先 --help）

| 脚本 | 作用 |
|------|------|
| `scripts/git_state_snapshot` | 仓库状态快照（分支/upstream/改动/stash/未推送提交与分支/远程） |
| `scripts/branch_cleanup_audit` | 分支剪枝候选审计（已合并/陈旧/受保护/远端可达性） |
| `scripts/version_consistency_audit` | 版本一致性 + 发布信号 + monorepo 检测 |
| `scripts/core_docs_relevance_scan` | 核心文档与变更交叉引用扫描 |
| `scripts/next_steps_analysis` | 下一步建议信号采集 |
