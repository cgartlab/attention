# 判定定义速查

Phase 2 分流与各门槛的精确边界。判定要保守：拿不准归脏态，让人看一眼。

> **本文件是这些判定定义的单一事实源**：干净/脏态、未推送判定、无价值分支、陈旧阈值、涉及 release 的多层门、核心文档集、门槛通过条件——**完整定义只写在这里**。其他文件遇到这些规则一律引用本文件，不复述（复述出来的副本正是历史上漂移的地方）。字段名与 `null`/`[]` 语义以 `scan-recipes.md` 的 JSON 契约为准。

## 干净态 vs 脏态
脏态当且仅当以下三条任一为真（字段来自 `git_state_snapshot`，语义见 `scan-recipes.md`）：

- **未提交改动**：`staged`、`unstaged`、`untracked` 任一非空（`untracked` 只计未被 `.gitignore` 排除者）。
- **未推送提交**：`unpushed_commits` 非空。
  - 脚本采集顺序：`origin/<默认分支>` 存在 → `git log --oneline origin/<默认分支>..HEAD`；否则有 upstream → `@{u}..HEAD`；**都没有 → `null`**。
  - ⚠️ **`unpushed_commits=null` 表示"无任何可比远程"，属不可判定，不得判定为"干净"**。此时既不能证明推送过、也不能证明没推过，应归脏态（或至少在计划门槛里把这条不确定性列出来让用户裁定）。把 `null` 读成 `[]` 就是"把没查成讲成没有"。
- **未推送分支**：`has_remote=true` 且 `unpushed_branches` 非空（本地分支 tip 不被任何 `refs/remotes/*` 覆盖）。这类分支上的提交可能一条都没进过远程，即使当前分支本身是同步的。
  - ⚠️ **`has_remote=false`（纯本地仓库）时本条与上一条「未推送提交」均属"不适用"，不参与脏态判定**：没有远程就无所谓推送；此时只看「未提交改动」一条，并按 `environment-and-prereqs.md` §3 的"无 remote → 纯本地仓库：跳过 fetch/pull/PR，只做本地巡检与本地分支剪枝"执行。把"不适用"当成"不可判定"会判成脏态，然后去推送一个不存在的远程（实测本仓库即如此）。

三条全假 → 干净态。`stash_count > 0` 不算脏态硬条件，但要在报告里提及（stash 是隐藏的未完成工作），且**只报告不动作**（见 `autonomy-and-safety.md`）。

## 无价值分支（可删候选）
需同时满足：

1. **已完全合并入默认分支**：本地列表用**本地默认分支** `git branch --merged <本地默认分支>`；远程列表用 **`origin/<默认分支>`** `git branch -r --merged origin/<默认分支>`。
   - **为什么两侧基准不同（实测教训）**：删本地分支不丢内容（提交已在本地默认分支里），所以本地用本地分支即可；改用 `origin/<默认分支>` 会把"本地已合并但尚未推送"的候选**漏报成空集**（假阴性）。删远程分支不可逆，必须用 `origin/<默认分支>`——用本地分支作基准会在"本地已合并、远程尚未收到"时误判为已合并，**删远程分支即丢数据**。
   - **基准守卫**：用 `origin/<默认分支>` 前先 `git rev-parse --verify --quiet refs/remotes/origin/<默认分支>`；不存在 → `remote_base_unverified=true`、远程候选一律为空、加 `remote-base-unverified` 警告。脚本输出 `local_merge_base`/`remote_merge_base` 两个字段供复核。
   - **形态注意**：本地默认分支不存在时 `git branch --merged <名字>` 会 `unknown revision` 并静默给空集——此时回退到 `origin/<默认分支>`，并在 `local_merge_base` 里体现用的是哪一个。
2. **不在受保护名单**（名单与判定见 `branch-model-and-protection.md`）。
3. **远程候选另有第四条判据**：见 `branch-model-and-protection.md` 的"远程剪枝"（已合并 + 非受保护 + **无开放 PR**）。
   - ❌ **不得**把删除条件写成"远端已经没有这个分支了"（或等价的"远端不再有对应 ref"）：候选本身就来自 remote-tracking ref，`git fetch --prune` 之后该条件**恒假**，规则会退化成永远没有候选（表面"干净"，实际漏报）。

**陈旧但未合并的分支：只报告，不删**——删了等于丢工作。

## 被 main 取代的分支（superseded）

脏态分支若计划开 PR 合入默认分支，先判它是否被 main **取代**——取代的分支开 PR 只会把 main 主动删掉的内容加回去，或重复已经合入的工作，等于推翻 main 的显式决定。

