# 采集脚本配方与 JSON 契约（单一事实源）

> 本文件是 scripts/ 下所有采集脚本的**共享配方**：每个脚本跑哪些 git 命令、输出哪些 JSON 字段与类型，都与本文件一致。PowerShell（.ps1）与 bash（.sh）两套实现都照本文件实现，保证跨 shell 输出**同形 JSON**。脚本仍是黑盒——调用方先 `--help`；本文件供实现者对齐、供模型在无脚本回退时手动照配方采集。
>
> **改契约的规则**：任何字段变更必须同时改三处——本文件、`.sh`、`.ps1`、以及 `evals/script-assertions.json` 的断言。只改一处即为漂移（历史上正是这么坏的）。验证方式：`pwsh -NoProfile -File evals/run_evals.ps1`。

## 通用约定

- 全部**只读**，绝不改仓库（不 commit/push/删分支/开 PR）。
- 入参：`--repo <path>`（可选，默认当前目录）、`--defaultBranch <name>`（可选）、`--help`（打印用法后退出 0）。
  - **`--repo` 必须校验**：路径不存在或不是目录 → 输出 `{"is_git":false,"error":"repo path not found"}` 并退出 0。**绝不静默回退到当前目录**（否则会把别的仓库当目标分析，属静默错误结论）。
  - `version_consistency_audit` 另收 `--target-version <x.y.z>`（用户明示的目标版本）与 `--since-tag <tag>`（提交扫描起点，默认 `git describe --tags --abbrev=0`）。
- 非 git 仓库 → 输出 `{"is_git":false,"error":"not a git repository"}`，退出 0。
- 退出码：`0` = 已产出完整 JSON（含 `is_git=false` 的正常短路）；`2` = 内部错误（此时仍须输出 `{"is_git":false,"error":"<原因>"}`，不得输出半截 JSON）。
- **颜色**：所有 git 调用一律 `-c color.ui=never`。用户全局 `color.ui=always` 会注入 ANSI 转义，使 `--merged` 分支名比对整体失效（静默漏报剪枝候选）。
- **失败可见**：任何 git/gh 子命令失败、跳过或降级，必须记入 `warnings[]` 或把相应字段置 `null`。**禁止**把"没查成"输出成与"确实为空"同形的 `[]`。
- **`warnings[]`**（各脚本均可输出，默认 `[]`）：机器可读短码，至少含 `gh-query-failed`、`remote-unreachable`、`no-remote`、`no-version-files`、`partial-parse`、`head-unborn`、`gh-host-mismatch`、`remote-base-unverified`、`rulesets-unavailable`、`protect-config-unreadable`。

### 路径与缺失语义（两套实现必须逐字一致）

| 规则 | 说明 |
|---|---|
| 路径形态 | JSON 内路径一律**相对仓库根 + 正斜杠**（`src/a.js`、`deep dir/子目录/x.txt`）。唯一例外：`repo_root` 为绝对路径 + 正斜杠（`D:/x/y`）。反斜杠路径视为契约违约 |
| 缺失 | `null` = 采集失败或该信息不可用；`[]` = 确实为空；**不得**用 `""` 表示缺失 |
| 数组 | 去重后**排序**输出（保证跨实现逐字段可比） |
| 字符串 | 不得内嵌裸控制字符（`\r`/`\n`/`\t` 必须转义）；取值处统一剥离行尾 CR |

### 默认分支探测（共用）
`git symbolic-ref --quiet --short refs/remotes/origin/HEAD`（去 `origin/` 前缀）→ `git ls-remote --symref origin HEAD`（剥离 `refs/heads/`）→ 按 `main→master→develop→trunk` 用 `git show-ref --verify --quiet refs/heads/<b>` 逐一试。
结果写入 `default_branch`，来源写入 `default_branch_source`（`origin-head` | `ls-remote` | `local-ref` | `explicit` | `fallback-main` | `unavailable`（`explicit` = 调用方通过 `--defaultBranch` 显式指定））。**探测不到时不得假装是 main**：`default_branch=null` 且 `default_branch_source=unavailable`，由模型按环境探测规则问用户。

