---
name: attention
description: 立正——任意 Git 项目的"站好队"巡检与修复 skill。当用户说"立正"，或在 git 项目中说"同步/整理/检查/提交这个项目""把项目弄干净""该提交了""开个 PR""让项目归位/就绪/可发布"等同义意图时激活：自动检测开发状态——干净则拉取最新默认分支、清理已合并的无价值分支、给下一步开发方向；有未提交/未推送改动则思考修复计划并自动执行，提交前严格保证核心文档同步真实最新变化、发行版本号一致，完成后开新 PR。也用于**值守循环**：巡检 open issue、处理某个 issue/PR、把 PR 评审到可合并、要我决定合并/回复/关闭时使用（Phase 3C）。即使用户没说"立正"，只要在 git 项目里表达"让项目归位/就绪/可发布"的意图就应使用本 skill。Use this skill whenever the user asks to sync, tidy up, check, commit, or open a PR for a git repository, or asks whether a project is ready to ship — even if they don't say "attention".
license: CC-BY-NC-SA-4.0
compatibility: Requires git (mandatory). gh optional (PR/issue queries; degrades to PR-ready artifacts). Bundled scripts need bash or PowerShell 7 — falls back to running git recipes manually. All analysis is local — no third-party services, no network calls beyond the repo's own remote.
metadata:
  version: "0.1.1"
  date: "2026-10-03"
  reference: "https://github.com/cgartlab/attention"
---

# 立正Skill

任意 Git 项目的"站好队"巡检与修复。一次调用，让项目回到可发布状态：要么干净同步并给出方向，要么把散落的改动想清楚、修好、文档与版本对齐、开成 PR。

## 核心理念（3 条）

1. **状态优先，动作在后**：先看清仓库现在是什么样，再决定动不动手；干净态与脏态走两条完全不同的路，绝不混用。判定定义见 `references/judgment-criteria.md`。
2. **只动该动的**：本地变更可批、远程不可逆动作必须再确认；永远不 force push、不删受保护/默认分支、不删未合并分支；门槛都设在提交之前；重复运行不得产生重复提交或重复 PR（幂等）。
3. **事实不得编造**：文档只反映真实 diff，版本只来自真实版本文件，建议只基于真实信号；缺的标 ［待补充：…］。**失败必须可见**——采集/查询失败或降级要留痕（`warnings[]` 或字段置 `null`），把"没查成"写成"没有"是最危险的编造。

## 不可让渡的三条铁律（本文件只做路由，不复述细则）

1. **禁止清单以 `references/autonomy-and-safety.md` 为准。**
2. **判定定义（干净/脏态、无价值分支、涉及 release、核心文档集、阈值、门槛通过条件）以 `references/judgment-criteria.md` 为准。**
3. **脚本 JSON 契约（字段、`null` vs `[]`、路径形态）以 `references/scan-recipes.md` 为准。**

> 本文件只保留**路由**（读哪个文件）+ **流程**（Phase 顺序）+ 上面 6 条元规则（理念 3 + 铁律 3）。Phase 已有 7 个、规则仍是 6 条——流程可以长，规则只减不增。历史上历次硬伤都源于本文件内联了 references 的"速查副本"——副本更窄、且它是唯一保证被加载的文本，于是更弱的规则成了实际执行的规则。**加规则要配对减规则**（见 `AGENTS.md`）。

## 何时使用

- 用户明示"立正"。
- 在 git 项目里，用户说"同步/整理/检查/提交这个项目""把项目弄干净""该提交了""开个 PR""让项目归位/就绪/可发布"等。

## 何时不用

- 非 git 仓库（探测到非 git → 说明并停止，不做任何改动）。
- 用户只是问一个 git 命令怎么写、或只想看某个文件——直接答，别启动整套巡检。
- **值守循环**（巡检 open issue / 处理某个 issue / 把某个 PR 修到可合并 / 评审或合并 PR）：走 Phase 3C，每轮只处理一个对象。