**判定（在呈现 PR 计划前执行，且必须在动手前用当前 `origin/<默认>` 重算）**：

1. 重算净差异：`git diff --stat origin/<默认>..HEAD`。长程只读巡检中远程跟踪引用可能被 fetch 或外部推送更新，早期快照的 diff 不等于动手时的 main——**动手前必须重算一次**，不要信首轮快照。
2. 对净差异里每个「分支新增」文件，判两种取代信号：
   - **已合入**：该文件在 `origin/<默认>` 里已存在且内容相同（同 blob，如经另一条 PR 合入）。`git diff origin/<默认>..HEAD` 对该文件无真实改动即佐证；用 `git ls-tree origin/<默认> -- <file>` 比 blob 确认。
   - **被主动删**：`git log origin/<默认> --oneline -- <file>` 命中带 remove / delete / revert 语义的提交，说明 main 故意删掉了它。
3. 若净差异**整体**落入上述两类（无真正独有的对外改动）→ 分支已被取代。

**处置**：不开 PR，转**废弃流程**——本地删除该分支（内容已在 main，丢弃无丢失；用 `-D` 前先确认 `git diff origin/<默认>..HEAD` 无独有内容）；远程分支按用户裁定保留或删。此结论会**实质改变执行方向**（用户可能仍想加回被删文件），必须在动手前重新与用户确认，不得默开 PR。

**与「无价值分支」的区别**：无价值分支指已合并、可安全剪枝的本地/远程分支（见上节）；被取代分支指仍有未合并提交、但内容已被 main 吸收或主动删除的**待交付**分支——前者剪枝、后者废弃，二者不可混用，别把「已被取代」误判成「无价值可删」而直接走剪枝路径。

## 陈旧 / 活跃的阈值（可判定，不留形容词）
- `age_days` 由脚本按 `now − <分支 tip 的 commit date>` 计算（见 `scan-recipes.md` 的 `branch_cleanup_audit`）。
- **陈旧（stale）**：`age_days > 30`。
- **活跃（active）**：`age_days <= 30`。
- **30 天是默认值，允许覆盖**：项目有明确节奏（月度发版、季度维护分支）或用户给了口径时按用户口径。**覆盖时必须说明用的阈值与理由**（例如"按项目季度维护节奏用 90 天"），不能默默换数。
- 陈旧 + 未合并 → 进 `local_stale_unmerged_report`，**只报告**。

## 涉及 release：多层门（信号层 → 门槛层）
**脚本只负责信号层；门槛层判定是模型职责，且必须写明理由**（指到具体文件/符号/提交，不能只给一个布尔值）。

### 第一层 信号层（宽口径："可能涉及 release"）
由 `version_consistency_audit` 的 `release_signals[]` 给出。**kind 取值与产出规则的权威定义在 `scan-recipes.md` 的 `release_signals` 契约**；下表只是"谁产出"的分层视图，有出入以契约为准：

| 信号 kind | 触发条件 | 谁产出 |
|---|---|---|
| `version-file-touched` | 变更集与任一版本承载文件有交集 | 脚本 |
| `commit-chore-release` | 提交标题含 `chore(release)` | 脚本 |
| `commit-breaking` | 提交标题含 `feat!` / `fix!` | 脚本 |
| `commit-feat` | 提交标题以 `feat` 开头 | 脚本 |
| `commit-fix` | 提交标题以 `fix` 开头 | 脚本 |
| `breaking-footer` | 提交正文前 20 行含 `BREAKING CHANGE:` / `BREAKING-CHANGE:` | 脚本 |
| `user-intent` | 用户明示要发版，或传了 `--target-version` | **模型补写**（脚本不臆测用户话语） |

宽口径意味着**信号非空 ≠ 要 bump**：`fix:`/`feat:` 天天有；`version-file-touched` 可能只是改了 README 里的一行版本号示例。

### 第二层 门槛层（窄口径："本次真的需要 bump"）
信号层命中后，逐个信号问一句：**这个改动对使用者的可见行为有变化吗？** 按下表判定：

