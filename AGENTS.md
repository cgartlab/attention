# AGENTS.md

给在本仓库工作的 coding agent 的指引。

## 这是什么
立正Skill（attention）——任意 Git 项目的"站好队"巡检与修复 Agent Skill。完整工作流见 `SKILL.md`。

## 工作约定
- **脚本黑盒**：`scripts/` 下的采集脚本先 `--help` 再调用，不要把源码读进上下文。bash（.sh）与 pwsh（.ps1）两套实现，按 `references/environment-and-prereqs.md` §6 探测 shell 选其一（**按能否执行探测，不是看文件在不在**）；JSON 契约见 `references/scan-recipes.md`。
- **只读采集**：脚本绝不自己提交/推送/删分支/开 PR；所有变更动作由你按 `SKILL.md` 工作流显式执行。
- **安全分层**：只读分析自动；本地变更需计划批准；远程不可逆动作（push、删远程分支、开 PR、推 tag）需最终确认。永远不 force push、不删未合并/受保护分支、**永不删默认分支**。无交互环境（无 `ask_user_question`）时：把计划写出来并**停下等确认**，不得自批。
- **报告大白话**：收尾报告主叙事面向项目作者（含新手），字段名/命令串/JSON 键不进主叙事，技术信号另放末尾"📋 技术细节（可选）"小节；含可发布判定（READY / NOT READY / BLOCKED）。
- **不编造**：文档与版本只反映真实 diff；下一步建议只基于真实信号（近期提交、开放 issue/PR、TODO、测试、缺失文档等）。**"没查成"必须写成"没查成"**（`null` + `warnings[]`），不得写成"没有"。

## 改本仓库时
- **提交规约**：conventional commits（`feat`/`fix`/`docs`/`chore`/`test`/`refactor`）；body 讲 WHY。
- **版本策略**：技能尚不完善，版本保持 `0.1.0`；变更记入 `CHANGELOG.md` 的 `[Unreleased]`，不随每次改动切版本号。
- **改脚本要成对**：同时改 `.sh` 与 `.ps1`。
- **改契约要三处同步**（**这是历史上漂移的根因**）：`references/scan-recipes.md`（单一事实源）+ `.sh` + `.ps1` + `evals/script-assertions.json` 的断言。只改一处即为漂移。
- **不要在 SKILL.md 里复述 references 的规则**：SKILL.md 只做路由 + 三条铁律。历次硬伤（force push 范围被窄化、受保护名单漏项、核心文档集三处不一致）全部发生在"速查副本"里。
- **自检**（提交前跑，两者都要绿）：
  - 全量回归：`pwsh -NoProfile -File evals/run_evals.ps1`（三层校验：严格 JSON + 双实现 parity + 断言表；bash 侧 `bash evals/run_evals.sh`）
  - 快速冒烟：`pwsh -NoProfile -File scripts/smoke_test.ps1 --repo .`（`bash scripts/smoke_test.sh`）
  - 测试工具说明见 `docs/VALIDATION.md`；审计背景与回归清单见 `docs/QUALITY-AUDIT.md`。

## evals/ 目录
- `evals/fixtures.ps1` / `fixtures.sh`：生成 19 个 fixture（F1–F19，**默认落在系统临时目录**——在仓库内会让"非 git 目录"负例失效）。成对实现，改一个必须改另一个。
- `evals/script-assertions.json`：断言表（唯一的期望值来源，当前 65 条）。**改断言等于改评测基准，必须同时说明理由**；不得为了变绿而放宽。
- `evals/run_evals.ps1` / `run_evals.sh`：runner，结果写 `evals/results/`（入库，作为验证证据）。
- **并发注意**：同时跑多个 runner 时用 `-FixturesDir`／`--out-dir` 指定不同目录，否则会互相删除重建 fixture 产生假失败。

## 依赖
`git`（必需）；`gh`（可选，开 PR 用）。运行时不要求 Python/Node/pwsh/bash 作为硬依赖——缺某条脚本路径的前置就换路径或走无脚本回退。`evals/` 的 runner 需要 pwsh（bash 侧建议有 python3 以做严格 JSON 校验）。