### 变更集（version/core_docs 共用）
staged(`git diff --cached --name-only --no-renames -z`) ∪ unstaged(`git diff --name-only --no-renames -z`) ∪ untracked(`git ls-files --others --exclude-standard -z`) ∪（若 `origin/<default>` 存在）`git diff --name-only --no-renames origin/<default>..HEAD`；去重、转正斜杠、排序。
`-z` 输出以 NUL 分隔、无尾换行；读时先 `tr '\0' '\n'`（sh）或 join-split（pwsh）。

---

## 1. git_state_snapshot

**用途**：工作树状态快照。
**git 命令**：
- `git rev-parse --is-inside-work-tree`（非 git 则短路）
- `git rev-parse --show-toplevel` → repo_root
- `git symbolic-ref --quiet --short HEAD` → current_branch（空=detached=true）
- `git rev-parse --short HEAD` → head_short（**无提交的仓库 → null**，并加 `head-unborn` 警告）
- `git remote` → has_remote(bool)；`git remote get-url origin`（无 origin 则第一个 remote）→ remote_host（按 URL 解析出的**主机名**，解析不出则 null）
- `git rev-parse --abbrev-ref --symbolic-full-name '@{u}'` → upstream（等于 `HEAD` 则置 null）
- 有 upstream 时 `git rev-list --left-right --count '@{u}...HEAD'` → behind=第一数, ahead=第二数（无则 null）
- 默认分支探测（通用）
- staged / unstaged / untracked（见"变更集"，untracked 仅计未被 .gitignore 排除者）
- `git stash list` → stash_count（行数）
- recent_changed_files：`count = git rev-list --count --first-parent HEAD`（**必须 `--first-parent`**：不带它时侧分支提交也被计入，而 `HEAD~n` 只沿第一父链，两者不一致会让 `HEAD~n` 不存在）；**`n = min(10, count-1)`**；n>0 则 `git diff --name-only --no-renames "HEAD~n..HEAD"`；**n==0（仅根提交）时**回退 `git show --name-only --format= HEAD`。历史写法 `min(10, count)` 会让提交数 ≤10 或含合并提交的仓库静默变空（审计发现的契约缺陷）
- unpushed_commits：`origin/<default>` 存在 → `git log --oneline origin/<default>..HEAD`；否则有 upstream → `@{u}..HEAD`；**否则 null**。null 有两种语义，必须靠 `has_remote` 区分：`has_remote=false` → **不适用**（没有远程可推，加 `no-remote` 警告）；`has_remote=true` 但取不到可比 ref → **不可判定**。不得输出 `[]`（那会被读成"确实没有未推送提交"）
- **unpushed_branches**：本地分支中 tip 不被任何 `refs/remotes/*` 覆盖者 → `git for-each-ref --format='%(refname:short)' refs/heads` 减去 `git branch -r --contains`/`rev-list --branches --not --remotes` 的结果。**`has_remote=false` 时必须输出 `[]`**：没有远程就没有"未推送分支"这一概念（实测：此前输出 `["main"]`，配合判定条款会把一个完全干净的纯本地仓库判成**脏态**，进而去尝试推送一个不存在的远程）

**JSON**：`{is_git(bool), repo_root(str), has_remote(bool), remote_host(str|null), current_branch(str|null), detached(bool), head_short(str|null), upstream(str|null), ahead(int|null), behind(int|null), default_branch(str|null), default_branch_source(str), staged(str[]), unstaged(str[]), untracked(str[]), stash_count(int), recent_changed_files(str[]), unpushed_commits(str[]|null), unpushed_branches(str[]), warnings(str[])}`

---

## 2. branch_cleanup_audit