## 环境与前置探测（Phase 0，先做）

每次激活先做前置探测，细则见 `references/environment-and-prereqs.md`。六件事：是不是 git 仓库、默认分支、远程宿主、gh 鉴权、项目画像、shell 选择。

两条最容易错、已在 reference 里给了判据的做法：**shell 要按"能否执行"探测**（`bash -c 'echo ok'` 退出 0 才算可用，别用 `Test-Path`）；**默认分支不得想当然**（按梯子回退，仍不确定就问用户）。**无 remote 是"纯本地仓库"**：跳过 fetch/pull/PR，只做本地巡检与本地分支剪枝——且要如实说"没有配远程"，别说成"连不上"。

## 脚本使用约定

`scripts/` 下是本 skill 的黑盒采集脚本（bash `.sh` 与 PowerShell `.ps1` 两套，输出同形 JSON）。**先 `--help` 再调用**；除非 `--help` 不够用，不要读源码——它们存在是为了被调用，不是为了被读进上下文。

脚本只做只读采集与候选计算，绝不自己提交/推送/删分支/开 PR。**`--repo` 会校验路径**（无效即报 `repo path not found`，不会退回当前目录）；**务必读 `warnings[]`**（它标记本次采集的降级，相关字段可能是 `null`）。字段语义、`null`/`[]` 约定与无脚本回退配方见 `references/scan-recipes.md`。

## 工作流总览（决策树）

```
Phase 0 前置探测（非 git → 停）
   |
Phase 1 状态快照（黑盒脚本出 JSON）
   |
Phase 2 状态判定 × 意图分流
   ├─ 干净 + 只想同步/看看     → Phase 3A（轻量：只读同步 + 剪枝候选 + 建议）
   ├─ 干净 + 有交付/发版意图   → Phase 3B（完整：两条门槛 → 提交 → 推 PR）
   ├─ 脏 + 用户要收拾仓库       → Phase 3B（完整）
   └─ 值守循环（issue / PR）    → Phase 3C（选对象 → 实现/评审 → 合并门 → 回复/关闭）
   |
Phase 4 收尾报告（含可发布判定）
```

## Phase 1 — 状态快照

先 `--help`，再调用下面 5 个脚本，拿齐 JSON 后再进 Phase 2（字段语义见 `references/scan-recipes.md`，不要凭字段名猜）：

- `git_state_snapshot` — 分支、upstream、ahead/behind、改动、stash、未推送提交与分支、远程信息。
- `branch_cleanup_audit` — 已合并候选、陈旧未合并（只报告）、受保护名单、远端可达性、远程基准。
- `version_consistency_audit` — 版本文件一致性、释放信号（`release_signals`）、monorepo 检测。
- `core_docs_relevance_scan` — 核心文档与变更的交叉引用（**低精度提示**，不是"文档无需更新"的裁决）。
- `next_steps_analysis` — 下一步建议信号（近期提交、开放 issue/PR、TODO、缺失文档、测试命令）。

> 不要在缺快照的情况下开始下结论。

## Phase 2 — 状态判定与路径分流

判定定义见 `references/judgment-criteria.md`（本文件不复述）。唯一要点：**判定要保守**——拿不准归脏态、拿不准走完整路径；多做几步是可恢复的，漏掉交付是不可恢复的。

**意图分流**：状态干净不等于没事要办——把**仓库状态**与**用户意图**分开看。

| 状态 | 用户意图 | 走法 |
|---|---|---|
| 干净 | 只想同步/看看 | Phase 3A |
| 干净 | 明示发版、要对齐版本号、要开 PR、要提交某处改动 | **Phase 3B 的门槛与交付步骤**；不存在"没有未提交改动所以什么都不做"这一说 |
| 脏 | **用户**要收拾/提交这个仓库 | Phase 3B（计划批准后提交） |
| 任意 | **值守循环**（巡检 open issue、处理某个 issue/PR、评审或合并 PR） | **Phase 3C** |
| 任意 | 值守循环 **且工作区脏** | **Phase 3C，但禁止提交**：不 stage / 不 commit / 不 stash / 不 pull，评估后停下来问（`references/issue-pr-loop.md` §12） |
| 非 git | 任意 | 说明并停 |

