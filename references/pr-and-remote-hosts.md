# PR 与远程宿主

## GitHub（gh 可用）
- 分支已推送后：`gh pr create --base <默认分支> --head <当前分支> --title "<title>" --body "<body>"`。
- title：用提交信息主体或 conventional 类型概括。
- body：按 `../assets/templates/pr-body.md`，含动机、改动、验证、文档与版本一致性声明。
- 开 PR 是远程不可逆动作——按 `autonomy-and-safety.md` 最终确认。

## 非 GitHub（GitLab/Bitbucket/Gitea 等）
- 不调 `gh pr create`。
- 输出"PR 就绪产物"：
  - 分支名与 base。
  - `git diff <默认分支>...HEAD --stat` 概览。
  - 建议的 PR title/body（同模板）。
  - 该宿主开 MR/PR 的指引（如 GitLab：远端 Web 创建 MR，或 `glab mr create` 若有 glab）。
- 不编造宿主专属命令；不确定就给 Web 创建指引。

## gh 不可用 / 未登录
- 退化到与非 GitHub 同款"PR 就绪产物"，并提示 `gh auth login` 后可自动开 PR。