| 情形 | 需要 bump？ | 必须给出的理由 |
|---|---|---|
| diff 改了公开 API / CLI 参数 / 配置项 / 输出格式 / 数据格式 | **是**（按语义化版本定 major/minor/patch） | 指到具体符号或文件 |
| diff 删除或废弃了对外能力 | **是** | 指到具体符号或文件 |
| 版本承载文件之间已不一致（`consistent=false`），或用户给了目标版本 | **是** | 列出 `distinct_versions` 与目标版本 |
| 仅文档 / 测试 / CI / 构建脚本 / 纯内部重构，无对外行为变化 | 否 | 说明"无对外行为变化" |
| 项目按日程发版（如每月固定），与改动内容无关 | 否（版本门槛不阻塞本次提交） | 说明节奏来源 |
| changelog-only 项目（`CHANGELOG.md` 是唯一版本源） | 按项目约定 | 说明约定出处 |
| 拿不准 | **归"需要 bump"**，在计划门槛里问用户 | 说明不确定点 |

- `consistent=null`（无版本文件，如 Go 模块）的处理见 `release-versioning.md`；Go 项目的版本门槛落到 tag 计划上。
- 判定"需要 bump" → 进入发行版本门槛，按 `release-versioning.md` 执行。
- 判定"不需要 bump" → 跳过该门槛，但**理由必须写进报告**（用户要能看到你为什么没动版本号）。

## 核心文档集（默认；**完整定义只在本节**）
按**顶层普通文件**的**文件名前缀**匹配（目录不算；`README*` 同时覆盖 `README.md`/`README.rst`/`README`）：

`README*`、`CHANGELOG*`、`CHANGES*`、`HISTORY*`、`AGENTS.md`、`CLAUDE.md`、`CONTRIBUTING*`、`LICENSE*`

外加：**被 README 索引的 `docs/**` 文档**（README 里以相对路径/链接指向的 `docs/` 下文件）。

- **项目可覆盖**：仓库有既成的文档布局（`doc/`、`documentation/`、`website/docs/`）或 `CONTRIBUTING` 里写明了文档规范时，按项目实际布局替换默认集；覆盖后必须在报告的"技术细节"里说明用了哪套集合。
- 版本承载文件跟着核心文档集一起核对，清单见 `version-file-inventory.md`（一致性规则见 `release-versioning.md`）。
- 脚本侧的 `core_docs` 字段用的是**更宽的口径**（全部 `docs/**/*.md` 前 50 个，见 `scan-recipes.md`），它是**低精度近似**：可能列出不属于本集合的文档，也可能漏掉 `doc/`、`documentation/` 等非 `docs/` 布局。扫描结果与本集合冲突时，**以本节定义为准**，扫描结果只当提示。

## 门槛通过条件（可判定）
两个提交前门槛的"通过"都**不是"没发现问题"**，而是"该做的事做完了"：

- **文档门槛通过** = 对本次变更集里每一个影响对外行为的改动，都**逐条对照 diff 检查了相关文档段落，并把该段落改到与 diff 一致**；或明确判定"本次无需文档更新"并给出理由（见 `core-docs-sync.md` 的"什么时候不更新文档"）。
  - ❌ **不是**"`core_docs_relevance_scan` 结果为空"。该扫描是低精度提示：`docs_mentioning_changes=[]` 在"文档只写函数名/命令名、不写文件名"的仓库里**恒为空**，而那恰恰是最该补文档的情况；`docs_stale_candidates` 才是"请人工确认"的清单。
  - **未消解的 `［待补充：…］` 占位符 = 未通过**：处置方式（补内容 / 排除出提交 / 列为 PR 阻塞项，三选一）见 `core-docs-sync.md`。
- **版本门槛通过** = 二选一：
  - 已按门槛层判定"需要 bump"，并完成：所有版本承载文件一致 bump（含 lockfile 里的声明）+ 补了可溯源的 CHANGELOG 条目 + 记录了 tag 计划；**或**
  - 已按门槛层判定"不需要 bump"，并在报告里写明理由。
  - `consistent=null` 只算"无从判定"，**不算通过**。

细则：文档门槛见 `core-docs-sync.md`，版本门槛见 `release-versioning.md`。

## 完成合同：收尾判定是四个事实面，不是一个标量

"这次立正做完了吗"必须**逐面**回答。四个面各有状态，**READY 只是四面的汇总结果，不能跳过面直接给标量**：

| 事实面 | 要回答的问题 | 状态取值 |
|---|---|---|
| **工作区** | 未提交改动、未推送提交、未推送分支都处理了吗？ | `verified-current` / `changed-and-verified` / `pending` / `not-applicable` |
| **文档** | 文档门槛过了吗（或已判定"无需更新"并给出理由）？ | 同上 |
| **版本** | 版本门槛过了吗（或已判定"无需 bump"并给出理由）？ | 同上 |
| **远程** | 推送 / PR 状态明确吗（见下"发布终态"）？ | 同上 |