**用途**：剪枝候选审计（只列不删）。
**git 命令**：
- 默认分支探测（通用）；取不到 → `default_branch=null` 且 `default_branch_source=unavailable`（**不再默认 main**；无默认分支时合并判定整体跳过并加警告）
- `git symbolic-ref --quiet --short HEAD` → current_branch
- protected = `[main,master,develop,dev,trunk,prod,production,gh-pages,gh-readonly]` ∪ `release/*` 通配 ∪ `{current}` ∪ `{default}` ∪ **`git config --get-all cleanup.protect` 的全部值**，**去重后排序**；字面量 `release/*` 也列入数组（自解释），实际判定同时用通配匹配。实测：`--get-all` 返回多值（`--get` 只回最后一个），故持久化保护名单必须用 `--get-all`；该项为可选增强，读取失败静默忽略（不视为错误）
- **仓库侧保护分支（gh rules，实测纠偏）**：`gh` 可用且宿主为 GitHub 时，对**查询集合**逐个查 `gh api repos/{owner}/{repo}/rules/branches/{branch}`（`--jq 'any(.[]; .type=="deletion")'`），命中删除保护的写入 `protected_from_rulesets(str[])`。
  - **不要用 `GET /rulesets`（列表）**：实测它只回 `id/name/target/enforcement/source/node_id/created_at/updated_at/_links`，**不含 `rules`/`conditions`**，据此判删除保护永远判不出来；`GET /rulesets/{id}` 详情虽含 `rules`，但 `rules/branches/{branch}` 已替你过滤 `enforcement`（只回 active）并展开 ref 匹配（`~DEFAULT_BRANCH`/`~ALL`/通配），更省事更准。`GET /rules/{ref}` **不存在（404）**。
  - **陷阱**：**分支不存在时该端点返回 `[]` + HTTP 200**（不是 404）→ 必须先确认分支存在（`git ls-remote` 权威，不可用时退回 `refs/remotes/origin/<b>`），否则"拼错分支名"会被读成"没有保护"。
  - **权限**：`Metadata (read)` 即可，公开仓库无认证也能查；老端点 `branches/{b}/protection` 不要用（无认证 401、非管理员 404）。`bypass_actors` 只读恒为 null，**不可**作判定依据。
  - **查询集合与上限**：静态名单筛出的本地已合并候选 ∪ 远程已合并候选 ∪ 默认分支，去重排序，**硬上限 100 次调用**。命中删除保护的分支从候选中剔除（"非受保护"按**有效保护**理解）。`local_stale_unmerged_report` 不参与该查询（已知限制：陈旧未合并分支只报告，不作为删除候选）。
  - **失败语义**：非 GitHub 宿主 / 无 gh / 无 remote / 任何一次调用失败 / 超上限 → `protected_from_rulesets=[]` + `rulesets-unavailable` 警告（**非 GitHub 也算"没查成"**，故该警告在非 GitHub 仓库上出现是正常的），绝不整体失败、绝不输出半截 JSON；也**不得**把"查不到"当成"没有保护分支"（`protected` 的静态部分只是下界）。
  - **口径说明**：`protected_from_rulesets` 存**解析后的本地分支名**，模式匹配用 shell glob（`*` 可跨 `/`），比 GitHub 的 `*`/`**` 更宽松 → 只会**多保护**、不会漏保护（刻意保守）。
  - **`cleanup.protect` 读取**：`git config --get-all cleanup.protect`；**exit 1（键不存在）视为正常、静默**；其他非零（真读取失败）→ `protect-config-unreadable` 警告（无法在"只坏这一处"的前提下造 fixture，故该分支仅代码走查覆盖）。
