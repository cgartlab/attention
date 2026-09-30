# 立正Skill（lizheng）

[![skills.sh](https://skills.sh/b/cgartlab/lizheng)](https://skills.sh/cgartlab/lizheng)
[![Agent Skills](https://img.shields.io/badge/Agent_Skills-compatible-4b3baf)](https://agentskills.io)
[![License: CC-BY-NC-SA-4.0](https://img.shields.io/badge/License-CC--BY--NC--SA--4.0-lightgrey)](LICENSE)

任意 Git 项目的"站好队"巡检与修复 Agent Skill。一次调用，让项目回到可发布状态。

## 它做什么

调用立正后，自动检测当前项目的开发状态：

- **干净态**（无未提交改动、无未推送提交）：拉取最新默认分支（`--ff-only`）、清理本地与远程已合并的无价值分支、给出基于真实信号的下一步开发建议。
- **脏态**（有未提交/未推送改动）：思考修复计划并自动执行，**提交前严格保证核心文档同步真实最新变化、发行版本号一致**，完成后开新 PR。

## 核心原则

- 状态优先，动作在后；干净与脏态走两条不同的路。
- 只动该动的：force push 到默认分支、删未合并分支、删受保护分支——永远不做。
- 事实不得编造：文档与版本只反映真实 diff，下一步建议只基于真实信号。
- 两阶段诊断：脏态修复先一次性找全再处理，禁止边找边改。
- 门槛即护栏：文档同步门槛与发行版本门槛放在**提交之前**。
- 收尾报告用大白话：主叙事面向项目作者（含新手），技术细节另放末尾可选小节。

## 安装

立正符合 [Agent Skills](https://agentskills.io) 开放标准（`SKILL.md` + `name`/`description` frontmatter），可用 `skills` CLI 装到 100+ 兼容 harness（Claude Code、Codex、Cursor、OpenCode、Windsurf、Gemini CLI 等）：

```bash
npx skills add cgartlab/lizheng
```

- 默认装到项目内（`./<agent>/skills/`）；`-g` 装到全局（`~/<agent>/skills/`）。
- `-a claude-code -a cursor` 指定 harness；`-l` 仅列出；`--all` 全装。
- 源也支持 GitHub URL、GitLab、Azure Repos、git URL、本地路径。详见 `npx skills --help`。

> 注：此命令需仓库先推送到 GitHub（`github.com/cgartlab/lizheng`）；当前未推送，推送后即可用。

**手动安装**（无 Node 或不想用 CLI）：把本仓库克隆/复制到你的 skills 目录：

- DSH：`C:\Users\<你>\.dsh\skills\lizheng`
- Claude Code：`~/.claude/skills/lizheng`

```
lizheng/
├── SKILL.md            # 触发与工作流
├── scripts/            # 黑盒采集脚本：bash(.sh) 与 PowerShell(.ps1) 两套
├── references/         # 按需加载的判断细则（含 scan-recipes.md 契约）
├── assets/templates/   # 提交/PR/CHANGELOG/报告模板
└── docs/               # 开发计划等
```

**运行时依赖**：`git`（必需）；`gh`（可选，开 PR 用）。脚本按环境选 bash 或 pwsh——见 `references/environment-and-prereqs.md` §6。不要求 Python/Node 作为运行时依赖。

## 使用

在任意 git 项目里对 agent 说"立正"或"同步/整理/检查这个项目""该提交了""开个 PR"等同义意图即可触发。详见 `SKILL.md` 的 description。

## 脚本

均为只读采集，绝不自己提交/推送/删分支/开 PR。bash（`.sh`）与 PowerShell（`.ps1`）两套实现，输出同形 JSON（契约见 `references/scan-recipes.md`）：

| 脚本 | 作用 |
|------|------|
| `git_state_snapshot` | 仓库状态快照（分支/upstream/改动/stash/未推送） |
| `branch_cleanup_audit` | 分支剪枝候选审计（已合并/陈旧/受保护） |
| `version_consistency_audit` | 版本承载文件一致性审计 |
| `core_docs_relevance_scan` | 核心文档与变更交叉引用扫描 |
| `next_steps_analysis` | 下一步建议信号采集 |

每个都支持 `--help`。两套实现的 git 命令与 JSON 字段完全一致——单一事实源在 `references/scan-recipes.md`。

## 许证

CC-BY-NC-SA-4.0（见 `LICENSE` 与 `SKILL.md` frontmatter）。