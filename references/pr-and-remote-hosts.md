# PR 与远程宿主

开 PR/MR 是远程不可逆动作——任何路径都按 `autonomy-and-safety.md` 做**执行点单独最终确认**后再执行。

## 宿主识别（按主机名，不得对整条 URL 子串匹配）
- 取 `git remote -v` 的 fetch URL，解析出 **host 段**：
  - `scheme://[userinfo@]host[:port]/path` → 取 `host`。
  - scp 形态 `git@host:path` → 取 `@` 与 `:` 之间的 `host`。
- **只拿 host 与宿主域名比对**（`github.com` 及其子域、`gitlab.com`、`bitbucket.org`、`codeberg.org`、`gitea.*`…）。
- ❌ **不得对整条 URL 做 `github.com` 子串匹配**：自建 GitLab 的**路径里含 `github.com`** 时（如 `https://git.corp.example/github.com-mirror/tool.git`）会被误判成 GitHub，进而错误地去调 `gh pr create`——对着一个 GitLab 仓库开不了 PR，还会把失败误报成"没权限"。
- 判不出宿主 → 一律按下面的"通用 PR 就绪产物"处理，**不猜**。
- **输出远程 URL 一律用脱敏形式 `remote_url_masked`**（`scheme://***@host/path`，去掉 userinfo 里的 token/用户名密码），见 `scan-recipes.md`。报告、PR body、日志里都不许出现带凭据的原始 URL。

## GitHub（github.com）
- 推送分支后：`gh pr create --base <默认分支> --head <当前分支> --title "<title>" --body "<body>"`。
- title：提交信息主体或 conventional 类型概括。
- body：按 `../assets/templates/pr-body.md`（动机/改动/验证/文档与版本一致性声明）。
- 开 PR 前先查是否已有同题开放 issue/PR（`gh_query_state="ok"` 时才作数），避免重复。
- gh 未登录 → 提示 `gh auth login`，其余流程照常；CLI 不可用时退化到下面的"通用 PR 就绪产物"。

## GitLab（gitlab.com / 自建 gitlab）
- 不调 `gh`。官方 CLI `glab`（若装了，先 `glab auth login`）：
  - `glab mr create --source-branch <当前分支> --target-branch <默认分支> --title "<title>" --description "<body>"`
- 无 glab → Web：打开 `<远程URL>/-/merge_requests/new`，选 source/target 分支（URL 可附 `?merge_request[source_branch]=<head>&merge_request[target_branch]=<base>`，形态随版本略有差异）。

## Gitea / Codeberg / 自建 Gitea
- CLI `tea`（或 `gitea`，若装了，先 `tea login`）：
  - `tea pulls create --base <默认分支> --head <当前分支> --title "<title>" --description "<body>"`
- 无 → Web：`<远程URL>/compare/<默认分支>...<当前分支>`。

## Azure DevOps
- `az` CLI + azure-devops 扩展（若装了，先 `az login`）：
  - `az repos pr create --source-branch <head> --target-branch <base> --title "<title>"`（`--description` 传 body）。
- 无 → Web：仓库 Pull Requests 页"New pull request"。

## Bitbucket（bitbucket.org / 自建）
- 无通用一等 CLI——不编造命令。走 Web：仓库 Pull requests 页"Create pull request"，选源/目标分支。

## 降级一：无 remote / 纯本地
"从来没配过远程"。
- 跳过 fetch/pull/PR；只产出本地"PR 就绪产物"（分支 + diff 概览 + title/body），提示用户：**先建远程并连上**，之后再来开。
- 报告话术：说"项目还没连远程仓库，这步先跳过"，不要说成"没有可推送的分支"。

## 降级二：有 remote 但不可达（与"无 remote"是两件事）
**判据**（满足任一即认定不可达）：
- `git fetch` 或 `git push` 失败（鉴权失败、DNS 解析失败、网络不通、代理拦截、SSH key 不匹配）；
- `git_state_snapshot` / `branch_cleanup_audit` 的 `remote_reachable=false`（`git ls-remote origin` 失败）；
- `warnings[]` 含 `remote-unreachable`。

**动作**：
- **照常产出 PR/MR 就绪产物**：分支名、base、`git diff <默认分支>...HEAD --stat` 概览、建议 title/body（按 `../assets/templates/pr-body.md`）+ 该宿主的手动创建指引（CLI 或 Web，见上面对应小节）。
- **明确告诉用户"没连上远程"**，并把失败原因摘要如实写出（鉴权 / DNS / 网络 / 代理）。⚠️ **不得**说成"没有远程"或"没有可推送的改动"——"没查成"不是"没有"。
- **不重试超过 2 次**；**不换协议绕过**：HTTPS 失败不自动改 SSH、不改 host、不自动改 `.git/config`。重试 2 次仍失败就停在这里等用户处理凭据/网络。
- 报告话术必须与"无 remote"区分：无 remote 是"还没连，需要你去建"；不可达是"连不上，需要你查网络/凭据"。

## 通用 PR 就绪产物（任何非 GitHub，或宿主 CLI 不可用，或远程不可达时）
- 分支名与 base。
- `git diff <默认分支>...HEAD --stat` 概览 + 完整 diff 指引。
- 建议的 title/body（同 `../assets/templates/pr-body.md`）。
- 该宿主开 MR/PR 的指引（按上面对应宿主给 CLI 或 Web）。
- 远程地址用 `remote_url_masked`；写清"这是本地准备好的产物，需要你手动推送/创建"。
- 不编造宿主专属命令；不确定就只给 Web 创建指引。
