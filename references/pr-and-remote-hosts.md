# PR 与远程宿主

开 PR/MR 是远程不可逆动作——任何路径都按 `autonomy-and-safety.md` 做最终确认后再执行。宿主从 `git remote -v` 的 URL 识别。

## GitHub（github.com）
- 推送分支后：`gh pr create --base <默认分支> --head <当前分支> --title "<title>" --body "<body>"`。
- title：提交信息主体或 conventional 类型概括。
- body：按 `../assets/templates/pr-body.md`（动机/改动/验证/文档与版本一致性声明）。
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

## 无 remote / 纯本地
- 跳过 PR；只产出本地"PR 就绪产物"（分支 + diff 概览 + title/body），提示连上远程后再开。

## 通用 PR 就绪产物（任何非 GitHub，或宿主 CLI 不可用时）
- 分支名与 base。
- `git diff <默认分支>...HEAD --stat` 概览 + 完整 diff 指引。
- 建议的 title/body（同 `../assets/templates/pr-body.md`）。
- 该宿主开 MR/PR 的指引（按上面对应宿主给 CLI 或 Web）。
- 不编造宿主专属命令；不确定就只给 Web 创建指引。