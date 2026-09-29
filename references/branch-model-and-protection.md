# 分支模型与保护

## 默认分支探测梯子
见 `environment-and-prereqs.md` 第 2 条。结果一句话向用户确认。

## 受保护名单（永不删）
内置：`main`、`master`、`develop`、`dev`、`trunk`、`release/*`、`prod`、`production`、`gh-pages`、`gh-readonly`、当前分支本身。
外加：`gh api repos/{owner}/{repo}/branches --jq '.[] | select(.protected==true) .name'` 返回的仓库保护分支。
当前默认分支无论叫什么都受保护。

## 本地剪枝
- 候选：`git branch --merged <默认分支>` 去掉受保护名单、去掉当前分支。
- 执行：`git branch -d <branch>`。`-d` 拒删未合并，作为第二道保险；若因"未完全合并"失败，不用 `-D` 强删，记入报告让用户决定。
- 不删 detached HEAD 时的"分支"。

## 远程剪枝
- 先 `git fetch --prune` 清理已不存在的 remote-tracking 引用。
- 候选：`git branch -r --merged <默认分支>` 中，去掉受保护、去掉 `HEAD ->`。
- 对每个候选，确认远端实际已无活跃分支（`git ls-remote` 确认远端无对应 ref，或 `gh api` 查）。
- 执行：`git push origin --delete <branch>` 或 `gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/<branch>`。
- 远程删除不可逆——按 `autonomy-and-safety.md` 最终确认。

## worktree / submodule
- worktree：只看当前 worktree 的 HEAD 与分支；不跨 worktree 删分支。
- submodule：不动子模块 HEAD 与分支。