<p align="center">
  <img src="assets/logo.svg" width="128" height="128" alt="attention logo">
</p>

<h1 align="center">立正Skill（attention）</h1>

<p align="center">
  <b>任意 Git 项目的"站好队"巡检与修复 Agent Skill。</b>一次调用，让项目回到可发布状态。
</p>

<p align="center">
  <a href="https://agentskills.io"><img alt="Agent Skills compatible" src="https://img.shields.io/badge/Agent_Skills-compatible-4b3baf"></a>
  <a href="https://github.com/cgartlab/attention/releases/tag/v0.1.0"><img alt="release v0.1.0" src="https://img.shields.io/badge/release-v0.1.0-success"></a>
  <img alt="skill version 0.1.0" src="https://img.shields.io/badge/skill_version-0.1.0-2563eb">
  <a href="https://github.com/cgartlab/attention/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/cgartlab/attention/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="checks: 553 passed" src="https://img.shields.io/badge/checks-553_passed-3fb950">
  <img alt="shell: bash + pwsh" src="https://img.shields.io/badge/shell-bash_%2B_pwsh-4EAA25">
  <img alt="runtime deps: git only" src="https://img.shields.io/badge/runtime-git_only-lightgrey">
  <a href="LICENSE"><img alt="license: CC-BY-NC-SA-4.0" src="https://img.shields.io/badge/License-CC--BY--NC--SA--4.0-lightgrey"></a>
</p>

> **徽章说明**：本仓库是 **private**，shields.io 读不到私有仓库的动态数据，故 `release` / `skill_version` / `checks` 为**静态徽章**（随发版手改，`checks` 数值取自最近一次发布门禁的全量结果）；`CI` 徽章为 GitHub 原生，**需有仓库读权限**才会显示。skills.sh 徽章只对公开仓库有效，故未使用。

## 它做什么

调用立正后，自动检测当前项目的开发状态：

- **干净态**（无未提交改动、无未推送提交，且用户只想同步）：拉取最新默认分支（`--ff-only`）、清理已合并的无价值分支、给出基于真实信号的下一步开发建议。
- **有交付意图**（有未提交/未推送改动，或用户明说要发版/提 PR）：思考修复计划并自动执行，**提交前严格保证核心文档同步真实最新变化、发行版本号一致**，完成后开新 PR。

> 状态干净不等于没事可做：用户说"版本号已改、要发版、提 PR"时，即使工作区干净也会走门槛与交付步骤（见 `SKILL.md` 的 Phase 2 分流表）。

## 核心原则

- 状态优先，动作在后；干净与脏态走两条不同的路。
- 只动该动的：force push、删未合并分支、删受保护/默认分支——永远不做。
- 事实不得编造：文档与版本只反映真实 diff，下一步建议只基于真实信号；**"没查成"必须写成"没查成"**，不能写成"没有"。
- 两阶段诊断：脏态修复先一次性找全再处理，禁止边找边改。
- 门槛即护栏：文档同步门槛与发行版本门槛放在**提交之前**。
- 收尾报告用大白话，并给出可发布判定（READY / NOT READY / BLOCKED）；技术细节另放末尾可选小节。

## 安装

