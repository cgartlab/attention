# 值守循环：issue → PR → 评审 → 合并

> 本文件是**流程**的单一事实源。判定口径（issue triage、UI 白名单、合并门、关闭判据）在 `judgment-criteria.md`；动作档位与禁止清单在 `autonomy-and-safety.md`；这里只写"按什么顺序做、每步产出什么"。
> 适用：用户要求"巡检 open issue / 值守 / 每轮处理一个 issue 或 PR / 把 PR 修到可合并"等持续性意图。一次性的"收拾这个仓库"仍走 Phase 3A/3B。

## 1. 轮次模型（三条，先立规矩再谈流程）

1. **一轮只处理一个对象**（一个 issue 或一个 PR）。做完 → 收尾 → 停。不得在同一轮里"顺便"处理第二个，也不得因为第一个做完了就自动开第二轮——下一轮由用户发起。
2. **幂等键 = issue 编号**（对象是 PR 时用 PR 编号）。同一幂等键在同一阶段不得重复劳动：不得重复开 PR、不得重复回复同一条结论。
3. **进度留痕只一处**：在 issue 上维护**一条**带 `<!-- attention:progress -->` 标记的评论（不存在则创建，存在则用 `gh api -X PATCH` 编辑同一 `comment_id`）。字段固定：

```json
{"stage":"triage|implement|review|verify|merge|blocked|closed","branch":"<name|null>","pr":"<number|null>","verified_sha":"<sha|null>","updated":"<ISO8601>"}
```

   - 每轮**开始**先读该标记的最新一条，据此决定从哪一步接续（避免重复劳动、避免同一 issue 开第二个 PR）。
   - ❌ 不得为"我还活着"发评论；同一阶段无实质变化不更新。
   - ❌ 不得在 issue 上连发流水账，把讨论区变成日志。

## 2. 步骤 0：前置门（任一不成立 → 降级为只报告，不进入循环）

| 条件 | 不成立时 |
|---|---|
| `is_git=true` 且有 remote | 说明并停（纯本地仓库不跑循环） |
| `is_github=true` | 非 GitHub：只输出"issue/PR 就绪产物"（标题、正文、分支名、手动指引），不编造宿主命令 |
| `gh_authed=true` **且** `gh_query_state="ok"` | 只报告：明确写"issue 查询没查成"（`null` + `warnings[]`），**不得**写成"没有 open issue" |
| 工作区干净 | 走第 12 节脏态规则：**不提交、不 stash**，输出评估后停下问 |

**字段用途边界（容易搞错）**：`next_steps_analysis` 的 `open_issues` / `open_prs` 是 `gh list` 的**单行字符串数组**，只够回答"有没有"，**不含** number/labels/updatedAt/body——`judgment-criteria.md` 的 triage 判定**不得**基于这两个字段，必须用下面的实时查询：

```bash
gh issue list --state open --limit 30 --json number,title,labels,updatedAt,comments,assignees
gh pr list    --state open --limit 30 --json number,title,labels,isDraft,reviewDecision,headRefName,updatedAt,mergeable
gh issue view <n> --json number,title,body,labels,comments,assignees,timelineItems
```

## 3. 步骤 1：选对象（issue triage）

候选排序：带 `P0`/`P1` 或 `bug` 的在前 → 其次 `updatedAt` 新的在前 → 其余按编号。逐个过 `judgment-criteria.md` §「issue triage 门」；第一个通过的就是本轮对象。

- 全部不通过 → 本轮结束，报告里列出每个 issue 及其**缺什么**（缺验收标准 / 缺复现 / 被 `wontfix` 等），不得为了"有事可做"放宽标准。
- 有 issue 通过但本轮**已经**处理过（进度评论里的 `stage` 未到终态）→ 从记录的阶段接续，不重新 triage。

## 4. 步骤 2：查重（是否已有对应 PR）

三条线索，**任一命中即视为"已有相关 PR"**，进入第 6 节评审路径：

1. issue 正文/时间线里出现 `#<pr>` 交叉引用，或 `Closes|Fixes|Resolves #<issue>`；
2. `gh pr list --state all --search "#<issue> in:body"`（GitHub 的 body 搜索；空结果**不等于**没有 PR，必须配合第 3 条）；
3. 分支名命中 `<type>/<issue>-<slug>`、`issue-<n>-*`、`<issue>-*`（精确前缀匹配，不得子串乱配）。

三条都不中 → 第 5 节实现路径。**注意**：三条都不中只能说明"没找到关联"，不等于"确定没有"——开 PR 前仍按 Phase 3B 第 8 步查一次同题开放 PR。

## 5. 步骤 3A：无 PR → 实现并开 PR

