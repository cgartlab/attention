# 立正Skill（lizheng）

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

## 安装

把本仓库克隆/复制到你的 skills 目录（DSH 为 `C:\Users\<你>\.dsh\skills\`）：

```
lizheng/
├── SKILL.md            # 触发与工作流
├── scripts/*.ps1       # 黑盒数据采集脚本（PowerShell，先 --help）
├── references/*.md     # 按需加载的判断细则
└── assets/templates/   # 提交/PR/CHANGELOG/报告模板
```

依赖：`git`；`gh`（可选，开 PR 用，需 `gh auth login`）。脚本为 PowerShell（`.ps1`），用 `pwsh -NoProfile -File` 运行。

## 使用

在任意 git 项目里对 agent 说"立正"或"同步/整理/检查这个项目"等同义意图即可触发。详见 `SKILL.md` 的 description。

## 脚本

均为只读采集，绝不自己提交/推送/删分支/开 PR：

| 脚本 | 作用 |
|------|------|
| `scripts/git_state_snapshot.ps1` | 仓库状态快照（分支/upstream/改动/stash/未推送） |
| `scripts/branch_cleanup_audit.ps1` | 分支剪枝候选审计（已合并/陈旧/受保护） |
| `scripts/version_consistency_audit.ps1` | 版本承载文件一致性审计 |
| `scripts/core_docs_relevance_scan.ps1` | 核心文档与变更交叉引用扫描 |
| `scripts/next_steps_analysis.ps1` | 下一步建议信号采集 |

每个脚本都支持 `--help`。

## 许证

CC-BY-NC-SA-4.0（见 `SKILL.md` frontmatter）。