- `git for-each-ref --format='%(refname:short)' refs/heads` → 本地分支
- **本地列表**：`git -c color.ui=never branch --merged <local-default>` 去前缀 `[* ]+` → 已合并名集。**本地合并必须用本地默认分支**（`main`），不能用 `origin/<default>`——本地已合并但尚未推送时用 `origin/<default>` 会把可安全删除的分支漏报（假阴性）；删除本地分支不会丢内容，因为提交已在本地默认分支里
- **远程列表**：`git -c color.ui=never branch -r --merged origin/<default>`。**远程合并必须用 `origin/<default>`**——用本地分支作基准会在"本地已合并、远程尚未收到"时误判为已合并，删远程分支就丢数据
- **基准守卫**：使用 `origin/<default>` 前先 `git rev-parse --verify --quiet refs/remotes/origin/<default>`；不存在则 `remote_base_unverified=true`、远程候选一律为空、并加 `remote-base-unverified` 警告。另：`origin/<default>` 落后于本地默认分支时，远程结论天然保守（宁可不删），但必须在输出里能看出来——故暴露 `local_merge_base` 与 `remote_merge_base` 两个字段
- 每个本地分支：已合并且非受保护 → local_merged_candidates；未合并 → `git log -1 --format='%cI' <b>` 算 age_days（`now - commitdate`，阈值见 judgment-criteria：默认 30 天），超阈值且非受保护且 ≠current → local_stale_unmerged_report `{branch,last_commit,age_days}`
- `git ls-remote origin` → refs/heads/* → name→sha 映射（remote_exists 用）；**失败 → remote_reachable=false + `remote-unreachable` 警告**（远端候选因此不可信，不得当成"没有可剪枝的远程分支"）
- `git for-each-ref --format='%(refname:short)' refs/remotes`（取 origin/*，跳过 origin/HEAD）
- 每个远程分支：`git branch -r --merged origin/<default>` 含 `origin/<short>` 且非受保护 → remote_merged_candidates `{branch,tracking_ref,remote_exists(bool),tip_sha(str|null)}`；`remote_exists` 必须用**精确匹配**（`grep -Fxq` / 哈希表），不得用无锚定子串（`feat` 会误配 `feat-x`）。**`tip_sha`** = 审计时该分支的 tip（`git rev-parse refs/remotes/origin/<short>`）：删除远程分支时**必须**把它传给 `git push origin --force-with-lease=<branch>:<sha> --delete <branch>`，否则确认窗口内他人推送的提交会被静默删掉（实测可复现的数据丢失）

**JSON**：`{is_git(bool), default_branch(str|null), default_branch_source(str), current_branch(str|null), remote_reachable(bool), protected_from_rulesets(str[]), local_merge_base(str|null), remote_merge_base(str|null), remote_base_unverified(bool), protected(str[]), local_merged_candidates(str[]), local_stale_unmerged_report([{branch,last_commit,age_days}]), remote_merged_candidates([{branch,tracking_ref,remote_exists,tip_sha}]), warnings(str[])}`

> 远程剪枝的可判定条件见 `branch-model-and-protection.md`：候选来自 remote-tracking ref，**不能**要求"远端已无对应 ref"（`fetch --prune` 之后恒假）。

---

## 3. version_consistency_audit

**用途**：版本文件一致性 + 发布信号（**不是**"是否涉及 release"的最终判定）。
**git 命令**：变更集（通用）。
**文件池（必须尊重 .gitignore）**：`git ls-files` ∪ `git ls-files --others --exclude-standard`。**不得**用裸目录遍历——那会把 `vendor/`、`.cache/` 等被忽略目录里的清单文件当成版本文件（假"版本不一致"）。硬编码排除目录（`node_modules|.git|target|dist|build|.venv|venv|__pycache__|obj|bin|vendor|third_party|Pods|bower_components`）作为二次防御——**`vendor`/`third_party` 必须在内**：第三方内嵌依赖常未被 `.gitignore` 排除，实测会把 `vendor/sub/Cargo.toml` 当成自有版本文件并报假"不一致"。排除必须按**路径段**判断（不得依赖 `\\` 分隔符，否则 Linux 上全部失效）。

**生态与版本字段**（检测到即纳入；详表见 `references/version-file-inventory.md`）：
- `package.json` → node，**顶层** `.version`（不得取 `dependencies.*.version` 等嵌套同名键）
- `package-lock.json` / `npm-shrinkwrap.json` → node-lock，根 `version` 与 `packages[""].version`
- `Cargo.toml` → rust，`^\s*version\s*=\s*"([^"]+)"`（`[workspace.package]` 亦计）；`Cargo.lock` → rust-lock，`[[package]]` 中 name==根包名者的 version
- `pyproject.toml` → python，`[project].version` 或 `[tool.poetry].version`；`setup.py`/`setup.cfg` → python
- `pom.xml` → jvm，`<version>`；`gradle.properties` → jvm，`^version\s*=\s*(.+)$`；`build.gradle(.kts)` → jvm，`version\s*=\s*['"]([^'"]+)`
- `*.csproj` / `Directory.Build.props` → dotnet，`<Version>`/`<VersionPrefix>`
- `*.gemspec` / `lib/**/version.rb` → ruby；`composer.json` → php；`pubspec.yaml` → dart；`mix.exs` → elixir；`MODULE.bazel` → bazel；`DESCRIPTION` → r；`Chart.yaml` → helm；`*.opam` → ocaml；`Package.swift` → swift
- **`SKILL.md`（Agent Skill 仓库）** → ecosystem `agent-skill`，取 YAML frontmatter 里 `metadata.version`（无则顶层 `version`）。**为什么**：Skill 仓库的真正版本号就在 frontmatter 里，不进清单会让 `version_files=[]`+`consistent=null`，等于巡不到自己的版本（实测本仓库即如此）
- `go.mod` 存在 → go_mod_present=true（go.mod 本身**不含**版本号，标签才是版本源）
- 值一律剥离行尾 CR 后再写入 JSON

- distinct_versions = 去重排序后的版本串集合
- **consistent**：`distinct 数 ≤ 1` → true；`distinct 数 > 1` → false；**版本文件数为 0 → null**（空集"一致"是空洞真值，会让人误以为"版本已核对"，故用 null + `no-version-files` 警告表达"无从判定"）
- **release_signals（新增）**：`[{kind, sample}]`，kind 取值与判定来源：
  - `version-file-touched`：变更集与版本文件有交集（此字段**只覆盖这一条**）
  - `commit-chore-release` / `commit-breaking`（`feat!`/`fix!`）/ `commit-feat` / `commit-fix`：`git log --format='%h %s' <range>` 前缀匹配；range 默认 `$(git describe --tags --abbrev=0)..HEAD`，无 tag 则全部提交，可用 `--since-tag` 覆盖
  - `breaking-footer`：`git log --format='%h %B' <range>` 前 20 行内出现 `BREAKING CHANGE:` / `BREAKING-CHANGE:`
  - `user-intent`：仅当调用方传 `--target-version` 或用户明示发版时由**模型**补写（脚本自身不臆测用户话语）
  - sample 为触发样例（commit 短哈希 + 标题，或文件路径）
- monorepo_mode / packages：检测 `pnpm-workspace.yaml`、`lerna.json`、`nx.json`、`Cargo.toml` 的 `[workspace]`、**或"多于一个 `package.json`"或"多于一个 `pyproject.toml`"**（按类型分别计数，不是合计——多生态单包仓库不算 monorepo）→ `monorepo_mode=true`。`packages` = 包**目录**列表（相对路径、排序）：Cargo workspace 取 `[workspace].members`（支持 `packages/*` 通配展开为实际含 `Cargo.toml` 的目录），npm/pnpm 取含 `package.json` 的包目录
- **Cargo workspace 版本继承（必须识别，不得静默漏掉）**：成员清单里的 `Cargo.toml` 若写 `version.workspace = true` 或 `version = { workspace = true }`，它**没有字面版本**，其版本来自根 `[workspace.package].version`。这类文件进 `inherited_version_files([{file, inherits_from}])`（`inherits_from` = 提供版本的根清单路径），**不计入** `version_files`/`distinct_versions`（否则会凭空多出一个空版本）。实测：不识别时成员完全不可见，`packages` 也为空
- target_version（**新增**）：`--target-version` 的回显（null=未指定）

**JSON**：`{is_git(bool), version_files([{file,ecosystem,version}]), inherited_version_files([{file,inherits_from}]), distinct_versions(str[]), consistent(bool|null), go_mod_present(bool), monorepo_mode(bool), packages(str[]), target_version(str|null), release_signals([{kind,sample}]), release_involved(bool), changed_files(str[]), warnings(str[])}`

> `release_involved` 保留为**兼容字段**，语义收窄为"`release_signals` 含 `version-file-touched`"。是否发行版本门槛的最终判定属模型职责，见 `judgment-criteria.md` 的多层门表格。

---

## 4. core_docs_relevance_scan

**用途**：核心文档与变更的交叉引用扫描（**低精度提示**，不是"文档是否需要更新"的裁决）。
**git 命令**：变更集（通用）。
- core_docs：顶层匹配 `^(README|CHANGELOG|CHANGES|HISTORY|CONTRIBUTING|LICENSE|AGENTS|CLAUDE)` 的**普通文件**（目录不算）；加 `docs/**/*.md`（前 50 个）
- changed_basenames = 变更文件 basename 去重排序
- 每个核心文档：读内容；对每个 changed basename 做**字面匹配（不区分大小写，正则转义）** → `references[]`
- `docs_mentioning_changes`（**原 `docs_needing_update` 更名**）：`[{doc, references[]}]`——**只表示"该文档提到了这些变更文件名"**。它为空**不代表**文档已同步：文档从不引用文件名（只写函数名/命令名）的仓库里它恒为空，而那恰恰是最该补文档的情况
- `docs_stale_candidates`：`exists=true`、未出现在变更集、且未提及任何变更文件的核心文档 → `str[]`。语义为"本次改动没有碰它、它也没提到改动过的文件，请人工确认是否需要更新"。**变更集为空时必须输出 `[]`**：什么都没改就谈不上"陈旧"（实测：此前会把全部核心文档都列出来，等于对着一个干净仓库刷 12 条无意义提示）

**JSON**：`{is_git(bool), core_docs([{file,exists(bool)}]), changed_files(str[]), changed_basenames(str[]), docs_mentioning_changes([{doc,references(str[])}]), docs_stale_candidates(str[]), warnings(str[])}`

> 文档门槛的**通过条件**是"逐条对照 diff 检查相关段落"，不是"扫描结果为空"。见 `core-docs-sync.md`。

---

## 5. next_steps_analysis

**用途**：下一步建议的原始信号采集。
**git 命令**：
- `git -c color.ui=never log --oneline -n 15` → recent_commits
- `git remote -v` → 解析出 remote 主机名：**is_github 判定按主机名**（`github.com` 或其子域），不得对整条 URL 做子串匹配（路径里含 `github.com` 的自建 GitLab 会被误判成 GitHub，进而驱动 `gh pr create`）；`remote_url_masked` = 脱敏后的 URL（`scheme://***@host/path`，去掉 userinfo 中的凭据）
- `gh_authed`：**本地凭据探测**——以 `gh auth token` 的**退出码**为准（它只读本地凭据存储、不联网，确定性）。**不得使用会联网的 `gh auth status` 作为该字段依据**，因为网络抖动/并发繁忙会被写成事实性的"未认证"（违反本节"没查成必须留痕"）。字段仍为 `bool`（本地凭据在 = 已登录），**不是 `bool|null`**；`gh` 不存在或命令不可用 → `gh_authed=false`（沿用现有降级口径）。**网络可达性由 `remote_reachable` / `gh_query_state` 表达，与"是否登录"是两件事**；登录态的偶发网络失败不得改写这两个字段之外的登录结论
- **宿主不匹配该 remote（本地凭据里没有该 host 的 token）→ `gh-host-mismatch` 警告**（同样只读本地，不联网）
- is_github 且 gh_authed → `gh issue list --state open --limit 20`、`gh pr list --state open --limit 20`
  - 查询成功 → 数组（可为 `[]`）
  - 查询失败 → 字段置 **null** 且 `gh_query_state="unavailable"` + `gh-query-failed` 警告（**不得**输出 `[]`，那会被读成"没有开放 issue/PR"这一事实性否定）
  - 不适用（非 GitHub / 未登录）→ 字段 `null`，`gh_query_state="not-applicable"`
  - 成功 → `gh_query_state="ok"`
