# 判定定义速查

Phase 2 分流与各门槛的精确边界。判定要保守：拿不准归脏态，让人看一眼。

## 干净态 vs 脏态
脏态当且仅当以下三条任一为真：
- 未提交改动：staged、unstaged、untracked 任一非空（untracked 只计未被 .gitignore 排除者）。
- 未推送提交：当前分支存在可达但不在任何 remote-tracking ref（`refs/remotes/*`）上的提交。无 upstream 时视全部为未推送。
- 未推送分支：本地分支其 tip 不被任何远程 ref 覆盖。

全假 → 干净态。有 stash 不算脏态硬条件，但要在报告里提及（stash 是隐藏的未完成工作）。

## 无价值分支（可删候选）
满足全部才算：
1. 已完全合并入默认分支：`git branch --merged <默认分支>`（本地）或 `git branch -r --merged <默认分支>`（远程）。
2. 不在受保护名单（见 `branch-model-and-protection.md`）。
3. 远程删除额外要求：远端已无活跃对应分支。

陈旧但未合并的分支：只报告，不删——删了等于丢工作。

## 未推送提交（精确）
- 有 upstream：`git log @{u}..HEAD --oneline` 非空。
- 无 upstream：`git log <默认远程>/<默认分支>..HEAD` 非空，或无可比远程则当前分支全部提交视为未推送。

## 涉及 release
满足任一：
- 变更集（未提交 + 未推送）触及任意版本承载文件（见 `release-versioning.md`）。
- 提交信息含 `chore(release)` / `feat!` / `BREAKING CHANGE`。
- 用户明示"这是 release / 要发版"。

触发发行版本门槛。

## 核心文档集（默认）
README*、CHANGELOG*、CHANGES*、HISTORY*、AGENTS.md、CLAUDE.md、CONTRIBUTING*、LICENSE*、`docs/**` 下被 README 索引的文档 + 各生态版本文件。项目可覆盖。

## 拿不准怎么办
归脏态，在计划门槛里向用户列出不确定点，让用户裁定。不默认假设"应该是干净的"。