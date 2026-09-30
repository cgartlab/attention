# Git 分支清理工具判定策略与安全机制对照报告

> 调研目标：为立正Skill（attention）的 `branch_cleanup_audit` + 剪枝逻辑提供可直接指导实现细节的对照依据。
> 调研方式：`git clone --depth 1` 拉取源码逐行阅读；对 Git 层语义（squash/rebase 合并后 `--merged` 是否失效、stale local main 是否会误判远程分支）做了 3 组可复现实验。
> 关键结论前置：**立正当前的"已完全合并入默认分支"判定是安全的（永不误删未合并工作），但不完整（漏判 squash/rebase 合并）；远程侧存在一个真实的数据丢失风险（用本地 main 而非 origin/main 判定），必须修。**

---

## 0. 调研对象清单

| # | 工具 | 语言 | 依赖 | 规模 | 定位 |
|---|---|---|---|---|---|
| 1 | [nkt/git-cleanup](https://github.com/nkt/git-cleanup) | Rust | git2 + git CLI | ~4000 行 | 最完备：merged/squashed/gone/abandoned 四分类 |
| 2 | [hartwork/git-delete-merged-branches](https://github.com/hartwork/git-delete-merged-branches) | Python | colorama | ~1500 行 | ★916，最高效的 squash 检测（三级 effort） |
| 3 | [intruderfr/git-stale-branch-cleaner](https://github.com/intruderfr/git-stale-branch-cleaner) | Python | 零依赖 | ~530 行 | 陈旧 + 已合并，纯函数核心 |
| 4 | [bobfromarcher/gitsweep](https://github.com/bobfromarcher/gitsweep) | JS | 零依赖 | 177 行单文件 | 极简：merged 或 upstream-gone |
| 5 | [aesteve-rh/git-prune-merged](https://github.com/aesteve-rh/git-prune-merged) | Python | GitPython/PyGithub | ~450 行 | **基于 GitHub PR SHA 匹配**，与 git 历史无关 |
| 6 | [abey/clean-git](https://github.com/abey/clean-git) | Go | yaml.v3 | ~1300 行 | 配置驱动（正则保护/包含），陈旧+已合并双重门槛 |
| 7 | [osolmaz/herdr-branch-cleanup](https://github.com/osolmaz/herdr-branch-cleanup) | Rust | serde_json | ~4000 行 | herdr 终端插件，`gh pr list` + 远程探测，只 checkout 不删 |
| 8 | [weirdgiraffe/git-cleanup-branches](https://github.com/weirdgiraffe/git-cleanup-branches) | Python | 零依赖 | 130 行 | 最简陋的参照物 |
| 9 | GitHub Actions 常见 snippet | JS/YAML | actions/github-script | — | 官方生态的标准做法 |

---

## 1. 逐个工具卡片

### 1.1 nkt/git-cleanup（Rust）— 本次调研的技术标杆

**语言/依赖**：Rust；`git2` 库做图操作，同时 spawn `git` CLI 做 `patch-id`/`diff-tree`/`log`（因为 git2 没有 patch-id）。

**判定算法**（`src/git.rs`）——**三阶段流水线**：

- **Phase 1 合并（merged）**：一次 `git branch --format=%(refname:short) --merged <main>` 拿到全量集合（`batch_merged()`，line 385–405），失败才回退到逐分支 `repo.graph_descendant_of(main_oid, oid)`（line 249–254）。这是把 O(N) 次调用压成 1 次。
- **Phase 1 gone**：`upstream_status()`（line 644–670）取 `branch_upstream_name`，再 `repo.find_reference(up)`——ref 不存在即 `UpstreamState::Gone`。
- **Phase 2 squashed（line 407–552）**——**核心创新，也是本次调研最想吸收的部分**：
  1. 对每个未分类分支取 `merge_base(main, tip)`；若 `merge-base == tip` 跳过；若 `base_tree.id() == tip_tree.id()`（空 diff）跳过（line 446–451）。
  2. 用 `git diff-tree -p <mb> <tip> | git patch-id --stable` 算出**分支整体 diff 的 patch-id**（`cli_diff_patchid()`，line 614–638）。注意是"整段 range 当一个 patch"，不是逐 commit。
  3. 用 `git log --first-parent --format='commit %H' -p <oldest_mb>..<main> | git patch-id --stable` 一次性建 patch-id → commit 映射（`cli_main_patchids()`，line 564–609），`--squash-scan-limit`（默认 10000，0=不限）封顶扫描深度。
  4. patch-id 命中 → 分类为 `Squashed`，detail 里带命中的 main 侧 commit。
  5. **fallback tip**：若本地 tip 是 remote tip 的祖先（`graph_descendant_of(fb, info.oid)`），还会额外拿 remote tip 试一次（`fallback_tip()` line 672–681；job 生成 line 422–433）。这解决"本地没更新但远程分支已被 squash 合并"的场景。
  6. git CLI 不可用时回退 libgit2 revwalk 实现（`check_squashed()` line 699–759），带 `HashMap` 记忆化。
- **Phase 3 abandoned**：`age_days >= abandoned_days`（默认 90），**opt-in**（`--abandoned`），因为它可能含未合并工作。对 Gone/Abandoned 类还算 `graph_ahead_behind` 报出"N 个未合并提交"（line 331–351）。

**squash/rebase 处理**：patch-id 方案对两者都有效（见 §3 实验 2、3 的实测数据）。

**gone 检测**：默认先 `git fetch --prune <remote>`（`fetch_prune()` line 168–177），`--no-fetch` 可跳过。

**dry-run**：`--list`（只读扫描，绝不 prompt 或删除）、`--json`（机器可读，隐含 `--list`）。`--force`/`-f` 全删不 prompt，`--yes`/`-y` 跳过多选器但仍确认。

**受保护名单**（line 61–92）：
```rust
pub const PROTECTED: [&str; 5] = ["main", "master", "develop", "trunk", "HEAD"];
```
叠加 `git config cleanup.protect`（多值 + 逗号分隔都支持，line 69–84）+ 运行时 `--protect`（可重复）。

**删除前的额外守卫**（`delete_branches()` line 761–820）：
- 当前 HEAD 分支 → 拒绝
- **被任何 worktree 检出的分支** → 拒绝（`list_worktree_branches()` line 876–882）
- `delete_one()` 用 git2 `branch.delete()`，不 force
- worktree 侧用 `git worktree remove`（**不带 `--force`**，line 979–981，注释明说"git 自己会拒绝 dirty/locked worktree 作为第二道防线"）

**默认分支探测**（`detect_main()` line 120–150）：显式 `--main` → `refs/remotes/<remote>/HEAD` symbolic target → `main`/`master`/`trunk`/`develop` 兜底。

**输出**：交互式 TUI 多选（`src/ui.rs`）或 `--json`。退出码 0/1/2 三态。

**亮点小结**：patch-id 检测（正确性最高）+ 三阶段分批（性能）+ worktree 感知 + 多层守卫 + git config 持久化保护名单。

---

### 1.2 hartwork/git-delete-merged-branches（Python，★916）— squash 检测的另一种解法

**语言/依赖**：Python 3；只有 `colorama`。**不依赖 PyGithub**，全部走 git CLI。

**判定算法**（`_engine.py` + `_git.py`）——**三级 effort 递进**（`--effort 1|2|3`，默认 2，`_cli.py` line 80–94）：

- **Level 1**：仅 `git branch --merged <target>`（`_git.py` `find_merged_local_branches_for` line 199–203）。远程用 `--remote --list <remote>/*` + `--merged <remote>/<branch>`（line 202–203）。
- **Level 2（默认）**：对未被 level 1 覆盖的分支用 `git cherry <target> <topic>`（`_engine.py` line 248–270）；所有输出行以 `-` 开头即"defacto merged"。**这只能捕捉 rebase 合并**（实测见 §3 实验 3）。
- **Level 3**：**临时 squash 副本技巧**（`_has_ben_squash_merged_into()` line 224–246，`_git.py` `commit_tree()` line 300–311）：
  ```
  git commit-tree -m "Squash-merge <topic>" -p <merge-base> <topic>^{tree}
  ```
  造一个**只有一个 commit、但包含 topic 相对 merge-base 的全部 diff** 的合成提交，再对它跑 `git cherry <target> <synthetic>`——因为 squash 合并后 main 上的那个 commit 与这个合成提交 patch-id 相同，cherry 会报 `-`。
  - **两个守卫**：detached HEAD（line 276–280）或未提交改动（line 283–287）时直接跳过 level-3 检查（因为 `commit-tree` 会改对象库）。
  - **只有当 `cherry_lines` 行数 > 1 才进入 squash 候选**（line 266–267）。
- **多目标分支**（line 208–220）：`required_target_branches` 可配多个，用 `reduce(and_, ...)` 做**集合交集**——分支必须合并进**全部**目标才算 merged。对 `main`+`develop` 双集成线仓库非常实用。

**squash/rebase**：三级递进，实测有效（§3 实验 2/3）。

**gone 检测**：无独立 gone 类。但有两个相关机制：
- `refresh_remotes()`（line 424–439）：确认后跑 `git remote update --prune <remote>`。
- `detect_stale_remotes()`（line 441–479）：对每个 required target 分支检查 `has_unpushed_commits_on`，发现"本地领先远程"就**主动警告**（因为会让远程侧 merged 检测失真）。这是很成熟的风险提示。

**dry-run**：`--dry-run`/`-n`。实现很干净：`_wrap_subprocess()`（`_git.py` line 53–62）按 `is_write` 标志决定是真跑还是返回 `pretend_result`。注意 `commit-tree` 被标为 `is_write=False`（line 304–308 注释解释了原因：不切分支、不动 ref），所以 dry-run 下仍会真创建合成 commit——这是**有意为之**的副作用。

**受保护名单**：**完全配置驱动，无硬编码默认**。首次运行进入交互式三步配置（`_configure()` line 153–160），写进 git config：
- `branch.<name>.dmb-required`（必须合并进的目标）
- `branch.<name>.dmb-excluded`（永不删）
- `remote.<name>.dmb-enabled`（启用远程删除的 remote）
- `delete-merged-branches.configured=5.0.0+`
运行时可加 `--exclude`、`--include-regex`（Python `re` 语法，多模式取交集，line 122–135）、`--branch`、`--remote`。

**远程删除**（`_git.py` line 216–235）：
```python
git push --delete --force-with-lease <remote> refs/heads/<branch>
```
**用 `--force-with-lease`**——防止在他人刚推了新提交时把它删掉。这是本次调研看到的唯一用这个 flag 的工具。

**确认**：每批删除前整批确认（`_confirmation.confirmed`）；本地先 `-d` 删 truly merged，defacto merged 用 `--force`（line 380–387）。

**其他亮点**：`refresh_target_branches()`（line 481–529）会 checkout 目标分支跑 `git pull --ff-only`，有 detached HEAD / 未提交改动守卫，finally 里保证切回原分支。

---

### 1.3 intruderfr/git-stale-branch-cleaner（Python）— 最简洁的"陈旧+已合并"实现

**语言/依赖**：Python；**零第三方依赖**（`subprocess` 调 git）。

**判定算法**（`git_stale_cleaner/core.py`）：
- 采集：`git for-each-ref --format=%(refname:short)%(committerdate:iso-strict)%(authorname)%(subject)` 一次拿全（line 121–127），注释说明"避免解析 `git branch -v` 的混乱输出"。
- merged：`git branch --merged <base>`（`_merged_branches()` line 89–107），**手工过滤三种噪声行**：`*` 前缀、`(HEAD detached at ...)`、`-> ` 符号引用（line 101–106）。
- **陈旧**：`committerdate` 距今 `>= threshold_days`（默认 90，line 52–54）。注意用 `committerdate` 而非 `authordate`——更贴近"最后被提交/推送"的时间。
- 分类（`classify_branches()` line 172–207）：deletable 需同时满足
  1. 不是当前 checkout 的分支
  2. 不受保护（除非 `--include-protected`）
  3. 陈旧（超阈值）
  4. 若 `--require-merged`，还必须已合并

**squash/rebase**：**完全不处理**。

**gone**：**无**。

**dry-run**：**默认就是只读报告**；必须传 `--delete` 才真删（`__main__.py` line 240–247）。这个默认值选择比 gitsweep 更安全。

**受保护名单**（line 16–18）：
```python
PROTECTED_BRANCHES = frozenset({"main", "master", "develop", "dev", "trunk", "production", "release"})
```
另外 base 分支自身也被标 protected（line 167–168，"不要把 merge base 本身当成合并进它自己的分支删除"）。

**删除**（line 210–237）：`git branch -d`，`--force` 才 `-D`；远程 `git push <remote> --delete <short_name>`；**受保护分支删除会抛 `PermissionError` 拒绝**（line 223–226）。

**输出**：ANSI 表格（TTY 才着色）或 `--json`。有 `tests/` 目录，核心是纯函数便于测试。

**亮点**：`require_merged` 把"陈旧"和"已合并"解耦成两个正交开关，用户可选"只删陈旧"或"只删已合并"或"两者都要"。

---

### 1.4 bobfromarcher/gitsweep（JS）— 极简参照

**语言/依赖**：Node.js；**零依赖**（只用 `readline`/`path`/`child_process`）。

**判定算法**（`bin/gitsweep.js`）：
- 采集：`git for-each-ref refs/heads --format=%(refname:short)\x1f%(upstream:track)\x1f%(committerdate:unix)` 一次拿全（line 74–77）。
- **gone**：`%(upstream:track)` 字段含 `gone` 子串即上游已删（line 48、64）——这是 `git for-each-ref` 的隐藏宝藏字段。
- merged：`git branch --merged <base> --format=%(refname:short)`（line 80–83）。
- 分类（`classify()` line 55–69）：当前分支/base/受保护 → kept；merged **或** gone → sweep。

**squash/rebase**：不处理。

**dry-run**：默认只列出；`--prune` 才删（line 160–163）；`--force` 跳过确认。

**受保护名单**（line 16）：`new Set(['main', 'master', 'develop', 'dev', 'release', 'HEAD'])`。

**默认分支探测**（line 29–39）：`git symbolic-ref --short refs/remotes/origin/HEAD` → `main`/`master` 兜底 → `'main'`。

**删除**（line 88–90、169）：merged 用 `git branch -d`；**gone 用 `-D`**（`force: o.force || b.gone`）——因为 gone 分支的 `-d` 通常会失败（上游没了、无法证明合并）。

**输出**：彩色终端或 `--json`。

**亮点**：`%(upstream:track)` 的 gone 检测零成本；"merged 用 -d、gone 用 -D"的分支策略是合理默认。

---

### 1.5 aesteve-rh/git-prune-merged（Python）— 完全不同的范式：PR SHA 匹配

**语言/依赖**：Python；`GitPython` + `PyGithub` + `click` + `PyYAML` + `python-dateutil`。

**判定算法**（`src/list.py` line 70–81、`src/prune.py` line 33–63）——**完全不看 git 历史，只看 GitHub PR 元数据 + SHA 精确匹配**：
- 用 `gh.search_issues(state='closed', is='merged', author=<当前用户>, repo=<配置>, type='pr')` 拉所有已合并 PR。
- **本地**：遍历 `repo.heads`，`head.commit.hexsha == preq.head.sha` 即匹配。
- **远程**：`repo.rev_parse(f'origin/{preq.head.ref}')`，其 SHA == `preq.head.sha` 即匹配。
- `--months N` 只处理 N 个月前的 PR（`list.py` line 77–79，用 `relativedelta`）。

**squash/rebase 处理**：**天然正确**。GitHub 自己知道 PR 是 merged，且用 `head.sha` 精确匹配分支尖端——不管 squash 还是 rebase，只要分支 tip 仍等于那个 PR 的 head commit，就删。这是**可靠性最高**的判定方式。但代价：
- 强依赖 GitHub + PyGithub + token
- 只处理**当前用户名下**的 PR（`author` 过滤），别人的分支不动
- 需要仓库写配置（token/user/repo）

**gone**：无。

**dry-run**：`--dry-run`（`prune.py` line 46–47）。

**受保护名单**：**完全没有**。任何 SHA 匹配的分支都会被删，**包括 main**。这是这个工具最明显的坑。

**确认**：交互式逐条 `_prompt_confirmation()`（line 17–24）或 `--yes`。

**删除**：本地用 GitPython `Reference.delete(repo, head.path)`（line 70）；远程用 `repo.remote().push(refspec=(f":{preq.head.ref}"))`（line 47）。

**亮点**：证明了"完全绕开 git 历史判定、改用远端权威状态"是可行的另一条路。立正可以考虑把 `gh pr list --state merged` 作为一个**可选增强信号**（见 §5）。

---

### 1.6 abey/clean-git（Go）— 配置驱动 + 双重门槛

**语言/依赖**：Go；`yaml.v3`。

**判定算法**（`internal/git/client.go` + `service.go`）：
- `git branch --merged <base>`（client.go line 48–65），**同时**再查 `origin/<base>` 的远程分支并**合并去重**（service.go line 63–98）。
- **陈旧门槛**：`time.Since(branch.LastCommitAt) < cfg.MaxAge` 则**跳过**（`main.go` line 181–187）——**必须又陈旧又已合并才删**。默认 `MaxAge = 30 天`。这是比"只删已合并"更保守的双重保险。
- `HasUnpushedCommits`：`git rev-list --count <branch>@{upstream}..<branch>`（client.go line 114–127），无 upstream 时视为 false。

**squash/rebase**：不处理。

**gone**：无直接检测（但会用 `HasUnpushedCommits` 标记）。

**dry-run**：`--dry-run` 全局开关（line 267–276）。

**受保护名单**（`internal/config/config.go` line 26–32）——**用正则而非名单**：
```go
func DefaultConfig() *Config {
    return &Config{
        BaseBranches:   []string{"main", "master", "develop"},
        MaxAge:         720 * time.Hour * 24, // 30 days
        ProtectedRegex: []string{"release/*", "hotfix/*"},
        IncludeRegex:   []string{".*"},
    }
}
```
`IsProtectedBranch()` 用 `regexp.MatchString`（service.go line 173–184）。`IncludeRegex` 是白名单（默认 `.*` 全通过）。

**删除**（client.go line 94–104）：
```go
func (c *defaultGitClient) deleteLocalBranch(branchName string) error {
    _, err := c.run("branch", "-d", branchName)
    if err != nil {
        _, forceErr := c.run("branch", "-D", branchName)  // ⚠️ 回退到 -D
        if forceErr != nil { return ... }
    }
    return nil
}
```
**⚠️ 这是个隐患**：`-d` 失败往往正是因为分支未合并，回退到 `-D` 就把这道保护绕过了。远程删除用 `git push <remote> --delete`（line 106–112），**无 `--force-with-lease`**。

**亮点**：`MaxAge` + `IncludeRegex` + `ProtectedRegex` 三轴配置，适合大型多分支仓库。

---

### 1.7 osolmaz/herdr-branch-cleanup（Rust）— 只 checkout 不删，安全模型最讲究

**语言/依赖**：Rust；`serde_json`。是 **herdr**（tmux-like 多 agent 终端）的插件，不是独立 CLI。

**判定算法**（`src/gitio.rs` + `src/core.rs`）——**完全基于 gh CLI + 远程探测**：
- 已合并：`gh pr list --head <branch> --state merged --json headRefOid --limit 1`（gitio.rs line 143–162）。
- 远程探测：`git ls-remote --symref origin HEAD refs/heads/<branch>`（line 115–141）一次拿到 **branch 是否存在 + 权威 default branch**。
- Fate 三态：`Merged`（有 merged PR 且 `headRefOid` 非空）/ `Deleted`（`branch_exists=false`）/ `Alive`。

**关键安全判断**（`core.rs` `has_unpushed_work()` line 102–112）——**这是本次调研最精彩的一段**：
```rust
/// True when the local tip may hold commits GitHub never saw.
///
/// A squash merge rewrites history, so `git branch --merged` lies; the
/// reliable check is whether the local tip is exactly the commit the remote
/// last knew about (the merged PR head, or the last fetched remote ref).
pub fn has_unpushed_work(local: &LocalFacts, remote: &RemoteFacts, fate: Fate) -> bool {
    if fate == Fate::Merged {
        return local.tip_sha != remote.merged_pr_head_sha;
    }
    remote.last_known_remote_sha.is_empty() || local.tip_sha != remote.last_known_remote_sha
}
```
它**直接在源码注释里点破了 `git branch --merged` 在 squash merge 下会说谎**，并给出替代方案：**用 SHA 精确比对本地 tip 与远端最后已知的 commit**。

**额外 hold 守卫**（`hold_reason()` line 115–135）：无法确定远程默认分支 / **linked worktree**（"分支是它的身份"）/ 有 agent 正在工作 / worktree 有未提交改动 / 本地有未推送工作。

**目标分支选择**（`sweep.rs` line 85–93）：
```rust
// The checkout target is the remote's authoritative default branch; the
// local origin/HEAD guess in `local.default_branch` can be stale.
```
它**用远程探测到的 default branch，而不是本地 `origin/HEAD` symbolic ref**。并且有一个专门的回归测试 `stale_local_origin_head_never_picks_checkout_target`（sweep.rs line 347–364）覆盖这个坑——**立正的默认分支探测顺序和这个一致，值得肯定**。

**默认分支探测**（gitio.rs line 28–61）：`git symbolic-ref --short refs/remotes/origin/HEAD` → 失败则 `git ls-remote --symref origin HEAD`（问远端，不问本地）。

**动作**：只 `git checkout <default>` + `git pull --ff-only`，**不删分支**。

**dry-run / notify-only**：两种模式（`Settings` line 26–30）。

**亮点**：状态机式决策（Fate × hold_reason → ActionKind），纯函数便于测试；对"本地 symbolic ref 过期"这个坑有回归测试。

---

### 1.8 weirdgiraffe/git-cleanup-branches（Python）— 反面参照

**判定**：三个来源手工合并
- prune：`git remote prune <remote> --dry-run` 解析 `[would prune]`（line 32–39）
- merged：`git branch --merged`（**不带 base，默认当前分支**，line 41–48）
- vv：`git branch -vv` 正则解析本地分支 + 远程跟踪（line 23–30）

**删除**：**全部用 `git branch -D`**（line 118）——**绕过 `-d` 保护**。

**受保护名单**：**无**（只靠"当前分支不在 `--merged` 输出里"间接保护）。

**确认**：逐条 y/n + 总确认。

**价值**：它展示了**不该做什么**：不带 base 的 `--merged`、无条件 `-D`、无保护名单。立正在这三点上都做对了。

---

### 1.9 GitHub Actions 常见 snippet（actions/github-script 范式）

典型模式（生态中广泛出现，如 AnandChowdhary/delete-merged-action、mheap/github-action-delete-branch 及各类 `.github/workflows`）：
```yaml
- uses: actions/github-script@v7
  with:
    script: |
      const { data: prs } = await github.rest.pulls.list({
        ...context.repo, state: 'closed', per_page: 100
      });
      for (const pr of prs.filter(p => p.merged_at)) {
        await github.rest.repos.deleteBranch({
          ...context.repo, branch: pr.head.ref,
        });
      }
```
**常见坑**（本次调研反复看到）：
1. 未排除默认分支 / `HEAD` ref
2. `pulls.list` 不分页，超过 100 个 PR 会漏
3. 无 dry-run，`workflow_dispatch` 一按就删
4. 用 `github.head_ref` 而非 `pr.head.ref`，会删错分支
5. 无 `protected_branches` 检查——`deleteBranch` API 对受保护分支会返回 403，但脚本没处理错误

**官方相关能力**：
- GitHub 现在支持在 **Rulesets 里配置 "Delete branch" 规则**，并在 PR 合并后**自动删除源分支**（`auto_delete_branches`，PR 模板/仓库设置 `Settings → General → Pull requests → Automatically delete head branches`）。**这是最干净的方案——交给 GitHub 自己删，工具只补漏。**
- `deleteBranch` REST API：`DELETE /repos/{owner}/{repo}/branches/{branch}`，对受保护分支返回 403。

---

## 2. 策略对照表

| 工具 | 合并判定算法 | squash/rebase 处理 | gone 检测 | dry-run | 受保护名单 | 默认分支探测 | 远程删除确认 | 陈旧分支处理 | 输出格式 |
|---|---|---|---|---|---|---|---|---|---|
| **立正 (attention)** | `git branch --merged <DEFAULT>`（本地 & 远程，**对比本地 main**） | ❌ 不处理（漏判） | ✅ `git ls-remote origin` 直接比对真实存在性 | ✅ 只读 audit，删需最终确认 | ✅ 硬编码 10 名 + `release/*` + 当前分支 + DEFAULT | gh repo view → `origin/HEAD` → main/master/develop/trunk | ✅ 需最终确认 | ✅ **只报告不删**（30 天） | ✅ JSON |
| **nkt/git-cleanup** | 一次 `git branch --merged`，回退 libgit2 `graph_descendant_of` | ✅ **patch-id 全量比对**（+ fallback remote tip + 10000 commit 扫描上限） | ✅ `fetch --prune` + upstream ref 存在性 | ✅ `--list`/`--json` 只读 | ✅ 5 名 + `git config cleanup.protect` 多值 + `--protect` | `origin/HEAD` → main/master/trunk/develop | ✅ 交互 TUI 多选 | ✅ `--abandoned` opt-in（默认 90 天）+ ahead 计数 | TUI / JSON |
| **hartwork/git-delete-merged-branches** | `git branch --merged` → `git cherry`（L2）→ 合成 squash commit + `git cherry`（L3） | ✅✅ **三级递进**，L2 抓 rebase、L3 抓 squash | ⚠️ 无 gone 类；`remote update --prune` + 主动警告未推送 | ✅ `--dry-run` 按 `is_write` 全局短路 | ✅ **纯 git config 驱动**（dmb-excluded/required/enabled），`--exclude`/`--include-regex` | 配置驱动（required branches 交互选） | ✅ 批量确认；`--force-with-lease` | ❌ 不处理陈旧 | 彩色终端 |
| **intruderfr/git-stale-branch-cleaner** | `git branch --merged <base>` | ❌ 不处理 | ❌ 无 | ✅ **默认只读**，`--delete` 才删 | ✅ 7 名 frozenset + base 自身 | CLI `-b`（默认 main） | ✅ `--yes` 跳过，否则 prompt | ✅ `committerdate` ≥ 90 天；`--require-merged` 可与陈旧解耦 | ANSI 表 / JSON |
| **bobfromarcher/gitsweep** | `git branch --merged <base>` | ❌ 不处理 | ✅ `%(upstream:track)` 含 gone | ✅ 默认只列出，`--prune` 才删 | ✅ 6 名 Set | `origin/HEAD` → main/master → 'main' | ✅ prompt，`--force` 跳过 | ❌ 不处理（有 age 显示但不参与判定） | 彩色 / JSON |
| **aesteve-rh/git-prune-merged** | **GitHub PR SHA 精确匹配**（`head.sha == branch tip`） | ✅✅ **天然正确**（与 git 历史无关） | ❌ 无 | ✅ `--dry-run` | ❌ **完全没有**（会删 main！） | 不涉及 | ✅ 逐条 prompt | ❌ `--months` 限制 PR 年龄 | 日志 |
| **abey/clean-git** | `git branch --merged` 本地+远程去重 | ❌ 不处理 | ⚠️ 无；有 `HasUnpushedCommits` 标记 | ✅ `--dry-run` | ✅ **正则**：`release/*` `hotfix/*` + `IncludeRegex` 白名单 + `MaxAge` 30 天 | 配置 `BaseBranches`（main/master/develop） | ⚠️ 无逐条确认 | ✅ 陈旧+已合并**双重门槛** | 彩色终端 |
| **osolmaz/herdr-branch-cleanup** | **`gh pr list --state merged` + `ls-remote` 探测** | ✅✅ **SHA 精确比对**（`tip_sha == merged_pr_head_sha`） | ✅ `branch_exists=false` → Deleted | ✅ dry-run / notify-only | ⚠️ 靠本地分支==默认分支跳过；无名单 | `origin/HEAD` → **问远端 `ls-remote --symref`** | N/A（不删分支，只 checkout） | ❌ 不处理 | JSON 状态文件 |
| **weirdgiraffe/git-cleanup-branches** | `git branch --merged`（**无 base**） | ❌ 不处理 | ✅ `remote prune --dry-run` 解析 | ⚠️ 无（逐条 y/n 是唯一保险） | ❌ 无 | 当前分支 | ⚠️ 逐条 y/n + 总确认 | ❌ 无 | 纯文本 |
| **GitHub Actions snippet** | `pulls.list` + `merged_at` | ✅✅ 天然正确（远端权威） | N/A | ⚠️ 多数没有 | ⚠️ 多数没检查 | `github.ref` | ⚠️ 直接 DELETE API | ❌ 无 | GitHub 日志 |

---

## 3. 立正规则的正确性核查（本次调研最有价值的部分）

立正用 `git branch --merged <DEFAULT>` 判定"已完全合并"。**结论：判定是 sound（安全）但 incomplete（不完整），且远程侧有一个真实的数据丢失风险。** 以下全部用真实 git 仓库实验验证（git 2.55.0，`D:\2-Area` 环境下可复现）。

### 3.1 三种合并方式下 `--merged` 的真实行为

实验脚本：`$env:TEMP\exp.ps1`（已实测，以下为真实输出）

```
=== CASE 1: FAST-FORWARD MERGE ===
  --merged => [feature]
  is-ancestor feature main exit = 0
  feature tip == main tip? True

=== CASE 2: SQUASH MERGE ===
  --merged => [feature]          ← feat2 未被列出！
  is-ancestor feat2 main exit = 1  ← 明确失败
  tree(feat2) == tree(main)? True  ← 但内容完全相同
  git cherry main feat2 => [+ ... + ...]  ← 两个 '+'，git cherry 也识别不出
  patch-id(feat2 range)            : 97aa77049202e7bb29127825334394277986d80a
  patch-id(main since mb, 1st-pare):
      97aa77049202e7bb29127825334394277986d80a 2fa606389a5d5843d11b231522fe8da9fe0e43c2  ← 命中！

=== CASE 3: REBASE MERGE (main advanced first) ===
  --merged => [feat4, feature]     ← 因为 feat4 的 ref 已被 rebase 更新，指向新提交
  is-ancestor feat4orig main exit = 1  ← 但 pre-rebase 的 feat4 不是祖先
  git cherry main feat4orig => [- ...]  ← '-' 前缀，git cherry 能识别 rebase 合并！
  patch-id(feat4orig range)          : 92fd9d0c1a05695d79602ac309aa1aa8f8920804
  patch-id(main since mb, 1st-pare):
      92fd9d0c1a05695d79602ac309aa1aa8f8920804 035f415499523e50c9b09de1d2e90b00449737d9  ← 命中
```

**Git 层面的确切解释**：

| 合并方式 | 提交图 | `is-ancestor` | `--merged` | `git cherry` | patch-id |
|---|---|---|---|---|---|
| **fast-forward** | `main` 直接指向 topic tip | ✅ 0 | ✅ 列出 | — | — |
| **merge commit**（`--no-ff`） | main 有 merge commit，parents = (main, topic) | ✅ 0 | ✅ 列出 | — | — |
| **squash merge** | main 得到一个**全新 commit**（tree 相同但非 descendant） | ❌ **1** | ❌ **不列出** | ❌ `+` | ✅ **命中** |
| **rebase merge**（ref 已更新） | topic ref 指向新 SHA 链，已在 main 上 | ✅ 0 | ✅ 列出 | — | — |
| **rebase merge**（ref 未更新，旧 SHA 残留） | 旧链不在 main 上 | ❌ **1** | ❌ **不列出** | ✅ `-` | ✅ **命中** |

**根因**：`squash` 和 `rebase` 都会**重写提交历史**——它们产生的提交拥有新的 SHA，原 topic 的提交不再位于 main 的祖先链上。`git branch --merged` 底层就是 `git merge-base --is-ancestor`，所以必然漏判。patch-id 之所以有效，是因为它**忽略 commit 身份，只比 diff 内容**，而 squash/rebase 都保留了 diff 内容。

### 3.2 对立正的具体影响

**不会误删（这是好消息）**：`--merged` 只在 topic tip 是 main 祖先时才列出。既然 tip 在 main 的可达闭包里，删除该分支不会丢失任何 main 不可达的提交。**所以立正的删除路径是 sound 的——永远不会删掉未合并的工作。**

**会漏判（这是问题）**：
1. **squash merge 后的分支永远留不下**。立正会把它们归入"陈旧未合并"（30 天以上），只报告不删。用户会看到一堆"陈旧未合并"的分支，实际上它们早已合并（内容上），造成困惑与仓库膨胀。
2. **rebase merge 后本地残留旧分支同样漏判**（如果开发者本地没更新分支 ref）。
3. 报告里"陈旧未合并"这个标签是**误导性的**——它既可能是真的未合并，也可能是 squash/rebase 合并。用户无法据此判断。

### 3.3 ⚠️ 更严重的问题：远程侧的数据丢失风险（必须修）

立正 `branch_cleanup_audit.sh` 第 49 行：
```bash
rmerged=$(git branch -r --merged "$DEFAULT" 2>/dev/null | ...)
```
这里用的是**本地 `$DEFAULT`**（本地 main），而不是 `origin/$DEFAULT`。

实验脚本：`$env:TEMP\exp3.ps1`（已实测，真实输出）：
```
=== STATE 2: merge feature into LOCAL main only, never push to origin ===
  git branch -r --merged main        => [origin/HEAD, origin/feature, origin/main]
  git branch -r --merged origin/main => [origin/HEAD, origin/main]
  is-ancestor origin/feature main        exit=0   (0 = ancestor)
  is-ancestor origin/feature origin/main exit=1
```

**场景**：开发者在本地 main 上合并了 `feature`（`--no-ff`），但还没 push 到 origin。此时：
- `git branch -r --merged main` 报告 `origin/feature` 已合并 ✅
- 但 `origin/feature` 的提交**并不在 `origin/main` 上** ❌

如果立正据此建议删除 `origin/feature`（远程不可逆动作），**那些只存在于该远程分支上的提交就会永久丢失**（除非开发者随后 push 了本地 main）。

**对比**：`git branch -r --merged origin/main` 正确返回空（不含 origin/feature）。

**修法**（三选一，推荐 1）：
1. **远程分支用 `git branch -r --merged origin/$DEFAULT` 判定**（对比 origin/main 而非本地 main）。
2. 审计前先 `git fetch origin`（nkt/git-cleanup 的做法），让本地 main 追上 origin/main 再判定。但立正脚本是**只读审计**，fetch 算写操作（改 refs），需要取舍。
3. 对 `remote_merged_candidates` 额外加一道 `git merge-base --is-ancestor origin/$short origin/$DEFAULT` 验证，不通过则降级为"可疑"。

### 3.4 patch-id 检测的正确性边界（为什么建议"只报告不删"）

实测确认了两个必须遵守的边界（`$env:TEMP\exp2.ps1`）：

```
=== VERIFY: squashed-copy trick ===
  git cherry main <squashed-copy> => [- 7efb8d2016f0551cd1dae28fce0c31d8fc395ede]
    (all '-' => DEFACTO MERGED)          ← squash 合并可被识别

=== CONTROL: unmodified feat2 cherry ===
  git cherry main feat2 => [+ ... + ...]
    ('+' => 未识别)                       ← 原始分支识别不出

=== EDGE: branch got NEW commits after squash merge (must stay UNMERGED) ===
  git cherry main <squashed-copy of feat2plus> => [+ 91e4a0b8ce1de9e98b60ab6eea1c0066ce51ef92]
    (any '+' => correctly NOT merged)     ← 分支在合并后又有新提交，正确判定为未合并

=== EDGE: empty branch (no diff vs base) must not false-positive ===
  patch-id(empty range): '' (empty => skip)
```

**关键边界**：
1. **分支在 squash 合并后又有新提交** → patch-id 不再匹配 → 正确判定为未合并 ✅
2. **空分支（与 base 无 diff）** → patch-id 输出为空 → **必须跳过**，否则空字符串比对可能产生假阳性 ✅（nkt/git-cleanup line 446–451 有 `base_tree.id() == tip_tree.id()` 显式检查）
3. **合成 squash commit 用 `git commit-tree` 会写入对象库** —— git-delete-merged-branches 因此在 dry-run 下仍会执行它（这是有意的副作用），并且在 detached HEAD / 未提交改动时跳过 level-3 检查。**patch-id 方案（`git diff-tree | git patch-id`）不写对象库，更安全**，这是 nkt/git-cleanup 优于 hartwork 的一点。
4. **patch-id 是内容哈希，理论上可能在不同分支的无关变更间碰撞**（虽然概率极低，因为 `--stable` 排除了行序、作者、提交信息）。这是"只报告不删"的根本理由：**patch-id 匹配是强证据但不是 ancestry 级别的证明**。

### 3.5 结论

| 维度 | 立正当前状态 | 评价 |
|---|---|---|
| 本地合并判定 soundness | ✅ `--merged` 只报祖先分支 | **安全，不会误删未合并工作** |
| 本地合并判定 completeness | ❌ 漏 squash/rebase | 会漏，分支永久留不下 |
| 远程合并判定 soundness | ❌ 用本地 main 判定 origin 分支 | **有数据丢失风险，必须修** |
| `-d` 作为第二保险 | ✅ 本地用 `git branch -d` | 有效——即使判定误报，`-d` 也会拒绝未合并分支 |
| 陈旧分支策略 | ✅ 只报告不删 | **正确**，最保守的选择 |

---

## 4. 受保护分支名单对照

### 4.1 各工具默认保护哪些分支

| 工具 | 默认保护名单 | 机制 | 是否可扩展 |
|---|---|---|---|
| **立正** | `main master develop dev trunk prod production gh-pages gh-readonly` + `release/*` + 当前分支 + DEFAULT | 脚本内硬编码数组 + `case` 模式匹配 | ❌ 需改脚本 |
| **nkt/git-cleanup** | `main master develop trunk HEAD` | Rust 常量 + `git config cleanup.protect`（**多值 + 逗号分隔**）+ `--protect` | ✅ 三处叠加 |
| **git-delete-merged-branches** | **无默认** | 纯 `git config` 驱动（`branch.<name>.dmb-excluded`），首次运行交互配置 | ✅ 完全配置化 |
| **git-stale-branch-cleaner** | `main master develop dev trunk production release` + base 自身 | Python `frozenset` | ⚠️ 需改源码 |
| **gitsweep** | `main master develop dev release HEAD` | JS `Set` | ⚠️ 需改源码 |
| **clean-git** | `release/*` `hotfix/*`（**正则**） | Go `regexp.MatchString` + `IncludeRegex` 白名单 | ✅ 配置化 |
| **herdr-branch-cleanup** | 无名单；靠"本地分支==默认分支"跳过 | 语义守卫 | — |
| **git-prune-merged** | **无** | — | — |
| **git-cleanup-branches** | **无** | — | — |

**对照观察**：
- **`HEAD` 入名单**（nkt/git-cleanup、gitsweep）：防止把 detached HEAD 或 `refs/heads/HEAD` 这类异常 ref 当成分支删。立正没有，建议加。
- **base/DEFAULT 自身入名单**（git-stale-branch-cleaner 显式、立正隐式）：防止"merge base 自己合并进自己"的自指。
- **正则 vs 名单**：clean-git 用正则是唯一做法，`release/*` 这种 glob 很自然。立正用 `case` + 数组，对 `release/*` 支持良好，但 `release/2024/*` 这类多级就无能为力。
- **git config 持久化**（nkt/git-cleanup、git-delete-merged-branches）：这是**最佳实践**——用户配置一次，所有工具/会话共享，不需要改脚本。立正硬编码在脚本里，每次调整都要改代码。

### 4.2 GitHub protected branch / rulesets 怎么查

**验证结果**（`gh` 2.99.0，2026-09）：

```
$ gh api "repos/git/git/rulesets"        → []                    ← 端点存在，返回数组
$ gh api "repos/git/git/rules/refs/heads/main"  → 404            ← 端点存在（该 ref 无规则）
$ gh api "repos/git/git/branches/main/protection" → 404          ← 端点存在（未配置 legacy protection）
```
（git/git 仓库本身没配规则，所以是空/404，但端点路径是有效的。）

**三条端点线，用途不同**：

| 端点 | 作用 | 何时用 |
|---|---|---|
| `GET /repos/{owner}/{repo}/rulesets` | 列出仓库级 **rulesets**（新版，2022+） | 首选。返回每个 ruleset 的 `name`、`target.id`（分支/标签模式）、`enforcement`、`rules[]` |
| `GET /repos/{owner}/{repo}/rules/{ref}` | 列出**实际作用于某个 ref** 的规则（跨仓库+组织+企业级汇总） | 判断"这个具体分支现在受不受保护"最准确 |
| `GET /repos/{owner}/{repo}/branches/{branch}/protection` | **legacy branch protection**（旧版，仍被大量仓库使用） | 兼容老仓库 |

**关键 ruleset 字段**（判断"能否删分支"用）：
```json
{
  "id": 123,
  "name": "main protection",
  "target": { "type": "branch", "id": 456 },
  "enforcement": "active",
  "target_type": "branch",
  "pattern": "main",
  "bypass_list": [...],
  "rules": [
    { "type": "deletion", "parameters": {} },        // ← 禁止删除
    { "type": "creation", "parameters": {} },
    { "type": "pull_request", "parameters": {...} },
    { "type": "linear_history", "parameters": {} }
  ]
}
```
**`rules[]` 里出现 `type == "deletion"` 即该分支禁止删除。**

**组织/企业级**：
- `GET /orgs/{org}/rulesets`
- `GET /orgs/{org}/rulesets/{ruleset_id}/branches`（列出该 ruleset 覆盖的分支）

**CLI 一行查**：
```bash
gh api "repos/$OWNER/$REPO/rulesets" --jq '[.[] | select(.enforcement=="active") | {name, pattern: (.target.name // .pattern), rules: [.rules[].type]}]'
gh api "repos/$OWNER/$REPO/rules/refs/heads/main" --jq '.rules[].type'
```

### 4.3 更好的做法（三条路径，按投入排序）

**路径 A：本地 git config 持久化名单（推荐立正采用，投入最小）**
照搬 nkt/git-cleanup 的 `cleanup.protect` 模式：
```bash
git config cleanup.protect "release, staging"   # 单值
git config --add cleanup.protect "hotfix/*"     # 多值追加
```
立正脚本读法（bash 侧）：
```bash
while IFS= read -r p; do protected+=("$p"); done < <(git config --get-all cleanup.protect 2>/dev/null)
```
**理由**：用户配置一次全仓库共享，脚本无需改动；多值天然支持 `release`、`staging`、`hotfix/*` 混合；与 CI/团队其他 git 工具（cleanup 命令族）共享同一约定。

**路径 B：运行时叠加 GitHub rulesets 查询（推荐，gh 可选依赖）**
立正已有 `gh` 可选依赖（开 PR 用），可加一步：
```bash
if command -v gh >/dev/null 2>&1; then
  gh api "repos/$OWNER/$REPO/rulesets" --jq '
    [.[] | select(.enforcement=="active")] |
    [ .[] | .rules[]? | select(.type=="deletion") | .. | objects | .target.name? // empty ]' 2>/dev/null
fi
```
**理由**：这是**唯一权威来源**——真正受保护的分支只有 GitHub 说了算，任何本地名单都可能与仓库设置漂移。立正现有描述里已写"受保护名单：… + 仓库保护分支"，但目前实现并未真正去查 GitHub，这一步是**补上已有承诺**。
**注意**：rulesets API 需要 `repo` 或 `read:repo` scope；无权限时应**静默降级**到本地名单，而不是报错（否则会让整个审计失败）。

**路径 C：把删除权交给 GitHub（零风险上限）**
在仓库 Settings → General → Pull requests 开启 **"Automatically delete head branches"**，或在 Ruleset 里加 `delete_branch` 规则。**工具只负责报告，删除由 GitHub 在合并时执行**——完全避免不可逆风险。立正可以把这个作为"下一步建议"输出给用户。

**关于"更保守的默认名单"的建议**：
- 加入 `HEAD`（防异常 ref）
- 加入 `develop/*`、`staging`、`staging/*`、`qa`、`integration`、`stg`（clean-git 的经验值）
- `gh-pages` 立正已有 ✅；建议补 `gh-pages/*` 和 `docs`、`docs/*`
- `release/*` 建议改为 glob 实现（`case "$1" in release/*) return 0;; esac` 已有，但 `release/2024.1` 这类会漏）——或改用正则

---

## 5. 可直接吸收的做法清单

按"投入/收益"排序。每条给出**做什么、怎么做、理由**。

### 5.1 🔴 必须修（数据丢失风险）

**1. 远程合并判定改用 `origin/$DEFAULT`**
- **做什么**：`branch_cleanup_audit.sh` 第 49 行 `git branch -r --merged "$DEFAULT"` → `git branch -r --merged "origin/$DEFAULT"`。
- **理由**：§3.3 实验证明用本地 main 会把"只合并进本地、未推送的分支"误报为远程已合并，删远程分支会永久丢提交。这是唯一会造成**数据丢失**的 bug。
- **注意**：`origin/$DEFAULT` 可能不存在（未 fetch 过、或 origin/HEAD 指向异常），需要 `[ "$(git rev-parse --verify --quiet "origin/$DEFAULT")" ]` 守卫，失败时回退到当前行为并在 JSON 里标注 `remote_base_unverified: true`。

**2. 加入 `HEAD` 到受保护名单**
- **做什么**：`protected=("main" "master" "develop" "dev" "trunk" "prod" "production" "gh-pages" "gh-readonly")` → 加 `"HEAD"`。
- **理由**：nkt/git-cleanup、gitsweep 都有。防止 detached HEAD 场景下的异常 ref 被当成普通分支处理。

### 5.2 🟠 强烈建议（补上已有承诺）

**3. 真正实现"仓库保护分支"查询（用 gh）**
- **做什么**：审计阶段若 `gh` 可用，查询 `gh api "repos/$OWNER/$REPO/rulesets"`，把 `enforcement=="active"` 且 `rules[]` 含 `type=="deletion"` 的分支名加入受保护名单；失败静默降级。
- **理由**：立正现有描述承诺了"受保护名单：… + 仓库保护分支"，但当前实现没有真正去查。这是**唯一权威来源**，本地名单必然与仓库设置漂移。立正已有 gh 可选依赖，边际成本极低。
- **实现要点**：rulesets 的 `pattern` 支持 glob（`release/*`），需要用同样的 glob 匹配逻辑而不是精确字符串比对；`target.name` 在 branch 类型时即分支名。

**4. 受保护名单支持 git config 持久化**
- **做什么**：读 `git config --get-all cleanup.protect`（多值）叠加到硬编码名单之上；文档里给出 `git config --add cleanup.protect "staging"` 的用法。
- **理由**：git-delete-merged-branches 和 nkt/git-cleanup 都这么做。用户配置一次全仓库共享，脚本不用改；且与生态内其他 cleanup 工具（nkt/git-cleanup 装成 `git cleanup`）共享同一约定。
- **实现要点**：bash 侧 `git config --get-all` 逐行读；pwsh 侧 `git config --get-all cleanup.protect` 管道。注意 `.sh` 与 `.ps1` 两套实现对齐（AGENTS.md 要求）。

**5. 加入"疑似已 squash/rebase 合并"报告分类（只报告，不删）**
- **做什么**：对未合并但陈旧的分支，用 `git diff-tree -p <merge-base> <branch> | git patch-id --stable` 算出整段 patch-id，与 `git log --first-parent --format='%H' -p <merge-base>..$DEFAULT | git patch-id --stable` 比对；命中则归入新分类 `squashed_candidates`。
- **理由**：§3.1 实测证明这是唯一能同时抓 squash + rebase 合并的本地 git 手段。立正当前把这类分支误报为"陈旧未合并"，用户无法判断。**只报告不删**——因为 patch-id 是内容哈希而非 ancestry 证明，理论上可能碰撞（虽然概率极低）。
- **实现要点**（照搬 nkt/git-cleanup，但可简化）：
  1. **跳过空 diff**：`git rev-parse <branch>^{tree}` == `git rev-parse <merge-base>^{tree}` 则跳过（§3.4 边界 2）。
  2. **限制扫描深度**：`git log -n 2000` 之类封顶，避免老仓库跑飞。
  3. **`--first-parent` 必加**：否则 merge commit 会把整段子树的历史都拉进来，patch-id 映射会包含无关提交。
  4. **只算主分支方向**：topic 侧算"整段 range 当一个 patch"（`git diff-tree -p mb tip`），main 侧算"逐 commit 的 patch"（`git log -p`），两边 patch-id 空间一致才能比对。
  5. 输出到 JSON 的新字段，**不进入删除候选**。

### 5.3 🟡 值得做（安全加固）

**6. 删除前检查分支是否被 worktree 检出**
- **做什么**：`git worktree list --porcelain` 解析出所有 `branch refs/heads/X` 条目；被检出的分支跳过（或报告"需先移除 worktree"）。
- **理由**：nkt/git-cleanup 专门做了这件事（`list_worktree_branches()`）。`git branch -d` 本身会拒绝删除被检出的分支，所以**不会真出事**，但报告里出现"删除失败"对用户不友好，且 linked worktree 场景（git worktree add）下分支是 worktree 的"身份"。
- **实现要点**：bash 侧 `git worktree list --porcelain | awk`；注意只排除非主 worktree。

**7. 远程删除加 `--force-with-lease`**
- **做什么**：远程删除命令从 `git push origin --delete <branch>` 改为 `git push origin --delete --force-with-lease=<branch>:<expected_sha>`。
- **理由**：hartwork/git-delete-merged-branches 是唯一用这个 flag 的。防止在"审计完成→用户确认"的时间窗口内他人推了新提交时把它一起删掉。
- **实现要点**：`<expected_sha>` 取审计时记录的 `git rev-parse origin/$branch`。注意 `--force-with-lease` 对 delete 的语法是 `--force-with-lease=<refname>:<oldvalue>`。
- **权衡**：如果用户确认时间窗口很短，收益有限；但代价也只是一行参数。**若实现成本可接受，建议做**。

**8. 加 `--include-regex` 白名单（可选）**
- **做什么**：可选参数，只考虑匹配的正则分支（如 `^feat/`、`^issue-`）。
- **理由**：git-delete-merged-branches 和 clean-git 都有。大仓库常有约定命名规范，白名单比黑名单好维护。
- **优先级低**：立正的"受保护名单"已是反向过滤，白名单是锦上添花。

### 5.4 ⚪ 观察但暂不吸收

**9. 多目标分支（required_target_branches）**
- git-delete-merged-branches 允许配置多个"必须合并进的目标"（如 main + develop），用集合交集。
- **暂不做**：立正的语义是"默认分支"单一目标，引入多目标会显著增加复杂度。若未来支持 develop 作为集成线，再考虑。

**10. 用 `gh pr list --state merged` 作为权威信号**
- git-prune-merged 和 herdr-branch-cleanup 都证明这是最可靠的判定（与 git 历史无关，天然覆盖 squash/rebase）。
- **暂不做**：强依赖 gh + GitHub。但可作为 §5.2-3 的**副产品**：既然已经调用了 `gh api rulesets`，多调一次 `gh api "repos/$O/$R/pulls?state=closed&sort=updated"` 过滤 `merged_at` 的成本很低，可以把"该分支对应的 PR 确实是 merged 状态"作为一个**置信度增强字段**输出，而不是作为删除依据。

**11. `git cherry` 检测 rebase 合并**
- 比 patch-id 简单（一条命令），且对 rebase 合并有效（§3.1 实测 `-` 前缀）。
- **不单独做**：patch-id 已覆盖 cherry 的能力且更强（同时抓 squash）。除非实现 patch-id 太贵，否则 cherry 是冗余的。

**12. 陈旧阈值可配置**
- 立正硬编码 30 天。clean-git 用 `MaxAge` 配置，git-stale-branch-cleaner 用 `--days`。
- **暂不做**：30 天是合理默认，立正定位是"巡检报告"而非"清理工具"，陈旧阈值不是核心参数。若用户反馈再抽成配置。

### 5.5 反面清单（立正已经避开的坑）

| 反面做法 | 谁这么做了 | 立正的对应正确做法 |
|---|---|---|
| `git branch --merged` 不带 base（默认当前分支） | git-cleanup-branches | 显式传 `$DEFAULT` ✅ |
| 删除时无条件 `git branch -D` | git-cleanup-branches、clean-git（-d 失败回退 -D） | 只用 `-d`，把它当第二保险 ✅ |
| 无受保护名单 | git-prune-merged、git-cleanup-branches | 10 个硬编码名 + 模式 ✅ |
| 陈旧分支也删 | clean-git（但用 MaxAge 双重门槛缓解） | 陈旧**只报告不删** ✅ |
| 无 dry-run | git-cleanup-branches | 审计脚本天然只读 ✅ |
| 不检查当前分支 | 多数工具 | 立正把当前分支加入 protected ✅ |
| 远程删除无确认 | GitHub Actions snippet 多数 | 立正要求最终确认 ✅ |

---

## 附录 A：立正当前实现的实际行为（`scripts/branch_cleanup_audit.sh`）

逐行核对了实际脚本，与任务描述一致，补充几个细节：

- **受保护名单**（line 12–14）：`main master develop dev trunk prod production gh-pages gh-readonly` + 当前分支 + DEFAULT；`release/*` 用 `case` 模式匹配（line 16–20）。**注意：`gh-readonly` 在脚本里有，但任务描述没提；`release/2024.1` 这类多级路径不会被 `release/*` 匹配到。**
- **陈旧阈值**（line 39）：`[ "$age_days" -gt 30 ]`，硬编码 30 天，且用 `committerdate`（`%cI`）。
- **陈旧分支排除**（line 39）：`! is_protected "$b" && [ "$b" != "$current" ]` ✅ 双重排除。
- **远程存在性**（line 46–47）：`git ls-remote origin` 缓存一次，然后 `grep -Fq -- "refs/heads/$1"`——**这是比 `git for-each-ref refs/remotes` 更准确的做法**（不依赖本地 refs 是否已 prune）。立正这里做得比 nkt/git-cleanup 还好（后者要先 `fetch --prune`）。
- **输出**（line 64）：单一 JSON 对象，字段 `is_git / default_branch / current_branch / protected / local_merged_candidates / local_stale_unmerged_report / remote_merged_candidates`。结构清晰，适合下游消费。
- **缺失**：未真正查询 GitHub 仓库保护规则（§4.3 路径 B）；远程判定用本地 main（§3.3 bug）。

## 附录 B：实验脚本位置（可复现）

- `$env:TEMP\exp.ps1` — squash/rebase/ff 三种合并下 `--merged`、`is-ancestor`、`git cherry`、`patch-id` 的对比
- `$env:TEMP\exp2.ps1` — squashed-copy 技巧验证 + 两个必须遵守的边界（合并后有新提交、空分支）
- `$env:TEMP\exp3.ps1` — stale local main 导致远程合并判定误报（立正的实际 bug）

实验环境：git 2.55.0.windows.3，Windows PowerShell 7。