- todo_fixme：`git grep --untracked -n -E -e 'TODO|FIXME|XXX|HACK' -- . ':(exclude)*.md' ':(exclude)*.markdown' ':(exclude)*.json' ':(exclude)*.rst' ':(exclude)scripts/next_steps_analysis.ps1' ':(exclude)scripts/next_steps_analysis.sh'`（前 30）。pattern 为 `TODO|FIXME|HACK|(^|[^X])XXX([^X]|$)`：**`XXX` 必须排除连续的 X 串**，否则会命中 `mktemp` 模板里的 `XXXXXX`/`XXXXXXXX` 占位符（实测本仓库 8 条命中里有 2 条是这种假阳性）。**`--untracked` 必须放在 pattern 之前**（写成 `git grep -E PAT --untracked` 会被 git 当成 revision，报 `unable to resolve revision`）；排除表写全、不省略；**不排除 `*.txt`**——文本文件里的 TODO 同样是有效信号
- `git for-each-ref --format='%(refname:short)%09%(committerdate:iso-strict)' refs/heads` → branches `[{branch,last_commit}]`
- test_commands：`package.json` scripts 的 test/lint/build/check/typecheck/format → `{name,script}`（script 为**完整命令串**，含转义引号，不得截断）；Makefile 目标 test/lint/build/check → `make <t>`；pyproject.toml 含 pytest/ruff/mypy → 该名；**另外识别"本 skill 自带的测试入口"**：`evals/run_evals.ps1|sh` → `{name:"run_evals"}`、`scripts/smoke_test.ps1|sh` → `{name:"smoke_test"}`（脚本按探测到的 shell 给出对应实现）。**为什么**：采用本 skill 的仓库其真实性测试入口就是这两个（实测本仓库 `test_commands=[]`，"这项目有没有测试"看不见）
- behind_default：`origin/<default>` 存在则 `git rev-list --count origin/<default>..HEAD`；否则 null
- missing_core_docs：顶层**普通文件**名前缀精确匹配 `README|CHANGELOG|LICENSE|AGENTS|CONTRIBUTING`（大小写敏感性两套实现必须一致：统一**区分大小写**，与 git 在 Linux 上的行为对齐），缺失者按该顺序输出

