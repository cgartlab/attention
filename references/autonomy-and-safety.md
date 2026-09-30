# 自动化与安全

## 分层确认模型
- **只读分析**（所有 snapshot/audit 脚本、`git fetch`、`git log`、issue/PR 列表）：始终自动。
- **本地变更**（编辑文件、`git add`、`git commit`、本地 `git branch -d`、**本地 `git tag`**）：计划门槛一次批准后自动执行。
- **远程不可逆**（**`git push`（任何分支的普通推送也算）**、`git push origin --delete`（**必须带 `--force-with-lease=<branch>:<sha>`**，见 `branch-model-and-protection.md`）、`gh pr create`、**`git push <remote> <tag>`**、对远程默认分支的任何写入）：**在执行点单独做最终确认**。

### ⚠️ 计划门槛不覆盖 push
计划批准的是"改哪些文件、提交什么、删哪些本地分支"——**不含任何远程写入**。
即使计划表（`assets/templates/plan-table.md`）里写了"推送并开 PR"，那也只是告知下一步打算做什么；**执行到 push 那一刻仍须再确认一次**。把 push 混进"一次批准"，等于用"同意改文件"换走了"同意改远程"。

### ⚠️ tag 要拆成两件事
- **本地 `git tag <name>`** → 本地变更，计划内执行。
- **`git push <remote> <tag>`** → 远程不可逆，执行点单独最终确认。
- 推错的 tag 比推错的分支更难收拾（别人可能已经拉过），所以两者不能合并成一个"打并推 tag"的动作。

## 永远禁止
- `git push --force` / `--force-with-lease` 到默认分支或受保护分支。
- 直接 push 到默认分支（任何改动走 PR）。
- **永不删默认分支或受保护分支**——`main`、当前默认分支（无论叫什么）、`release/*`、以及受保护名单里的任何分支，**本地与远程都不许删**；当前所在分支同样永不删。
- 删未合并分支（`-D` 强删、`push --delete` 未合并的远程分支）。
- 纳入 `.gitignore` 排除的文件（`node_modules`、`dist`、`.env` 等）。
- 在 detached HEAD 下做脏态修复的提交（先提示切分支）。
- 自动改 `.git/config`。

## 非交互环境（delegated / 无人值守 / 无 `ask_user_question`）
- **只读分析可以照做**：Phase 0/1/2 的探测与判定、出候选清单、写报告草案，都不需要交互。
- **一切变更动作与远程动作都必须停在确认点**：把完整计划（或干净态的剪枝候选）**写在回复里，然后停下等待用户确认**。
- **不得自批**：把"没人可问"当成"默认同意"，会直接绕过分层确认模型——这是硬规则。宁可交一份"计划待确认"就结束，也不要先做了再说。
- 同样适用于任何拿不到用户回应的通道：CI 任务、定时任务、被其他 agent 转交的执行。

## 边界情况处理
- **detached HEAD**：脏态修复前提示用户切到/新建分支；不直接在 detached HEAD 提交。
- **零提交仓库（unborn HEAD）**：`head_short=null` + `head-unborn` 警告；不能算"干净"，也不能基于不存在的 `origin/<default>` 做比较。
- **shallow clone**：`--merged` 判断受限，剪枝降级为基于已合并 PR 判断（gh），不强删。
- **无 upstream**：`unpushed_commits=null` 时按"不可判定"处理（见 `judgment-criteria.md` 的干净/脏态），不当作"全部已推送"；提示用户设 upstream。
- **未跟踪的半成品文件**：**不得删除**——它们是用户还没纳入版本控制的工作。要么在计划里提议提交，要么列入计划表"需你确认"让用户裁定。
- **stash**：**只报告**（`stash_count` 与 `git stash list`），**不 `drop`、不 `apply`、不 `pop`**——stash 里可能是用户故意藏起来的未完成工作。
- **多 remote**：PR 针对 `origin`（或用户指定主 remote）；不向所有 remote push。
- **monorepo**：版本一致性覆盖全部 workspace 成员版本文件（见 `version-file-inventory.md`）。
- **预存在且与本变更无关的失败测试**：报告，不阻塞；若本变更引入的失败则必须修绿。
- **pull 冲突**：停止，报告冲突文件，不 force、不自动 merge。
- **merge commit 风险**：干净态只用 `--ff-only`；出现分叉走脏态或单独决策。
