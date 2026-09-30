# 分支模型与保护

## 默认分支探测梯子
见 `environment-and-prereqs.md` 第 2 条。结果一句话向用户确认。

## 受保护名单（永不删）
内置：`main`、`master`、`develop`、`dev`、`trunk`、`release/*`、`prod`、`production`、`gh-pages`、`gh-readonly`、当前分支本身。
外加：`gh api repos/{owner}/{repo}/rules/branches/{branch} --jq 'any(.[]; .type=="deletion")'` 命中者（**按分支查询实际生效的规则**）。**不要用 `GET /rulesets` 列表**（实测不含 `rules`/`conditions`，判不出来），也不要用已被取代的 `branches/{b}/protection`（无认证 401、非管理员 404）。查询集合与失败语义见 `scan-recipes.md` §2。
- **`--paginate` 不能省**：该接口默认每页 30 条，分支多的仓库会漏掉后面的受保护分支，进而把它们当成可删候选。
- 当前默认分支无论叫什么都受保护（即使名字不在上面的名单里）。

脚本 `branch_cleanup_audit` 输出的 `protected` 字段 = 内置集合 ∪ `release/*` 通配 ∪ `{当前分支}` ∪ `{默认分支}`，**已去重排序**（见 `scan-recipes.md`）。脚本不查 `gh api`（那是模型动作），所以 `protected` 是**下界**：拿到脚本结果后仍要补上 API 查到的那批。

## 本地剪枝
- 候选（**本地**）：`git branch --merged <本地默认分支>` 去掉受保护名单、去掉当前分支。
  - **基准**：本地删除不丢内容，用本地默认分支即可；改用 `origin/<默认分支>` 会把"本地已合并、尚未推送"的候选漏报成空集（实测假阴性）。仅当本地默认分支不存在时才回退 `origin/<默认分支>`，并在 `local_merge_base` 中体现。
- 执行：`git branch -d <branch>`。`-d` 拒删未合并，作为第二道保险；若因"未完全合并"失败，**不用 `-D` 强删**，记入报告让用户决定。
- 不删 detached HEAD 时的"分支"。

## 远程剪枝
- 先 `git fetch --prune` 清理已不存在的 remote-tracking 引用。
- **候选判定（三条全部满足才算候选）**：
  1. **已合并入默认分支**：`git branch -r --merged origin/<默认分支>` 含它（对应 `remote_merged_candidates[].tracking_ref`）。
     - **基准守卫**：先用 `git rev-parse --verify --quiet refs/remotes/origin/<默认分支>` 确认基准存在；不存在 → `remote_base_unverified=true`、远程候选一律为空 + `remote-base-unverified` 警告（**不得**把"基准不可用"当成"没有可删的远程分支"）。
     - 远程候选必须用 `origin/<默认分支>` 作基准：用本地分支会在"本地已合并、远程尚未收到"时误判，删远程分支即丢数据。
  2. **非受保护**：不在上面的受保护名单里。
  3. **无开放 PR**：`gh pr list --state open --head <branch> --json number,title`（GitHub）。
     - `gh_query_state == "ok"` **且返回空** → 确认无开放 PR，可进入删除计划。
     - `gh_query_state != "ok"`（未登录 / 非 GitHub / 查询失败）→ **降级为"只报告不删"**：把候选列出来，说明"没能确认有没有开放 PR"，交用户在计划门槛里裁定。**不得**把"没查成"当成"没有开放 PR"。
     - 非 GitHub 宿主：按 `pr-and-remote-hosts.md` 用该宿主的等价查询；查不到同样降级为只报告。
- ❌ **不得**把删除条件写成"远端已经没有这个分支了"（或等价的"远端不再有对应 ref"）：候选本身就来自 remote-tracking ref，且在 `git fetch --prune` 之后该条件**恒假**——规则会退化成"永远没有远程候选"，表面干净、实际漏报。可判定条件就是上面三条。
- **远端不可达时整体降级**：`remote_reachable=false`（`git ls-remote origin` 失败）或 `warnings[]` 含 `remote-unreachable` → 远程候选不可信，**只报告不删**，并如实说"没连上远程"，不得说成"没有可清理的远程分支"。
- `remote_exists` 比对必须**精确匹配**（`grep -Fxq` / 哈希表），不得用无锚定的子串匹配（`feat` 会误配 `feat-x`）。
- 执行（**必须带 lease**）：`git push origin --force-with-lease=<branch>:<sha> --delete <branch>`，`<sha>` 取本轮审计记录的 `remote_merged_candidates[].tip_sha`；或 `gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/<branch>`（该端点无 lease 能力，故仅在能用 lease 的路径不可用时使用，并须在删除前再次 `git ls-remote` 复核 tip）。
  - **为什么必须带 lease**：不带 lease 的 `--delete` 会静默删掉"等你确认"的窗口里别人推送的提交（实测可复现的数据丢失）。lease 的 refname 必须与分支完全同名，写错等于没有 lease。
  - 删除一个已不存在的远程分支 = 幂等成功，不报错。
- 远程删除不可逆——按 `autonomy-and-safety.md` 做**执行点单独最终确认**（计划门槛不覆盖它）。

## worktree / submodule
- worktree：只看当前 worktree 的 HEAD 与分支；不跨 worktree 删分支。
- submodule：不动子模块 HEAD 与分支。