**轻量与完整的区别不在"查多少"，而在"动不动交付链路"**：轻量路径止于只读与本地同步，不建分支、不提交、不开 PR。**脏态的提交权由意图决定**——同一份脏工作区，"用户让我收拾"可提交，"循环轮次撞见"不可提交（后者可能是上一轮残留或别人正在写的东西）。

典型例子：用户说"这次改了 package.json 的版本号要发版，把 Cargo 那边也对齐，然后提 PR"，而那个版本改动**已经提交**、工作区干净——按状态属干净态，但诉求是真实交付任务，必须走 3B 的门槛与交付步骤。

## Phase 3A — 干净态处理

1. `git fetch` + 对默认分支 `git pull --ff-only`。只快进：若有分叉（非快进）→ 停止并报告，绝不合并提交、绝不 force。理由：干净态的目标是同步，不是消化本地分叉。**无远程 → 跳过本步并如实说明**（"还没配远程"，不是"连不上"）。
2. **剪枝已合并分支**：仅删"已完全合并入默认分支 且 不在受保护名单"者；陈旧未合并分支只报告不删。**先列候选（将删除/将保留+原因）、等用户点头再动手**——顺序与「开头那句"顺手清理"不算确认」见 `references/autonomy-and-safety.md` §清场顺序；`-d` 作第二道保险、远程删除必须带 lease、远端不可达时写"没查成"不写"没有"，细则见 `references/branch-model-and-protection.md`。
3. **下一步建议**：用 `next_steps_analysis` 的信号给可执行方向，只基于真实信号。
4. 若为了 pull 切换过分支，收尾切回原分支。

## Phase 3B — 修复与交付路径

> 本路径同时服务"脏态修复"与"干净态但有交付意图"（Phase 2 分流结果）。工作区本来就干净时第 1、4 步可能空转——照走，不要跳过门槛。

1. **诊断**：用 `git_state_snapshot` 归类未提交/未推送改动（WIP 功能 / 构建破损 / 半成品）。先诊断全找全，出问题清单，禁止边找边改。**排查过程中发现的小毛病（非用户主诉但真实存在的小问题，如假阳性噪音、过期数字、未实现的小功能）也纳入清单**——与主诉问题一起在计划表中分组，不因其"小"而跳过。
2. **修复计划 + 计划表**：基于 diff 给出具体可发布化计划，并**列成表**（模板见 `assets/templates/plan-table.md`）：将创建 / 将更新 / 将跳过（附原因） / 需你确认。用 `ask_user_question` 呈现，一次批准覆盖后续本地动作（编辑、测试、提交、**本地**分支删除）。**推送不在此列**——push/PR/删远程分支/推 tag 属远程不可逆动作，执行点另做最终确认。
3. **工作分支（必做，不可省）**：若当前分支在受保护名单内（例如正站在 `main` 上），先 `git switch -c <type>/<slug>`——命名沿用仓库既有习惯（从 `git log` / `git branch` 实测得出）。**禁止直接在默认分支上提交并推送**。无法建分支 → 停止并报告。
4. **执行修复 + 逐步 verify**：应用编辑，每个改动点后立刻验证（跑测试 / 回读文件 / 重跑相关脚本）再进下一步。跑测试/lint/build 至绿；绿不了就如实报告阻塞器，不硬提交。
5. **文档同步门槛（提交前）**：跑 `core_docs_relevance_scan`，按 `references/core-docs-sync.md` 更新核心文档（该扫描是低精度提示，判定口径见 `judgment-criteria.md` §门槛通过条件）；CHANGELOG 分节见 `references/changelog-sections.md`。含未消解 ［待补充］ 的文档要么不进提交，要么在 PR body 列为阻塞项。
6. **发行版本门槛（提交前）**：按 `references/judgment-criteria.md` 的**多层门**判定——脚本给 `release_signals`（宽口径），**是否真的 bump 由你结合用户意图判定并说明理由**；需要 bump 时一致 bump 所有版本文件、补 CHANGELOG、记录 tag 计划。`consistent=null`（无版本文件）时不要声称"版本已一致"。
7. **提交**：按探测到的提交规约，一个提交一个意图；body 讲 **WHY**（diff 已说明 WHAT）。**改动按逻辑分组，每组走独立分支 + PR（不创建 Issue）**——一个大改动可拆成多个 PR（如 fix + docs + feat 各一），便于逐个评审与回滚。模板见 `assets/templates/commit-message.md`。
8. **推送与开 PR**：推送前做**远程动作最终确认**。GitHub → `gh pr create`（模板见 `assets/templates/pr-body.md`）；非 GitHub / CLI 不可用 / 远程不可达 → 输出 PR/MR 就绪产物（分支、diff 概览、建议标题正文、手动指引），**不编造**宿主专属命令。**不创建 Issue——最终交付物只有 PR**。开 PR 前先查是否已有同题开放 PR（`gh_query_state="ok"` 时才作数）。

