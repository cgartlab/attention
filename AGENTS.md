# AGENTS.md

给在本仓库工作的 coding agent 的指引。

## 这是什么
立正Skill（lizheng）——任意 Git 项目的"站好队"巡检与修复 Agent Skill。完整工作流见 `SKILL.md`。

## 工作约定
- **脚本黑盒**：`scripts/` 下的采集脚本先 `--help` 再调用，不要把源码读进上下文。bash（.sh）与 pwsh（.ps1）两套实现，按 `references/environment-and-prereqs.md` §6 探测 shell 选其一；JSON 契约见 `references/scan-recipes.md`。
- **只读采集**：脚本绝不自己提交/推送/删分支/开 PR；所有变更动作由你按 `SKILL.md` 工作流显式执行。
- **安全分层**：只读分析自动；本地变更需计划批准；远程不可逆动作（push、删远程分支、开 PR、推 tag）需最终确认。永远不 force push 默认分支、不删未合并/受保护分支。
- **报告大白话**：收尾报告主叙事面向项目作者（含新手），字段名/命令串/JSON 键不进主叙事，技术信号另放末尾"📋 技术细节（可选）"小节。
- **不编造**：文档与版本只反映真实 diff；下一步建议只基于真实信号（近期提交、开放 issue/PR、TODO、测试、缺失文档等）。

## 改本仓库时
- **提交规约**：conventional commits（`feat`/`fix`/`docs`/`chore`）。
- **版本策略**：技能尚不完善，版本保持 `0.1.0`；变更记入 `CHANGELOG.md` 的 `[Unreleased]`，不随每次改动切版本号。
- **改脚本要成对**：同时改 `.sh` 与 `.ps1`，并对齐 `references/scan-recipes.md` 契约，防双份漂移。
- **自检**：在 lizheng 仓库上跑立正本身（`pwsh -NoProfile -File scripts/*.ps1 --repo .`）确认无回归。

## 依赖
`git`（必需）；`gh`（可选，开 PR 用）。运行时不要求 Python/Node/pwsh/bash 作为硬依赖——缺某条脚本路径的前置就换路径或走无脚本回退。
