---
name: lizheng
description: 立正——任意 Git 项目的"站好队"巡检与修复 skill。当用户说"立正""lizheng"，或在 git 项目中说"同步/整理/检查/提交这个项目""把项目弄干净""该提交了""开个 PR""让项目归位/就绪/可发布"等同义意图时激活：自动检测开发状态——干净则拉取最新默认分支、清理已合并的无价值分支、给下一步开发方向；有未提交/未推送改动则思考修复计划并自动执行，提交前严格保证核心文档同步真实最新变化、发行版本号一致，完成后开新 PR。即使用户没说"立正"，只要在 git 项目里表达"让项目归位/就绪/可发布"的意图就应使用本 skill。
license: CC-BY-NC-SA-4.0
metadata:
  version: "0.1.0"
  date: "2026-09-29"
  reference: "https://github.com/cgartlab/lizheng"
---

# 立正Skill

任意 Git 项目的"站好队"巡检与修复。一次调用，让项目回到可发布状态：要么干净同步并给出方向，要么把散落的改动想清楚、修好、文档与版本对齐、开成 PR。

## 核心理念

- **状态优先，动作在后**：先看清仓库现在是什么样子，再决定动不动手。干净与脏态走两条完全不同的路，绝不混用。
- **只动该动的**：本地变更可以批，远程不可逆动作必须再确认；force push 到默认分支、删未合并分支、删受保护分支——永远不做。
- **事实不得编造**：文档同步只反映真实 diff 支撑的变化，版本号只来自真实版本文件，下一步建议只基于真实信号（近期提交、开放 issue/PR、TODO grep、测试信号）。缺的标 ［待补充：…］，不替用户圆上。
- **两阶段诊断**：脏态修复时，先一次性把问题找全、出清单，再逐条处理——禁止边找边改，否则交出来的稿子全是毛边。
- **门槛即护栏**：文档同步门槛与发行版本门槛放在提交之前，不是提交之后补救。这是本 skill 与"提交完才发现文档没更新"的分水岭。

## 何时使用

- 用户明示"立正"/"lizheng"。
- 在 git 项目里，用户说"同步/整理/检查/提交这个项目""把项目弄干净""该提交了""开个 PR""让项目归位/就绪/可发布"等。

## 何时不用

- 非 git 仓库（探测到非 git → 说明并停止，不做任何改动）。
- 用户只是问一个 git 命令怎么写、或只想看某个文件——直接答，别启动整套巡检。

## 环境与前置探测（Phase 0，先做）

每次激活先做前置探测，细节见 references/environment-and-prereqs.md。要点：

1. **是不是 git 仓库**：git rev-parse --is-inside-work-tree 失败 → 说明并停止。
2. **默认分支**：gh repo view --json defaultBranchRef → 回退 git symbolic-ref refs/remotes/origin/HEAD → 回退 main→master→develop→trunk。一句话向用户确认探测到的默认分支与远程宿主，不确定就列候选问用户。
3. **远程宿主**：GitHub（用 gh，PR 全功能）/ GitLab·Bitbucket·其它（remote -v 识别，PR 降级为"PR 就绪 diff + 手动指引"）。
4. **gh 鉴权**：gh auth status 未登录 → 标记 PR 功能不可用，其余流程照常。
5. **项目画像**：项目类型、核心文档集、版本承载文件、提交规约（读 git log 判定是否 conventional commits）、测试/lint/build 命令（package.json scripts / Makefile / pyproject 等）。

> 为什么要先探测：默认分支不是想当然的 main，远程宿主决定 PR 怎么开，gh 没登录不能硬开 PR。把这些不确定一次性钉死，后面的判断才稳。

## 脚本使用约定

本 skill 在 scripts/ 下提供若干黑盒数据采集脚本（PowerShell，.ps1）。它们处理确定、重复、可验证的采集，把结构化 JSON 交给你推理——避免你自己拼 git 命令时漏判或污染上下文。

**约定**：
- **先 --help，再调用**。先看用法，按用法调用。除非 --help 不够用，不要读脚本源码——它们存在是为了被调用，不是为了被读进上下文。
- 脚本只做只读采集与候选计算，绝不自己提交、推送、删分支、开 PR。所有变更动作由你（模型）按本工作流显式执行。
- 脚本路径相对本 skill 基础目录。用你的 shell 工具运行：pwsh -NoProfile -File "<base>/scripts/<name>.ps1" --help。

> 为什么用脚本：git branch --merged 的输出、版本号的跨文件一致性、核心文档的交叉引用——这些一旦手写极易漏判，且每次都重复。写成黑盒跑一次出 JSON，判断质量稳定，上下文也干净。

## 工作流总览（决策树）

```
Phase 0 前置探测（非 git → 停）
   |
Phase 1 状态快照（黑盒脚本出 JSON）
   |
Phase 2 判定：有未提交改动 或 有未推送提交 或 有未推送分支？
   ├─ 否（干净态）→ Phase 3A
   └─ 是（脏态）  → Phase 3B
   |
Phase 4 收尾报告
```

## Phase 1 — 状态快照

先 --help，再按用法调用下列脚本，拿到 JSON 后推理：

- scripts/git_state_snapshot.ps1 — 当前分支、upstream 跟踪、ahead/behind、staged/unstaged/untracked（尊重 .gitignore，不纳入 node_modules 等）、stash、最近变更文件、与默认分支的散度。
- scripts/branch_cleanup_audit.ps1 — 本地已合并分支、远程已合并分支、受保护名单、陈旧未合并分支（仅报告）。
- scripts/version_consistency_audit.ps1 — 全部版本承载文件及其版本串、是否一致、是否"涉及 release"。
- scripts/core_docs_relevance_scan.ps1 — 核心文档清单 + 哪些变更源文件被文档交叉引用 → 标记需更新文档。

