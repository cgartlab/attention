# Phase 0：环境与前置探测

每次激活立正Skill，先跑这套探测，把不确定一次性钉死。单一信号不足以下结论，至少两处印证。

## 1. 是不是 git 仓库
- 跑 `git rev-parse --is-inside-work-tree`。
- 非零退出或输出不是 `true` → 说明"当前目录不是 git 仓库"，停止，不做任何改动。
- git worktree 子目录也成立（`git rev-parse --show-toplevel` 给出真根）。

## 2. 默认分支探测（按优先级回退）
1. `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`（GitHub 且 gh 可用时最可靠）。
2. `git symbolic-ref refs/remotes/origin/HEAD`（去掉 `refs/remotes/origin/` 前缀）。
3. 逐一试存在性：`git show-ref --verify --quiet refs/heads/main`、`master`、`develop`、`trunk`。
4. 都不行 → 用 `ask_user_question` 列候选问用户，不默认假设。

> 为什么不一刀切 main：很多老仓库还是 master，有的用 develop/trunk。假设错了，`pull --ff-only` 与剪枝判断全错。

## 3. 远程宿主探测
- `git remote -v` 看 fetch/push URL。
- `github.com` → GitHub 路径（gh 全功能）。
- `gitlab`/`bitbucket`/`gitea`/`codeberg` 等 → 非 GitHub 路径：PR 降级为"PR 就绪 diff + 手动指引"，不调 `gh pr create`。
- 无 remote → 纯本地仓库：跳过 fetch/pull/PR，只做本地巡检与本地分支剪枝。

## 4. gh 鉴权
- `gh auth status`。
- 未登录或非活动 → 标记 `pr_available=false`，继续其余流程，到开 PR 处给手动指引。
- 多账户：确认活动账户匹配 remote owner，不匹配时提示。

## 5. 项目画像（决定文档集与版本文件）
- 项目类型：按特征文件识别——`package.json`(Node)、`Cargo.toml`(Rust)、`pyproject.toml`/`setup.py`(Py)、`go.mod`(Go)、`pom.xml`/`build.gradle`(JVM)、`*.csproj`(.NET)、`Gemfile`(Ruby)、`mix.exs`(Elixir)、`CMakeLists.txt`(C/C++) 等。
- 核心文档集：见 `core-docs-sync.md` 的默认集 + 按项目类型增补。
- 版本承载文件：见 `release-versioning.md` 的生态映射。
- 提交规约：读 `git log --pretty=format:%s -n 30`，多数形如 `type(scope): ...` → 判定 conventional commits，沿用；否则沿用仓库已有风格。
- 测试/lint/build 命令：读 `package.json` scripts（test/lint/build/check）、Makefile 目标、`pyproject.toml` 配置等。找不到 → 跳过该步，不编命令。

## 6. harness 适配
- 本 skill 主要在 DSH（pwsh）运行；脚本为 `.ps1`，用 `pwsh -NoProfile -File` 调。
- 探测到非 DSH（如 Claude Code、Codex）：脚本不可用时退化为你（模型）直接拼等价 git 命令采集；判断流程不变。