**JSON**：`{is_git(bool), default_branch(str|null), behind_default(int|null), recent_commits(str[]), is_github(bool), remote_url_masked(str|null), gh_authed(bool), gh_query_state(str), open_issues(str[]|null), open_prs(str[]|null), todo_fixme(str[]), branches([{branch,last_commit}]), test_commands([{name,script}]), missing_core_docs(str[]), warnings(str[])}`

---

## 无脚本回退用法（P3）

当 harness 既不能跑 bash 也不能跑 pwsh 脚本（或只让模型直接执行命令）时，按下面步骤手动采集，保证判断流程不变：

1. **跑 git 命令**：按上面每节的"git 命令"清单，用 harness 给的任意 shell 直接执行——git 命令跨平台一致，只有 shell 胶水（数组/JSON 拼装）不同。
2. **组装 JSON**：照对应小节的"JSON"契约拼成同形 JSON（字段名、类型、路径形态、null/[] 语义都照契约；数组去重排序）。
3. **走判断**：拿组装好的 JSON 进 Phase 2 起的判断（干净/脏态分流、剪枝、修复、文档/版本门槛、报告），与脚本路径完全一致。

> 权衡：回退路径靠模型每次正确跑 git + 拼 JSON，失去脚本的黑盒确定性，故仅作兜底——主路径仍是 bash（.sh）或 pwsh（.ps1）脚本。缺 `gh` 时，PR 步骤降级为"PR 就绪 diff + 手动指引"，不硬开。