## Phase 3C — 值守循环（issue / PR）

> 本路径服务"持续性值守"意图（巡检 open issue、处理某个 issue / PR、把 PR 修到可合并、评审或合并。**判定口径**（triage / UI 白名单 / 合并门四层 / 关闭判据）见 `references/judgment-criteria.md`；**动作档位**（评论 / 合并 / 关闭）见 `references/autonomy-and-safety.md`。这里只给顺序。

1. **前置门**：非 GitHub / 未登录 / `gh_query_state!="ok"` → 只报告"没查成"，不进循环；工作区脏 → 不提交，问（Phase 2 表）。
2. **选对象**：`gh issue list --json …` 实时查（**不得**用 `open_issues` 字段做 triage，它只有一行标题），过 triage 门，**本轮只取一个**。
3. **查重**：三条线索命中即"已有相关 PR"→ 走评审；都不中 → 走实现。
4. **实现 / 评审**：无 PR → 拉最新默认分支、建 `<type>/<issue>-<slug>`、连同类问题一并修、走 3B 两道门槛、`gh pr create`（body 首行 `Closes #<n>`）；有 PR → 按 `assets/templates/pr-review.md` **逐行**读 diff，并在隔离 worktree **实跑**留证（命令+退出码+计数），未决反馈先解决。自己的 PR 同样过一遍。
5. **合并门**：四层全过才可合并；**强 UI 改动永不自动合并**，必须截图 + 人工确认（`references/issue-pr-loop.md` §8.3）。否则：能修则修 → 修不了按 `assets/templates/issue-pr-comment.md` 回复 → 确应放弃则**先评论后关闭**。
6. **收尾**：合并后删源分支（带 lease）→ 回默认分支 → 再走一次 Phase 3A；报告按 `status-report.md` 加"本轮对象"。

## Phase 4 — 收尾报告

结构、可发布判定（READY / NOT READY / BLOCKED）、CRITICAL/WARNING/SUGGESTION 分级、大白话语言规则与脱敏要求，**全部见 `assets/templates/status-report.md`**（含 ❌/✓ 正反例）。一条底线：报告要能让人**立刻知道下一步干什么**，字段名与命令串只进末尾"📋 技术细节（可选）"小节。

**收尾报告须包含 PR 合并顺序建议**（若有多个 PR）：按依赖关系与风险排序（纯文档 PR → fix PR → feat PR），给出每条 PR 的合并前提与冲突风险提示。让用户一眼看清"先合哪个、哪个可能需要 rebase"。

## 安全与边界