1. `git switch main` + `git pull --ff-only`（分叉 → 停，不 merge、不 force）。
2. 从最新 main 建分支：`<type>/<issue>-<slug>`（type 用 `judgment-criteria.md` 的 commit 类型映射）。
3. 按"尽可能完整细致"实现：**issue 指出的问题 + 排查中发现的同源问题**（同类缺陷一次修干净，别只补报告的那一处）。范围超出 issue 的，在 PR body 里单列一节说明为什么顺带。
4. 逐步验证（见第 7 节"实跑"），全绿后再提交。
5. 提交前过 Phase 3B 的两道门槛（文档同步、版本门）。
6. `gh pr create`，body 首行写 `Closes #<issue>`（GitHub 据此自动关联）；模板见 `assets/templates/pr-body.md`。
7. 进第 6 节评审路径——**自己的 PR 也要按同一清单自查一遍**，不得因为"我刚写的"跳过。

## 6. 步骤 4：有 PR → 评审（逐行，不是看摘要）

按 `assets/templates/pr-review.md` 全文过一遍，**并满足下面三条硬要求**：

1. **像 reviewer 一样读全文 diff**：`gh pr diff <n>` 逐文件读，不只看统计与文件名。每个改动点回答三问：正常路径对不对、失败路径会不会被吞、边界/跨平台对不对。
2. **代码拉下来实跑**（第 7 节）——"读着没问题"不算证据。
3. **反馈处理**：`gh pr view <n> --json reviews,comments`；有 `CHANGES_REQUESTED` 或未决评论必须先解决（修 → 回复 → 请求 re-review），不得带着未决反馈合并。

评审结论只能三选一：`可合并` / `可修 → 我来修` / `应关闭`（判据见第 9 节）。

## 7. 步骤 5：实跑（"验证过"的定义）

在**隔离目录**跑，绝不污染主工作树：

```bash
git fetch origin pull/<n>/head:pr-<n>        # 或 git fetch origin <headBranch>
git worktree add --detach ../attn-verify-<n> pr-<n>
# 在 worktree 里：跑项目声明的全部检查（run_evals / smoke_test / test / lint / build / typecheck）
git worktree remove ../attn-verify-<n>        # 收尾（worktree 不参与分支剪枝，见 LESSONS）
```

- 检查项来源：`next_steps_analysis.test_commands`（不要凭印象挑）；本仓库自带入口为 `evals/run_evals.*` 与 `scripts/smoke_test.*`。
- 每条命令记录**命令 + 退出码 + 结论摘要**（pass/fail 计数），写进 PR 评论（第 10 节）。❌ 不得只写"测试通过"。
- 该修但修不了（环境缺依赖/跨平台不可用）→ 如实写"没跑成"+ 缺什么；**没跑成不得当作通过**。
- UI 相关改动另需截图证据（第 8 节）。

## 8. 步骤 6：合并门（四层，全过才可合并）

判定口径见 `judgment-criteria.md` §「合并门」；此处只强调顺序与降级：

| 层 | 内容 | 不通过时 |
|---|---|---|
| L1 客观信号 | CI 全绿（无 CI 时：本地等价证据 + 明确标注"CI 未跑"） | 不合并 |
| L2 内容门 | 评审清单全过、无未决反馈；diff 与 issue 一致；契约四处同步 / 双实现成对 / 断言未放宽 / 文档已同步 / 无 secret | 不合并 |
| L3 授权门 | 合并授权存在（见第 8.1）；**强 UI 改动 → 无论有无授权都不自动合并** | 转为"PR READY，等人工" |
| L4 动作门 | 合并动作本身在执行点确认（授权明确覆盖时可不问，UI 除外） | 停 |

**8.1 授权的来源与优先级**（从高到低，取最高者）：

1. 用户在**当前对话**明说"这轮可以合并 / 非 UI 的直接合"；
2. 仓库持久标记：**仅** PR 带 `auto-merge` 标签（已裁定：不引入 `.github/attention.auto-merge` 配置文件，避免多一个授权来源）；
3. 默认：**无授权 → 只给合并建议 + 证据**。

> ❌ "立正过一遍"本身不是合并授权；提示词里"验证通过就合并"若来自**历史文案**而非本轮明说，按第 3 档处理。

**8.2 合并方式**：**固定 squash**——`gh pr merge <n> --squash --delete-branch=false`。这条写死：不探测、不随仓库风格漂移，要改就由用户明确指定（`--merge` / `--rebase`）。源分支删除单独执行（`--force-with-lease=<branch>:<sha>`，见 `branch-model-and-protection.md`）。

**8.3 UI 截图门（硬门）**：强 UI 改动必须满足 ① 有改进后的有效截图（渲染真实页面，不是设计稿、不是文字描述）② 截图与改动一致（同一分支、同一 SHA）③ PR 评论内联展示。三条缺一 → 一律不合并，等用户手动确认。

截图证据的落地方式（GitHub 不接受直接上传二进制）：

```bash
# 1) 渲染：固定视口 1440×900 与 390×844；项目支持浅/深色则各一张
# 2) 存放：证据分支，不进默认分支
git worktree add --detach ../attn-evidence attention/evidence-pr-<n> || git switch -c attention/evidence-pr-<n> main
mkdir -p docs/evidence/pr-<n> && cp shot-*.png docs/evidence/pr-<n>/
git add docs/evidence && git commit -m "docs(evidence): PR #<n> 视觉截图" && git push origin attention/evidence-pr-<n>
# 3) 引用：PR 评论内联
#    ![after](https://raw.githubusercontent.com/<owner>/<repo>/attention/evidence-pr-<n>/docs/evidence/pr-<n>/shot-1.png)
```