## 依赖与边界审计（P3）
- **运行时依赖**：仅 `git`（必需，缺则 Phase 0 停止说明）；`gh`（可选，仅 next_steps 与开 PR 用，缺则降级）。不要求 Python/Node/pwsh/bash 作为硬依赖——它们只是某条脚本路径的前置，缺了换路径或走无脚本回退。
- **shell 探测（重要）**：**必须按"能否执行"探测，不能按"文件是否存在"**——`C:\Program Files\Git\bin\bash.exe` 在某些受限沙箱里存在但一启动就 `couldn't create signal pipe` 失败。探测方式：`bash -c 'echo ok'` 看退出码与输出。
- **shell profile 隔离**：pwsh 路径一律 `pwsh -NoProfile`；bash 路径不读 profile。
- **平台假设**：.ps1 用 PowerShell cmdlet（仅 pwsh 路径）；.sh 用 POSIX 工具（find/grep/sed/awk/date/tr），日期经 `epoch_of` 兼容 GNU 与 BSD。两套互不污染。
- **无 jq/python 时的降级**：.sh 对需要真 JSON 解析的字段（如 `package.json` 的 scripts、顶层 version）在缺少解析器时输出 `partial-parse` 警告，并在契约里明示该字段为 best-effort——**不假装与 .ps1 等价**。
