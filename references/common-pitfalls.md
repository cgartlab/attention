# 常见坑：你"做了但没生效"的那类

> 与 `autonomy-and-safety.md` 的"永远禁止"互补：那是**不许做**，这里是**你以为生效了、其实没有**。
> 第 1–6 条附实测命令与现象（2026-09-30 在本仓库环境实测）；第 7 条是重复违规的处置原则（属流程规则，无实测命令）。
> 立正的巡检发现这类问题时要**说明为什么没生效**，而不是只说"已加入 .gitignore"。

## 1. `.gitignore` 的模式没写前导斜杠 → 匹配到不该匹配的层级

**实测**（仓库内 `deep/nest/vendor/lib.txt` 未被跟踪）：

| `.gitignore` 内容 | `git check-ignore --no-index -q deep/nest/vendor/lib.txt` |
|---|---|
| `vendor/` | **命中**（忽略任意层级的 vendor 目录） |
| `/vendor/` | 不命中（只忽略**仓库根**的 vendor 目录） |

- **影响**：把名字通用的目录写成 `build/`、`vendor/`、`dist/`，会连带忽略子目录里的同名目录——可能把要发布的东西忽略掉，或反过来让本该忽略的深层目录被抓进版本库。
- **建议**：只想忽略根目录时写 `/name/`；确实要全局忽略才用 `name/`。**没有前导斜杠不代表"相对当前目录"**（.gitignore 没有相对当前目录的概念）。
- **判据**：`git check-ignore --no-index -v <path>` 会打印命中的规则行。

## 2. `.gitignore` 对**已跟踪**文件无效

**实测**：文件先提交 → 再写进 `.gitignore` → 再修改，`git status` **仍报** ` M keep.txt`；`git ls-files` 仍列出它。

- **影响**：用户以为"忽略就完事了"，但文件仍会出现在每次 diff 里，也会随提交一起进入后续版本。
- **正解**：`git rm --cached <path>` 解除跟踪（**保留工作区文件**），再配合 `.gitignore` 才是真正的"停止跟踪"。批量目录同理：`git rm -r --cached <dir>`。
- **判据**：`git ls-files --error-unmatch <path>`（exit 0 = 已跟踪）。**不要**只用 `check-ignore` 判断（见下一条）。

## 3. `git check-ignore` 默认会跳过已跟踪路径（调试陷阱）

**实测**：`deep/nest/vendor/lib.txt` 被 `git add` 跟踪后——

| 命令 | 结果 |
|---|---|
| `git check-ignore -q <path>`（默认） | **不命中**（exit 1） |
| `git check-ignore --no-index -q <path>` | 命中（exit 0） |

- **原因**：默认会查索引，已跟踪路径视为"未被忽略"。于是**规则明明生效，却显示没生效**，很容易误改成更激进的规则。
- **用法**：排查**规则本身**用 `--no-index`；判断"这个文件现在会不会被提交"要**叠加跟踪状态**（`git ls-files`）。

## 4. 被忽略的文件 `git add` 会**拒绝**（而非静默跳过）

**实测**：`git add deep/nest/vendor/lib.txt` → exit **1**，报 `The following paths are ignored by one of your .gitignore files`；`git add -f` → exit 0。

- **影响**：在自动化流程里 `git add -A` 之后若期望"文件都在索引里"，被忽略的路径不会在——不要把它们当作"已加入"。
- **变体**：想保留忽略规则但强制纳入个别文件，用 `!` 例外规则或 `git add -f`；两者语义不同（前者长期有效，后者一次性）。

## 5. 判定"忽略"与"跟踪"时，请同时看两个维度

| 维度 | 判据 | 说明 |
|---|---|---|
| 是否被规则忽略 | `git check-ignore --no-index <path>` | 只看规则，不看索引 |
| 是否被跟踪 | `git ls-files --error-unmatch <path>` | 只看索引 |

四个组合都可能出现，**结论完全不同**：
- 忽略 + 未跟踪 → 正常（不会被提交）
- 忽略 + **已跟踪** → 规则没起作用（需 `git rm --cached`）
- 未忽略 + 未跟踪 → 会出现在 `git status` 的 untracked 里
- 未忽略 + 已跟踪 → 正常跟踪
## 6. 删除远程分支不带 lease → 静默丢掉别人的提交

**实测**（本地裸仓库 + 两个 clone 复现）：审计时 `topic` 指向 `A`；在"等你确认"的窗口里另一个人往 `topic` 推了 `B`；此时执行不带 lease 的 `git push origin --delete topic` —— **删除成功，但 `B` 永久丢失**（远程分支连同其中的提交一起没了）。

- **正解**：`git push origin --force-with-lease=<branch>:<sha> --delete <branch>`，`<sha>` 用**审计时记录**的 tip。sha 不匹配时报 `! [rejected] (delete) -> <branch> (stale info)` 并退出 1 —— 这正是我们要的"发现变了就停"。
- **三个陷阱**：
  1. lease 的 refname 必须与分支**完全同名**；写错名字等于没有 lease，删除**照样成功**（实测）。
  2. 用**显式 sha**，不要用裸 `--force-with-lease`（git 文档点名后者 experimental，且会与本地的后台 fetch 打架）。
  3. 删除一个**已不存在**的远程分支是**幂等成功**，不要报成失败。
- **落点**：`branch_cleanup_audit` 为每个远程候选输出 `tip_sha`；删除时照抄这个 sha。

## 7. 同类问题第三次出现 → 散文约束不够，该上机制

**判据**：同一条规则被违反 **3 次**（3 个分支、3 份文档、3 个版本文件、3 次提交）——说明它靠"说"已经管不住了。

- **为什么是 3**：第一次是意外，第二次是巧合，第三次是**结构性缺口**。继续写更多散文只会让规则更长而不更有效。本仓库自己吃过这个亏：`AGENTS.md` 写明"改脚本要成对"，`docs/QUALITY-AUDIT.md` 的 D1–D11 里仍有成对漂移。
- **该做什么**：把这条规则变成**机器可判**的形式，而不是再写一遍：

  | 重复问题的形态 | 换成什么机制 |
  |---|---|
  | 版本文件总是不一致 | 提交前钩子跑 `version_consistency_audit`，不一致就拦 |
  | 文档总是滞后于代码 | CI 跑 `core_docs_relevance_scan` + 人工确认清单 |
  | 提交信息不守规约 | `commitlint`（`commit-msg` 钩子） |
  | 分支命名混乱 | pre-push 钩子校验分支名 |

- **立正的职责边界**：**只建议，不擅自装钩子**。装钩子会改用户的开发流程，属"本地变更需计划批准"，且可能与他们既有的 pre-commit 框架（husky / pre-commit / lefthook）冲突。写进报告的建议里，由用户决定。
- **报告话术**：说"同一类问题这次出现了 N 处，光靠约定可能不够——建议加一条自动检查，要我帮你配吗？"，而不是把同一条建议重复 N 遍。