汇总规则：

- 四面全部为 `verified-current` / `changed-and-verified` / `not-applicable` → **READY**。
- 任一面为 `pending` → **NOT READY**，并在报告里列出**差在哪一面**。
- 任一 CRITICAL 阻塞（pull 冲突、凭据缺失、需用户裁定是否 bump、含未消解 `［待补充：…］`）→ **BLOCKED**。

**不要为了凑满四面而编造证据**：纯本地仓库没有远程面 → 如实标 `not-applicable`；没有版本文件 → 版本面同样 `not-applicable`。没有可查的部署标记就没有"远程已验证"，写 `pending`，**不写** `verified-current`。

**为什么用向量而不是一个标量**：一个项目可能文档已同步、版本已对齐、分支还有未推送提交——单一标量只能选一个值，会掩盖"哪一面没闭合"。用户需要知道的是**具体差哪一面**，而不是一句笼统的"还没好"。

## 发布终态：合并 ≠ 部署 ≠ 用户可见

这些状态**互不蕴含**，报告里不得混用：

| 状态 | 什么证据才算 | 不能从什么推出 |
|---|---|---|
| 已提交 | 本地 commit 存在（`HEAD` 可达） | — |
| 已推送 / PR 已开 | 远程 ref 存在 / PR 已创建 | 不能推出已合并 |
| **已合并** | PR `state=merged` + merge commit 在默认分支上可达 | **不能推出已部署**——代码进了默认分支不等于跑起来了 |
| **已部署** | 部署标记 / release 指向目标 commit + 服务在跑 | 不能推出用户已看到（可能有缓存） |
| **用户可见** | 真实入口（页面 / API）返回新版本 | — |

- 立正的职责边界：**一次性的收拾仓库止于"已推送 / PR 已开"；值守循环（`issue-pr-loop.md`）在授权门通过时可以走到"已合并"**。"已部署 / 用户可见"始终不属于本 skill 能验证的范围，除非用户明确要求且项目有可查的部署标记。
- 因此 `has_remote=false`（纯本地）时，远程面只能是 `pending` 或 `not-applicable`，**绝不能写 `verified-current`**。
- 说"已发布"之前先问自己：**我用的证据是哪一格？** 跳格必须有理由，否则按实际所在格如实写（展示形式见 `assets/templates/status-report.md`）。

## issue triage 门（"值得修复和实现的"= 可判定，不是感觉）

一个 issue 进入本轮处理，必须**同时**满足 A、B、C 三组条件；任一组不满足 → 本轮跳过，报告里写明缺哪一条。

**A. 动作意图明确**：labels 至少命中一个——`bug` / `fix` / `enhancement` / `feat` / `feature` / `docs` / `ci` / `refactor` / `perf` / `P0` / `P1` / `P2`；且**未**命中 `wontfix` / `invalid` / `duplicate` / `question` / `stale`。

**B. 内容可执行**（body 非空，且至少含一项）：
- 复现步骤（"steps to reproduce" / "复现" / 命令行片段 / 报错原文）；
- 期望 vs 实际（"expected" / "actual" / "期望" / "应该"）；
- 明确验收标准（"done when" / "验收" / 可勾选清单 / 具体命令应返回什么）。

**C. 没有被别人占着**：`assignees` 为空，或 assignee 就是当前协作的账号。

判定之外的两条倾斜规则：
- **`P0`/`P1` 且 B 组缺失时**：可以先复现再补齐 B（复现成功即视为 B 成立），因为高优先级 bug 的描述不完整是常态。
- **stale 判定**：`updatedAt` 超过 90 天、且 body 不满足 B、且无新评论 → 不处理，报告里列为"待作者补信息"，**不得**直接关（关 issue 另见下方判据）。

## UI / 视觉相关改动的判定（白名单，自动可判）

用途：决定"能否自动合并"（强 UI 一律不能）与"是否必须交截图"。判定**只看 diff 里的路径**，不看提交信息。

**强 UI（必须截图 + 永远禁止自动合并）** —— 命中任一即成立：