- **分层确认模型、永远禁止清单、边界情形（detached HEAD / 零提交 / stash / 未跟踪半成品 / 无远程 / 远程不可达 / monorepo）**：全部以 `references/autonomy-and-safety.md` 为准。
- **非交互环境（delegated / 无人值守 / 无 `ask_user_question`）**：把计划或候选写在回复里并**停下等待确认**，不得自批。这条是硬规则——把"没人可问"当成"默认同意"会直接绕过分层确认模型。

## references 索引（按需读，别全读）

| 文件 | 何时读 |
|------|--------|
| `references/scan-recipes.md` | **脚本 JSON 契约（单一事实源）**：字段语义、`null` vs `[]`、无脚本回退配方 |
| `references/environment-and-prereqs.md` | Phase 0 探测细则与适配（shell 探测、Windows 回退、无远程/不可达） |
| `references/judgment-criteria.md` | 判定分流、各定义边界、涉及 release 的多层门、门槛通过条件 |
| `references/branch-model-and-protection.md` | 默认分支探测、受保护名单、本地/远程剪枝与 lease 删除 |
| `references/core-docs-sync.md` | 核心文档集、差异驱动更新法、反幻觉与溯源、知识分层 |
| `references/release-versioning.md` | 各生态版本文件、一致性规则、CHANGELOG |
| `references/changelog-sections.md` | CHANGELOG 分节表、`hidden` vs `skip`、条目溯源 |
| `references/version-file-inventory.md` | 版本文件与 lockfile 的跨生态详表（含 Agent Skill 的 SKILL.md frontmatter） |
| `references/pr-and-remote-hosts.md` | gh PR 模板、非 GitHub 与远程不可达的降级 |
| `references/autonomy-and-safety.md` | 分层确认模型、禁止动作、边界情况 |
| `references/common-pitfalls.md` | "做了但没生效"类问题（.gitignore 前导斜杠/已跟踪文件/`check-ignore` 陷阱/删除远程要 lease） |
| `references/issue-pr-loop.md` | **Phase 3C 的流程单一事实源**：轮次与幂等键、triage 选对象、PR 查重、逐行评审与实跑、合并门顺序、截图证据落法、回复/关闭、脏态特例 |
| `docs/ecosystem-research/` 与 `docs/ecosystem-survey.md` | **研究备忘，非默认加载**：只在需要对齐行业做法或判断字段边界时读 |

## assets/templates 索引

- `assets/templates/commit-message.md` — 提交信息规约与示例（含 body 讲 WHY、提交前自检清单）
- `assets/templates/pr-body.md` — PR 描述结构
- `assets/templates/changelog-entry.md` — CHANGELOG 条目结构（Keep a Changelog 六类）
- `assets/templates/plan-table.md` — 修复计划表（将创建/更新/跳过/需确认）
- `assets/templates/status-report.md` — 收尾报告结构、语言规则、可发布判定、复核命令表（含值守循环的"本轮对象"一节）
- `assets/templates/pr-review.md` — PR 逐行评审清单（结构/逻辑/跨平台/验证/文档/安全/视觉，含真实事故条目）
- `assets/templates/issue-pr-comment.md` — issue/PR 评论四种骨架（进度、阻塞、关闭理由、合并证据 + 强 UI 版）

## scripts 索引（黑盒，先 --help）

| 脚本 | 作用 |
|------|------|
| `scripts/git_state_snapshot` | 状态快照（分支/upstream/改动/stash/未推送提交与分支/远程） |
| `scripts/branch_cleanup_audit` | 分支剪枝候选（已合并/陈旧/受保护/远端可达性/合并基准） |
| `scripts/version_consistency_audit` | 版本一致性 + 发布信号 + monorepo 检测 |
| `scripts/core_docs_relevance_scan` | 核心文档与变更交叉引用扫描 |
| `scripts/next_steps_analysis` | 下一步建议信号采集 |