立正符合 [Agent Skills](https://agentskills.io) 开放标准（`SKILL.md` + `name`/`description` frontmatter），可装到兼容 harness（Claude Code、Codex、Cursor、OpenCode 等）。

**⚠️ 本仓库托管为 private（私有）**：`skills` CLI **支持私有仓库**（用你已配置的 git 凭据 / `gh` / SSH），但**消费方必须有本仓库读权限**；skills.sh 徽章只对公开仓库有效，在本仓库上不显示。也可以直接"手动安装"：

```bash
npx skills add cgartlab/attention   # 私有仓库亦可，但需有本仓库读权限（凭据由 gh/git 提供）
```

**手动安装**（现在就能用）：把本仓库克隆/复制到你所用 harness 的 skills 目录。各 harness 的默认位置：

| harness | 项目内 | 全局 |
|---|---|---|
| DSH | `<项目>/.dsh/skills/attention` | `%USERPROFILE%\.dsh\skills\attention` |
| Claude Code | `.claude/skills/attention` | `~/.claude/skills/attention` |
| Cursor | `.agents/skills/attention` | `~/.cursor/skills/attention` |
| Codex | `.agents/skills/attention` | `~/.codex/skills/attention` |

> 在 Windows 上可以直接做目录联接（junction）指向本仓库，改一处即全局生效：`New-Item -ItemType Junction -Path "$env:USERPROFILE\.dsh\skills\attention" -Target "<本仓库路径>"`。

```
attention/
├── SKILL.md            # 触发与工作流（只做路由 + 三条铁律）
├── scripts/            # 黑盒采集脚本：bash(.sh) 与 PowerShell(.ps1) 两套
├── references/         # 按需加载的判断细则（含 scan-recipes.md 契约）
├── assets/templates/   # 提交/PR/CHANGELOG/计划表/报告模板
├── evals/              # 回归：21 个 fixture + 断言表 + 双实现 runner
└── docs/               # 验证记录、质量审计、调研备忘
```

**运行时依赖**：`git`（必需）；`gh`（可选，开 PR 与查 issue/PR 用，缺则降级为"PR 就绪产物 + 手动指引"）。脚本按环境选 bash 或 pwsh——**探测方式是"跑一次 `bash -c 'echo ok'`"，不是看文件在不在**（受限沙箱里 `bin\bash.exe` 可能存在却启动失败）。不要求 Python/Node 作为运行时依赖。

## 使用

在任意 git 项目里对 agent 说"立正"或"同步/整理/检查这个项目""该提交了""开个 PR"等同义意图即可触发；英文场景说 "tidy up this repo and open a PR" 之类也会命中。详见 `SKILL.md` 的 description。

## 脚本

均为只读采集，绝不自己提交/推送/删分支/开 PR。bash（`.sh`）与 PowerShell（`.ps1`）两套实现，输出同形 JSON（契约见 `references/scan-recipes.md`）：

| 脚本 | 作用 | 关键能力 |
|------|------|----------|
| `git_state_snapshot` | 仓库状态快照 | 分支/upstream/改动/stash/**未推送提交与分支**/远程信息 |
| `branch_cleanup_audit` | 分支剪枝候选审计 | 已合并/陈旧未合并/受保护/远端可达性 |
| `version_consistency_audit` | 版本一致性 | 版本文件一致性 + **发布信号**（`release_signals`）+ monorepo 检测；支持 `--target-version`、`--since-tag` |
| `core_docs_relevance_scan` | 文档交叉引用扫描 | 低精度提示 + `docs_stale_candidates`（请人工确认的清单） |
| `next_steps_analysis` | 下一步建议信号 | 近期提交、开放 issue/PR、TODO（含未跟踪文件）、测试命令、缺失文档 |

每个都支持 `--help`；`--repo` 会校验路径（无效即明确报错，不会退回当前目录）。全部脚本都会输出 `warnings[]` 标记本次采集的降级。

## 验证

仓库自带可复现的回归，不靠"人肉记得跑"：

```powershell
# 三层校验：严格 JSON（RFC 8259）+ .sh/.ps1 逐字段 parity + 断言表（21 个 fixture、83 条断言）
pwsh -NoProfile -File evals/run_evals.ps1
bash evals/run_evals.sh                 # bash 侧（建议有 python3）

# 快速冒烟：双实现都跑 + 负例断言
pwsh -NoProfile -File scripts/smoke_test.ps1 --repo .
bash scripts/smoke_test.sh --repo .
```

结果写入 `evals/results/`（入库作为证据）。

**已验证 / 未验证（诚实边界）**：

- ✅ 已验证：双实现在 21 个 fixture 上输出严格合法 JSON 且逐字段一致；非 git 目录、零提交仓库、detached HEAD、CRLF 版本文件、被忽略目录内的版本文件、宿主误判、颜色注入等边界；`--repo` 无效与漏值不再静默/挂死。
- ❌ 未验证：**任何远程操作**（本开发环境无法建立可用的远程传输：本地路径传输要过 shell、`git://` receive-pack 会挂死）；真实 GitHub PR 创建；`npx skills add` 安装链路（需先推送）；跨 harness 触发率。

详见 `docs/VALIDATION.md`（验证记录）与 `docs/QUALITY-AUDIT.md`（本次审计查出的缺陷、复现方式与回归清单）。

## 发布与版本

- **版本策略**：未切 1.0 之前保持 `0.1.0`；未发布变更记入 `CHANGELOG.md` 的 `[Unreleased]`，是否切版由维护者决定（见 `AGENTS.md`）。
- **版本载体**：唯一载体是 `SKILL.md` frontmatter 的 `metadata.version`（`version_consistency_audit` 已识别为 `agent-skill` 生态）。
- **发布流程**：见 `docs/RELEASING.md`（CI 门禁、发布 PR、tag 保护、回滚）。
- **发布前自检**（只读，失败即退出 1）：

  ```powershell
  pwsh -NoProfile -File scripts/release_preflight.ps1 --repo .
  bash scripts/release_preflight.sh --repo .          # 两套实现判据一致
  ```
## 许证

CC-BY-NC-SA-4.0（见 `LICENSE` 与 `SKILL.md` frontmatter）。注意：非商业授权，商用再分发前请先确认合规。
