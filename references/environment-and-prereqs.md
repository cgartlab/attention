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

## 6. shell 探测与脚本路径选择（P1 起）
立正的采集脚本有 bash（.sh）与 PowerShell（.ps1）两套实现，输出同形 JSON（契约见 `references/scan-recipes.md`）。Phase 0 探测可用 shell 后选路径：

1. **bash 可用**（`command -v bash` 成功）→ 用 `.sh`：`bash "<base>/scripts/<name>.sh" --repo <path>`。覆盖 Linux/macOS/WSL/Claude Code/Cursor。
   - **Windows 注意**：Git for Windows 自带 bash.exe 但常不在 PATH，command -v bash 会漏。检测失败时查 git 安装目录下的 bin\bash.exe（由 git 路径推导，如 C:\Program Files\Git\bin\bash.exe），找到即用该全路径调 .sh。
2. **否则 pwsh 可用**（`pwsh -v` 成功）→ 用 `.ps1`：`pwsh -NoProfile -File "<base>/scripts/<name>.ps1" --repo <path>`。覆盖 Windows/DSH。
3. **两者都不可用**（harness 只让模型直接执行命令）→ 无脚本回退：模型按 `references/scan-recipes.md` 的 git 命令配方，用 harness 给的任意 shell 直接跑 git 并自行组装 JSON；判断流程不变。

> 为什么三层而非一把梭成 bash：立正的开发/验证环境是 Windows/pwsh（无 bash），纯 bash 重写会让它在自己环境跑不起来。双实现 + 回退，覆盖最广；契约单一事实源在 scan-recipes.md，防双份漂移。

> 运行时依赖：仅 `git`（必需，缺则停止）；`gh`（可选，PR 用，缺则降级为就绪产物）。不要求 Python/Node/pwsh/bash 作为硬依赖——它们只是某条脚本路径的前置，缺了换路径。
