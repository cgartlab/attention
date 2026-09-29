# 自动化与安全

## 分层确认模型
- 只读分析（所有 snapshot/audit 脚本、fetch、log、issue 列表）：始终自动。
- 本地变更（编辑文件、`git add`、`git commit`、本地 `git branch -d`、stash 处理）：计划门槛一次批准后自动执行。
- 远程不可逆（`git push`、`git push origin --delete`、`gh pr create`、`git tag` + push tag、远程默认分支任何写入）：执行点单独最终确认。

## 永远禁止
- `git push --force` / `--force-with-lease` 到默认分支或受保护分支。
- 直接 push 到默认分支（任何改动走 PR）。
- 删未合并分支（`-D` 强删、`push --delete` 未合并远程分支）。
- 删受保护分支。
- 纳入 .gitignore 排除的文件（node_modules、dist、.env 等）。
- 在 detached HEAD 下做脏态修复的提交（先提示切分支）。
- 自动改 `.git/config`。

## 边界情况处理
- detached HEAD：脏态修复前提示用户切到/新建分支；不直接在 detached HEAD 提交。
- shallow clone：`--merged` 判断受限，剪枝降级为基于已合并 PR 判断（gh），不强删。
- 无 upstream：未推送 = 当前分支全部提交；提示设 upstream。
- 多 remote：PR 针对 origin（或用户指定主 remote）；不向所有 remote push。
- monorepo：版本一致性覆盖全部 workspace 成员版本文件。
- 预存在且与本变更无关的失败测试：报告，不阻塞；若本变更引入的失败则必须修绿。
- pull 冲突：停止，报告冲突文件，不 force、不自动 merge。
- merge commit 风险：干净态只用 `--ff-only`；出现分叉走脏态或单独决策。