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

> 为什么不一刀切 main：很多老仓库还是 master，有的用 develop/trunk。假设错了，`pull --ff-only` 与剪枝判断全错。探测不到时**不得假装是 main**（脚本侧输出 `default_branch=null` + `default_branch_source=unavailable`，见 `scan-recipes.md`）。

## 3. 远程宿主探测
- `git remote -v` 看 fetch/push URL。
- **按主机名判宿主**（`scheme://[userinfo@]host[:port]/path` 或 `git@host:path` 里的 host），**不得对整条 URL 做子串匹配**——自建 GitLab 的路径里含 `github.com` 会被误判成 GitHub。细则见 `pr-and-remote-hosts.md`。
- `github.com`（或其子域）→ GitHub 路径（gh 全功能）。
- `gitlab`/`bitbucket`/`gitea`/`codeberg` 等 → 非 GitHub 路径：PR 降级为"PR 就绪 diff + 手动指引"，不调 `gh pr create`。
- **无 remote** → 纯本地仓库：跳过 fetch/pull/PR，只做本地巡检与本地分支剪枝。
- **有 remote 但不可达**（第三种情况，别和"无 remote"混为一谈）：`git fetch`/`git push` 失败，或 `remote_reachable=false`，或 `warnings[]` 含 `remote-unreachable` → 照常产出 PR/MR 就绪产物 + 手动指引，并**明确告诉用户"没连上远程"**；不重试超过 2 次、不换协议绕过。细则见 `pr-and-remote-hosts.md`。

## 4. gh 鉴权
- **登录态用本地探测**：`gh auth token`（只读本地凭据，**不联网**；退出码 0 = 已登录）。**不要用 `gh auth status` 判定登录态**——它会做网络检查，抖动时会被读成"未登录"（`pr_available=false`），等于把"没查成"讲成"没有"（实测：代理指向死端口时 `gh auth status` rc=1 而 `gh auth token` rc=0）。宿主不匹配同样用本地判定：`gh auth token --hostname <remote host>` 非 0 且已登录 → `gh-host-mismatch`。需要给人看的账号信息（用户名/宿主）才用 `gh auth status`，且其失败要记为"没查成"。
- 未登录或非活动 → 标记 `pr_available=false`，继续其余流程，到开 PR 处给手动指引。
- 多账户：确认活动账户匹配 remote owner，不匹配时提示（`gh_query_state` 会反映为查询不可用）。

## 5. 项目画像（决定文档集与版本文件）
- **项目类型与"版本承载文件"**：**同一张表，见 `references/version-file-inventory.md`**（生态 / 文件 / 字段位置 / 是否必备 / 备注）。**本节不再自带一份清单**——历史上本节与 `release-versioning.md` 各有一份，成员互不一致（本节列了 `Gemfile`、`mix.exs`、`CMakeLists.txt`，那边没有；那边有 `gradle.properties`，本节只写 `build.gradle`）。
  只提醒三条容易踩的：
  1. **一个仓库可以同时是多种类型**（monorepo、Rust workspace、多语言项目）——按表逐类核对，别只认第一个命中的特征文件。
  2. **有特征文件 ≠ 有产品版本**：`go.mod` 没有版本字段、`.NET` 的 `global.json` 是 SDK 版本。别把工具链版本当产品版本去对齐。
  3. **lockfile 也是版本承载文件**，必须一起核对（它不是包管理器现算的）。
- **核心文档集**：完整定义见 `judgment-criteria.md` 的"核心文档集"（`core-docs-sync.md` 只做路由）。按项目实际布局可覆盖。
- **提交规约**：读 `git log --pretty=format:%s -n 30`，多数形如 `type(scope): ...` → 判定 conventional commits，沿用；否则沿用仓库已有风格。**不要自创风格**——沿用现状比"更规范"更重要。
- **测试/lint/build 命令**：读 `package.json` scripts（test/lint/build/check）、Makefile 目标、`pyproject.toml` 配置等。找不到 → 跳过该步，**不编命令**。

## 6. shell 探测与脚本路径选择（P1 起）
立正的采集脚本有 bash（.sh）与 PowerShell（.ps1）两套实现，输出同形 JSON（契约见 `references/scan-recipes.md`）。Phase 0 探测可用 shell 后选路径。

> **判据是"能否执行"，不是"文件是否存在"。** 只 `command -v` 成功、或只找到一个文件，都**不构成**可用。

1. **bash 可用** → 用 `.sh`。
   - **探测方式（执行探测）**：跑 `bash -c 'echo ok'`，**看退出码为 0 且输出为 `ok`**。退出非 0、或输出里出现 `couldn't create signal pipe` 之类启动失败信息 → 判为不可用。
   - **为什么不能"找到即用"**：`C:\Program Files\Git\bin\bash.exe` 在受限沙箱里**文件存在但一启动就失败**（cygwin 起不来——信号管道被沙箱拒绝）。存在式判据会选中一个必然失败的路径，之后每次脚本调用都报错，还会被误读成"仓库有问题"或"脚本坏了"。
   - 调用：`bash "<base>/scripts/<name>.sh" --repo <path>`。覆盖 Linux/macOS/WSL/Claude Code/Cursor。
   - **Windows 注意**：Git for Windows 自带 bash.exe 常不在 PATH，`command -v bash` 会漏。检测不到时由 git 安装路径推导全路径（如 `C:\Program Files\Git\bin\bash.exe`），**并用同一个执行探测**（`& "<该全路径>" -c "echo ok"`）确认它能跑起来，再采用。
2. **否则 pwsh 可用** → 用 `.ps1`。探测方式同上：`pwsh -NoProfile -c "echo ok"` 退出 0 且输出 `ok`。
   - 调用：`pwsh -NoProfile -File "<base>/scripts/<name>.ps1" --repo <path>`。覆盖 Windows/DSH。
3. **两者都不可用**（harness 只让模型直接执行命令）→ 无脚本回退：模型按 `references/scan-recipes.md` 的 git 命令配方，用 harness 给的任意 shell 直接跑 git 并自行组装 JSON；判断流程不变。

> 为什么三层而非一把梭成 bash：立正的开发/验证环境是 Windows/pwsh（无 bash），纯 bash 重写会让它在自己环境跑不起来。双实现 + 回退，覆盖最广；契约单一事实源在 `scan-recipes.md`，防双份漂移。

> 运行时依赖：仅 `git`（必需，缺则停止）；`gh`（可选，PR 用，缺则降级为就绪产物）。不要求 Python/Node/pwsh/bash 作为硬依赖——它们只是某条脚本路径的前置，缺了换路径或走无脚本回退。`evals/` runner 需要 pwsh。
