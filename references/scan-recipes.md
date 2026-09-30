# 采集脚本配方与 JSON 契约（单一事实源）

> 本文件是 scripts/ 下所有采集脚本的**共享配方**：每个脚本跑哪些 git 命令、输出哪些 JSON 字段与类型，都与本文件一致。PowerShell（.ps1）与 bash（.sh）两套实现都照本文件实现，保证跨 shell 输出**同形 JSON**。脚本仍是黑盒——调用方先 `--help`；本文件供实现者对齐、供模型在无脚本回退时手动照配方采集。

## 通用约定
- 全部**只读**，绝不改仓库（不 commit/push/删分支/开 PR）。
- 入参：`--repo <path>`（可选，默认当前目录）、`--defaultBranch <name>`（可选）、`--help`（打印用法后退出 0）。
- 非 git 仓库 → 输出 `{"is_git":false,"error":"not a git repository"}`，退出 0。
- **默认分支探测**（共用）：`git symbolic-ref --quiet --short refs/remotes/origin/HEAD` → 去 `origin/` 前缀；失败则按 `main→master→develop→trunk` 用 `git show-ref --verify --quiet refs/heads/<b>` 逐一试。
- **变更集**（version/core_docs 共用）：staged(`git diff --cached --name-only --no-renames -z`) ∪ unstaged(`git diff --name-only --no-renames -z`) ∪ untracked(`git ls-files --others --exclude-standard -z`) ∪（若 `origin/<default>` 存在）`git diff --name-only --no-renames origin/<default>..HEAD`；去重。
- **路径分隔符**：JSON 内路径统一正斜杠（`.ps1` 已做 `\`→`/`；`.sh` 天然 `/`），便于跨平台比对。
- `-z` 输出以 NUL 分隔、无尾换行；读时先 `tr '\0' '\n'`（sh）或 join-split（pwsh）。

## 1. git_state_snapshot
**用途**：工作树状态快照。
**git 命令**：
- `git rev-parse --is-inside-work-tree`（非 git 则短路）
- `git rev-parse --show-toplevel` → repo_root
- `git symbolic-ref --quiet --short HEAD` → current_branch（空=detached=true）
- `git rev-parse --short HEAD` → head_short
- `git rev-parse --abbrev-ref --symbolic-full-name '@{u}'` → upstream（等于 `HEAD` 则置 null）
- 有 upstream 时 `git rev-list --left-right --count '@{u}...HEAD'` → behind=第一数, ahead=第二数（无则 null）
- 默认分支探测（通用）
- staged=`git diff --cached --name-only --no-renames -z`
- unstaged=`git diff --name-only --no-renames -z`
- untracked=`git ls-files --others --exclude-standard -z`
- `git stash list` → stash_count（行数）
- recent_changed_files：n=min(10, `git rev-list --count HEAD`)；n>0 则 `git diff --name-only --no-renames "HEAD~n..HEAD"`
- unpushed_commits：origin/<default> 存在→range=`origin/<default>..HEAD`；否则有 upstream→`@{u}..HEAD`；否则 null。有 range 则 `git log --oneline <range>`
**JSON**：`{is_git(bool), repo_root(str), current_branch(str|null), detached(bool), head_short(str), upstream(str|null), ahead(int|null), behind(int|null), default_branch(str|null), staged(str[]), unstaged(str[]), untracked(str[]), stash_count(int), recent_changed_files(str[]), unpushed_commits(str[])}`

## 2. branch_cleanup_audit
**用途**：剪枝候选审计（只列不删）。
**git 命令**：
- 默认分支探测（通用）；都没有则默认 `main`
- `git symbolic-ref --quiet --short HEAD` → current_branch
- protected = `[main,master,develop,dev,trunk,prod,production,gh-pages,gh-readonly] ∪ {current} ∪ {default}`；且 `release/*` 通配视为受保护
- `git for-each-ref --format='%(refname:short)' refs/heads` → 本地分支
- `git branch --merged <default>` → 去前缀 `[* ]+` → 已合并名集
- 每个本地分支：已合并且非受保护 → local_merged_candidates；未合并 → `git log -1 --format='%cI' <b>` 算 age_days（`now - commitdate`），age>30 且非受保护 且 ≠current → local_stale_unmerged_report `{branch,last_commit,age_days}`
- `git ls-remote origin` → refs/heads/* → name→sha 映射（remote_exists 用）
- `git for-each-ref --format='%(refname:short)' refs/remotes`（取 origin/*，跳过 origin/HEAD）
- 每个远程分支：`git branch -r --merged <default>` 含 `origin/<short>` 且非受保护 → remote_merged_candidates `{branch,tracking_ref,remote_exists(bool)}`
**JSON**：`{is_git(bool), default_branch(str), current_branch(str|null), protected(str[]), local_merged_candidates(str[]), local_stale_unmerged_report([{branch,last_commit,age_days}]), remote_merged_candidates([{branch,tracking_ref,remote_exists}])}`

## 3. version_consistency_audit
**用途**：版本文件一致性 + 是否涉及 release。
**git 命令**：变更集（通用）。
**文件查找**（递归，排除 `node_modules|.git|/target|/dist|/build|.venv|/venv|__pycache__|/obj|/bin`）：
- `package.json` → ecosystem=node，version=JSON `.version`
- `Cargo.toml` → rust，`(?m)^\s*version\s*=\s*"([^"]+)"`
- `pyproject.toml` → python，同上
- `setup.py` → python，`version\s*=\s*"([^"]+)"`
- `pom.xml` → jvm，`<version>([^<]+)</version>`
- `gradle.properties` → jvm，`(?m)^version\s*=\s*(.+)$`
- `*.csproj` → dotnet，`<Version>([^<]+)</Version>` 或 `<PackageVersion>...</PackageVersion>`
- `*.gemspec` → ruby，`\.version\s*=\s*"([^"]+)"`
- `go.mod` 存在 → go_mod_present=true
- distinct_versions=去重后的 version 集；consistent = distinct 数 ≤1
- release_involved：任一版本文件路径与某变更路径后缀匹配（任一向）；或任一变更 basename == 某版本文件 basename
**JSON**：`{is_git(bool), version_files([{file,ecosystem,version}]), distinct_versions(str[]), consistent(bool), go_mod_present(bool), release_involved(bool), changed_files(str[])}`

## 4. core_docs_relevance_scan
**用途**：核心文档是否引用了变更文件。
**git 命令**：变更集（通用）。
- core_docs：顶层匹配 `^(README|CHANGELOG|CHANGES|HISTORY|CONTRIBUTING|LICENSE|AGENTS|CLAUDE)` 的文件；加 `docs/**/*.md`（前 50 个）
- changed_basenames=变更文件 basename 去重
- 每个核心文档：读内容；对每个 changed basename，若内容含该 basename（正则转义后字面匹配）→ references[]；有则 docs_needing_update `{doc,references}`
**JSON**：`{is_git(bool), core_docs([{file,exists(bool)}]), changed_files(str[]), changed_basenames(str[]), docs_needing_update([{doc,references(str[])}])}`

## 5. next_steps_analysis
**用途**：下一步建议的原始信号采集。
**git 命令**：
- `git log --oneline -n 15` → recent_commits
- `git remote -v`；is_github = 含 `github.com`
- `gh` 可用且 `gh auth status` 成功 → gh_authed=true
- is_github 且 gh_authed → `gh issue list --state open --limit 20`、`gh pr list --state open --limit 20`
- todo_fixme：`git grep -n -E 'TODO|FIXME|XXX|HACK' -- . ':(exclude)*.md' ':(exclude)*.markdown' ':(exclude)*.json' ':(exclude)*.txt' ':(exclude)*.rst' ':(exclude)scripts/next_steps_analysis.ps1' ':(exclude)scripts/next_steps_analysis.sh'`（前 30）
- `git for-each-ref --format='%(refname:short)%09%(committerdate:iso-strict)' refs/heads` → branches `[{branch,last_commit}]`
- test_commands：`package.json` scripts 的 test/lint/build/check/typecheck/format → `{name,script}`；Makefile 目标 test/lint/build/check → `make <t>`；pyproject.toml 含 pytest/ruff/mypy → 该名
- behind_default：origin/<default> 存在则 `git rev-list --count origin/<default>..HEAD`
**JSON**：`{is_git(bool), default_branch(str|null), behind_default(int|null), recent_commits(str[]), is_github(bool), gh_authed(bool), open_issues(str[]), open_prs(str[]), todo_fixme(str[]), branches([{branch,last_commit}]), test_commands([{name,script}])}`

## 无脚本回退用法
当 harness 既无 bash 也无 pwsh 脚本执行能力时，模型按本文件每节的"git 命令"直接跑（用 harness 给的任意 shell），照"JSON"小节手动组装同形 JSON，再走 Phase 2 起的判断。仅兜底，非主路径。