- 证据分支**只增不改**；PR 关闭/合并后不自动删（回溯用），删由用户决定。
- 没有渲染能力（无浏览器/无构建产物）→ 输出 `BLOCKED` + 缺什么。❌ 不得用旧截图、不得用设计稿、不得口头描述替代。

## 9. 步骤 7：不合并 → 回复或关闭

| 情形 | 动作 |
|---|---|
| 有可修的阻塞（CI 红 / 缺文档 / 判据不符） | **修**：按第 6 节闭环，修完重新验证 |
| 修不了但不是方向错误（缺权限、缺环境、需上游） | **回复 PR/issue**：写清阻塞点、证据、需要谁做什么；状态 `BLOCKED` |
| 重复（已有等价 PR/issue） | 先评论指出现存对象编号 → 关闭后者 |
| 已被 main 覆盖（内容已在默认分支上） | 先评论给出证据（`git diff` 为空 / `git cherry -` 命中）→ 关闭 |
| 方向与项目定位冲突 / 无法复现且长期无回应 | 先评论说明理由 + 给出需要的复现信息 → 关闭 |

**关闭判据的可判定条件**见 `judgment-criteria.md` §「PR/issue 关闭判据」。两条硬约束：

- **先评论、后关闭**，顺序不可颠倒（关闭会把讨论区静音，理由必须已经在场）。
- 关闭是远程不可逆动作 → 执行点单独确认（档位见 `autonomy-and-safety.md`）。

## 10. 步骤 8：合并后收尾

1. `gh pr merge --squash` → 复核 `gh pr view <n> --json state`（`MERGED`）。
2. 删源分支（带 lease，sha 取合并前的 head）。
3. `git switch main` + `git pull --ff-only`。
4. **再跑一次立正**（Phase 3A 轻量路径）：剪枝候选先列后删、给下一步建议。
5. 更新进度评论：`stage=closed`（issue 由 `Closes #n` 自动关闭则只更新评论）。

## 11. 本轮报告（在通用收尾报告上加一节）

`assets/templates/status-report.md` 的"本轮对象"一节必填：

- 对象：`#<n> <标题>`（issue 或 PR）、类型
- 做了什么：实现 / 评审 / 修复 / 回复 / 关闭 / 合并，一句话
- 证据：跑了什么命令、退出码、pass/fail 计数；UI 改动的截图链接
- 判定：`MERGED` / `PR READY（等人工）` / `NOT READY` / `BLOCKED` / `SKIPPED（triage 未通过）`
- 为什么停在这里：一句话；若 `BLOCKED`，写清卡在谁/什么

## 12. 脏态特例（覆盖 Phase 3B 的默认行为）

循环轮次里，**工作区有未提交改动 = 立刻停止提交动作**：

1. 收集事实：`git status --short`、涉及文件、是否与本 issue 相关、`stash_count`。
2. 输出评估：这些改动像什么（上一轮残留 / 用户 WIP / 与本 issue 相关），**不 stage、不 commit、不 stash、不 clean、不 pull**（pull 会带入冲突风险）。
3. 停下问用户，给出三选：由用户自己处理 / 授权本轮提交（附提交计划表）/ 先搁置并改做只读分析。

**唯一例外**：用户在**当前对话**明确说"收拾这个仓库 / 提交这些改动"——此时按 Phase 3B 原规则（计划表批准后提交）执行。历史对话里的"顺手清理"不算。

## 13. 与既有 Phase 的关系

- Phase 3A（干净态）与 Phase 3B（修复交付）：**不变**，用于"用户要求收拾仓库"。
- Phase 3C（本文件）：用于"值守循环"，其第 5 步复用 3B 的实现与门槛，其第 8 步复用 3A 的剪枝。
- ❌ 不得为了走循环而跳过 3B 的两道门槛（文档同步 / 版本门）；循环只是多了评审、实跑、合并、回复、关闭这几件事，**没有放宽任何一道既有门槛**。

## 14. 明确不做的事（避免越权与过度承诺）

- 不主动创建 issue（`SKILL.md` 现行规则）；发现新问题 → 写进 PR body 的"顺带修复"或报告，由用户决定是否开 issue。
- 不做 issue 指派、不打标签、不改 milestone（`gh issue edit` 属远程写，未经授权一律不动）。
- 不在非 GitHub 宿主上编造 `gh` 等价命令；只产出可粘贴的文本产物。
- 不在同一轮处理第二个对象；**不做定时值守（cron）**——下一轮必须由用户发起（已裁定）。
- 不在无人值守时自批合并：授权门第 1 档要求"当前对话"，被委派/无人值守时最高只能到 `PR READY`。