> 拿齐四份快照再进 Phase 2。不要边拿边下结论。

## Phase 2 — 判定分流

判定定义见 references/judgment-criteria.md，速查：

- **未提交改动**：staged / unstaged / untracked 任一非空。
- **未推送提交**：当前分支可达但不在任何 remote-tracking ref 上的提交。
- **未推送分支**：本地有分支其提交未出现在任何远程。

三条任一为真 → 脏态（Phase 3B）；全假 → 干净态（Phase 3A）。

## Phase 3A — 干净态处理

1. git fetch + 对默认分支 git pull --ff-only。只快进：若与本地提交散度（非快进）→ 停止并报告，绝不合并提交、绝不 force。理由：干净态的目标是同步，不是消化本地分叉——分叉该走脏态或单独决策。
2. **剪枝已合并分支**：用 branch_cleanup_audit 的候选——仅删"已完全合并入默认分支 且 不在受保护名单"的分支。陈旧未合并分支只报告不删（删了会丢工作）。受保护名单见 references/branch-model-and-protection.md（main master develop dev trunk release/* prod production gh-pages + 仓库保护分支）。
   - 本地：git branch -d <branch>（-d 本身就拒删未合并，作为第二道保险）。
   - 远程：仅删"已合并 且 远端已无活跃对应分支"者，用 git push origin --delete 或 gh api。远程删除是不可逆——按 references/autonomy-and-safety.md 做最终确认。
3. **下一步建议**：scripts/next_steps_analysis.ps1 综合 git log 近期提交、gh issue/pr list 开放项、TODO/FIXME grep、测试信号、分支年龄 → 给可执行方向。只基于真实信号，不编造。

## Phase 3B — 脏态修复路径

1. **诊断**：用 git_state_snapshot 归类未提交/未推送改动（WIP 功能 / 构建破损 / 半成品），判是否有失败测试或构建。两阶段：先诊断全找全，出问题清单，禁止边找边改。
2. **修复计划**：基于 diff 给出具体可发布化计划——要改什么、为什么、预期结果。
3. **计划门槛**：用 ask_user_question 呈现完整计划，一次批准。这一道确认覆盖后续全部本地动作（编辑、测试、提交、推送）；远程不可逆动作另在执行点做最终确认。
4. **执行修复**：应用编辑、跑测试/lint/build、迭代至绿。绿不了就如实报告阻塞器，不硬提交。
5. **文档同步门槛（提交前）**：跑 core_docs_relevance_scan，按 references/core-docs-sync.md 把 README/CHANGELOG/AGENTS.md/CONTRIBUTING/docs/** 更新到反映真实 diff。只反映真实变化、不得新增事实；缺的标 ［待补充：…］。
6. **发行版本门槛（提交前）**：若涉及 release，跑 version_consistency_audit，按 references/release-versioning.md 一致 bump 所有版本文件、补 CHANGELOG 条目、记录 tag 计划。"涉及 release" = 变更集触及版本文件 / 含 chore(release) 或 feat! / 用户明示 release。
7. 按探测到的提交规约提交、推送分支。
8. 终检后开 PR：GitHub 用 gh pr create（assets/templates/pr-body.md）；非 GitHub → 输出 PR 就绪 diff + 手动指引，不尝试 gh pr create。

> 为什么把文档与版本门槛放在提交前：提交后再补文档，要么得追加提交污染历史，要么干脆忘了。门槛前置，让每个 PR 自带"文档与代码一致"的保证。

## Phase 4 — 收尾报告

用 assets/templates/status-report.md 输出：改了什么、清理了什么、PR 链接（或手动指引）、下一步建议。让用户一眼看清这次"立正"做了什么。

## 安全与禁止（分层确认）

细节见 references/autonomy-and-safety.md，速查：

- **只读分析**：始终自动。
- **本地变更**（编辑、提交、删本地已合并分支）：计划批准后自动。
- **远程不可逆**（push、删远程分支、开 PR、推 tag）：执行点最终确认。
- **永远禁止**：force push 到默认分支、直接 push 到默认分支（改走 PR）、删未合并分支、删受保护分支、纳入 .gitignore 文件。

## 判断定义速查

见 references/judgment-criteria.md，含：干净/脏态、无价值分支、未推送提交、涉及 release、核心文档集 等的精确定义与边界。

## references 索引（按需读，别全读）

| 文件 | 何时读 |
|------|--------|
| references/environment-and-prereqs.md | Phase 0 探测细则与适配 |
| references/judgment-criteria.md | 判定分流、各定义的精确边界 |
| references/branch-model-and-protection.md | 默认分支探测、受保护名单、剪枝规则 |
| references/core-docs-sync.md | 核心文档集、差异驱动更新法、反幻觉 |
| references/release-versioning.md | 各生态版本文件、一致性规则、CHANGELOG |
| references/pr-and-remote-hosts.md | gh PR 模板、非 GitHub 回退 |
| references/autonomy-and-safety.md | 分层确认模型、禁止动作、边界情况 |

## assets/templates 索引

- assets/templates/commit-message.md — 提交信息规约与示例
- assets/templates/pr-body.md — PR 描述结构
- assets/templates/changelog-entry.md — CHANGELOG 条目结构
- assets/templates/status-report.md — 收尾报告结构

## scripts 索引（黑盒，先 --help）

- scripts/git_state_snapshot.ps1 — 仓库状态快照
- scripts/branch_cleanup_audit.ps1 — 分支剪枝候选审计
- scripts/version_consistency_audit.ps1 — 版本一致性审计
- scripts/core_docs_relevance_scan.ps1 — 核心文档相关性扫描
- scripts/next_steps_analysis.ps1 — 下一步建议信号采集