| 类别 | 规则 |
|---|---|
| 资产目录 | `assets/**`、`images/**`、`img/**`、`public/**`、`static/**`、`media/**`、`**/assets/**`（任一层出现以上目录名即算） |
| 样式表 | `*.css` `*.scss` `*.sass` `*.less` `*.styl` |
| 页面/模板 | `*.html` `*.htm` `*.hbs` `*.ejs` `*.pug` `*.njk` `*.liquid` |
| 图片/字体/图标 | `*.png` `*.jpg` `*.jpeg` `*.webp` `*.avif` `*.gif` `*.ico` `*.svg` `*.woff` `*.woff2` `*.ttf` `*.otf` |
| 设计源文件 | `*.fig` `*.sketch` `*.ai` `*.psd` `*.xd` `*.afdesign` |
| 视觉规范文档 | 文件名含 `design` / `visual` / `brand` / `logo` / `icon` / `theme` 的 `.md`（例外见下方边界） |

**疑似 UI（禁止自动合并；截图可选，但报告须说明是否看过渲染效果）**：`*.tsx` `*.jsx` `*.vue` `*.svelte` `*.astro`，以及 `templates/**`、`components/**`、`layouts/**`、`styles/**`、`themes/**` 下的任意文件。

**边界**：
- 删掉一个 `assets/` 里的文件也算强 UI（删除同样是视觉变更）。
- **带图文档不算 UI**（已裁定）：`docs/**/*.md` 或任意 `.md` 里新增/修改图片引用 → `ui_touched` 不变，可自动合并。只有"文件名本身是视觉规范"（上表最后一行）才仍按强 UI 处理。
- 纯文档里的**表格/文字排版**改动不算 UI（否则一切 docs 都要截图）；只有"渲染出来才看得见差异"的才算。
- 判定结果必须写进报告（`ui_touched: strong|suspected|none`），否则视为未判定 → 按 `strong` 处理（从严）。

## 合并门（四层，全过才可合并）

顺序固定，**后一层不能替代前一层**：

| 层 | 通过的判据 | 不通过 |
|---|---|---|
| **L1 客观信号** | ① PR 的 CI 检查**全部完成且成功**（`gh pr checks` 无 pending/fail）；② 无 CI 时：本地按 `issue-pr-loop.md` §7 实跑全部检查并记录命令+退出码+计数，且报告明确标注"CI 未跑"；③ `mergeable=MERGEABLE`（无冲突）；④ 分支不落后于默认分支超过 1 个 squash 单位（落后则先更新分支再验证） | 不合并 |
| **L2 内容门** | `assets/templates/pr-review.md` 全部条目通过；`reviewDecision` 不是 `CHANGES_REQUESTED`；无未决评审评论；diff 与 issue 诉求一致；契约四处同步 / 双实现成对 / 断言未放宽 / 文档已同步 / 无 secret | 不合并 |
| **L3 授权门** | 存在授权（`issue-pr-loop.md` §8.1：当前对话明说 > PR 带 `auto-merge` 标签 > 无）；**且** `ui_touched != strong` | 转 `PR READY`，等人工 |
| **L4 动作门** | 合并动作在执行点确认（授权已明确覆盖"合并"这个动作时才可免问；强 UI 永远需要人工） | 停 |

三条铁律：
- ❌ **强 UI 改动永不被自动合并**——授权再明确也不行，必须有截图 + 人工确认。
- ❌ **"检查是绿的"不等于"L1 通过"**：CI 任务未启动（计费/额度/队列）属 `BLOCKED`，不是 `pass`。实测过：job 3 秒红、日志写着 spending limit，那不是代码失败。
- ❌ 不得为凑 L1 把测试跳过、放宽断言或删检查。

## PR / issue 关闭判据（先评论，后关闭）

| 判据（可判定） | 证据要求 |
|---|---|
| **重复** | 现存等价 PR/issue 的编号 + 标题；两者 diff 覆盖同一改动集 |
| **已被默认分支覆盖** | `git diff <default> <head>` 为空，或 `git cherry <default> <head>` 无 `+` 行（squash 合并下 `-` 行即"已等价应用"） |
| **方向冲突** | 引用项目定位文档（`SKILL.md` / `README` / `AGENTS.md`）里的具体条款，说明违反哪条 |
| **不可复现且长期无回应** | 复现尝试记录（命令+输出）；issue `updatedAt` > 90 天且已请求信息 ≥ 1 次无回应 |

- **顺序不可逆**：评论（写清判据与证据）→ 等确认（远程不可逆档位）→ 关闭。
- ❌ 不得关掉"只是暂时修不了"的对象（那是 `BLOCKED`，不是关闭理由）；不得关掉自己刚开的 PR 来"清理现场"。


## 拿不准怎么办
归脏态，在计划门槛里向用户列出不确定点，让用户裁定。不默认假设"应该是干净的"。`null`（没查成）与 `[]`（确实是空）是两件事，报告里必须分开说。
