# Changelog

本项目所有重要变更记录于此。格式参考 [Keep a Changelog](https://keepachangelog.com/)，版本号遵循 [语义化版本](https://semver.org/)。

## [0.2.0] - 2026-09-30

### Changed
- 收尾报告改用大白话：主叙事面向项目作者（含刚入行的开发者），禁止字段名 / 命令串 / JSON 键进入主叙事，原始技术信号另放末尾"📋 技术细节（可选）"小节，主叙事必须能独立读懂。
- SKILL.md 的 Phase 4 新增"报告语言原则"小节，并说明原因：满是字段名的报告对项目质量提升零帮助，报告的价值在于让用户立刻知道下一步干什么。

## [0.1.0] - 2026-09-29

首个可用版本。

### Added
- 立正核心工作流：Phase 0 前置探测 → Phase 1 状态快照 → Phase 2 干净/脏态分流 → Phase 3A 干净同步 / 3B 脏态修复 → Phase 4 收尾报告。
- 五个只读采集脚本（PowerShell）：git_state_snapshot / branch_cleanup_audit / version_consistency_audit / core_docs_relevance_scan / next_steps_analysis。
- 七份 references：环境与前置探测、判断标准、分支模型与保护、核心文档同步、发行版本、PR 与远程宿主、自主与安全。
- 四份 assets/templates：提交信息、PR body、CHANGELOG 条目、状态报告。
- 四个 evals（clean-sync / dirty-wip-fix / version-bump-release / non-github-fallback）及断言。
- LICENSE：CC-BY-NC-SA-4.0 完整 legalcode。