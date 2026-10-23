# 质量审计记录（2026-09-30）

> 这份文档记录**修复前实测到的缺陷**、复现方式与不可测边界。它是"为什么这么改"的依据，也是回归清单——`evals/run_evals.ps1` 里每条断言都对应下面某个编号。

## 方法与证据分级

| 级别 | 含义 | 本文档中的用法 |
|---|---|---|
| **实测** | 我在本机跑出来的，附最小复现命令 | 缺陷 D1–D11 |
| **读码** | 静态阅读源码得出，未实跑（如 bash 在受限沙箱不可用时的推断） | 已在有 bash 后补测 |
| **规范核对** | 对照 agentskills.io 规范原文逐字段核对 | 打包层结论 |

**环境边界（诚实声明，均未验证）**：远程操作在本沙箱不可测（本地路径传输要过 shell、`git://` 的 receive-pack 会挂死）；真实 GitHub PR 路径未验证；`npx skills add` 安装链路未验证（仓库未推送）；"无 skill 基线"在 DSH 内无法强制（skill 会被自动发现，某个基线 run 就加载了它）。

## 实测缺陷清单

### D1 `--repo` 无效 → 静默分析当前目录（**最高危**）
- 现象：`--repo` 指向不存在的路径、普通文件或空串时，脚本 `Set-Location`/`cd` 失败但继续执行，输出**当前所在仓库**的合法 JSON、`exit=0`、且 JSON 里没有任何字段说明路径失败。
- 复现：`pwsh -NoProfile -File scripts/git_state_snapshot.ps1 --repo C:\definitely\not\here` → `repo_root` 指向调用者所在仓库。
- 影响：agent 会巡检、汇报、甚至操作**错误的仓库**。`.sh` 同样（`cd` 失败不检查）。
- 修复：`--repo` 校验失败即输出 `{"is_git":false,"error":"repo path not found"}`（断言 `NEG-path-notgit`）。

### D2 `.sh` 输出**严格非法 JSON**（5 个脚本里的 2 个）
- 现象：CRLF 版本文件 → `version_consistency_audit.sh` 的值里带裸 `\r`；`next_steps_analysis.sh` 的 `todo_fixme` 带裸 CRLF。`System.Text.Json` 直接拒绝（RFC 8259 禁止字符串内裸控制字符）。
- 复现：`bash scripts/version_consistency_audit.sh --repo <CRLF 仓库>` → 严格解析失败。
- 修复：`_lib.sh` 的 `jes()` 补控制字符转义 + 取值剥离行尾 CR（断言 `all-strict-json`、`F8`）。

### D3 `release_involved` 在 `.ps1` 恒为 false
- 现象：`changed_files` 已含版本文件（`package.json`）时仍报 `false`，违反契约 §3。根因是对 `[pscustomobject]` 做 `-replace`/`Split-Path -Leaf`，取到的是对象字符串。
- 影响：Windows/pwsh 侧（skill 自己的开发环境）发行版本门槛**永不触发**。
- 修复：取 `$_.file` 属性；并把"是否涉及 release"改为**多层门**（信号层由脚本给，门槛层由模型判定）（断言 `F7-signal-vf`、`F12-*`）。

### D4 "两套实现同形 JSON"承诺为假
- 现象（同仓库同参数）：`.sh` 给相对路径 `package.json`，`.ps1` 给绝对反斜杠 `D:\\...\\package.json`；`test_commands[].script` 在 `.sh` 被截断成 `prettier --write \`；数组顺序不同（`sort -u` vs 首现序）。
- 修复：路径统一"相对仓库根 + 正斜杠"、数组统一排序、script 取完整值（断言 `all-parity`）。

### D5 `--repo` 漏值 → `.sh` 死循环挂死
- 现象：`bash scripts/git_state_snapshot.sh --repo`（漏值）3 秒未退出，持续刷 `shift count out of range`。`shift 2` 在 `$#=1` 时失败而 `$#` 不变，`while [ $# -gt 0 ]` 恒真。
- 修复：参数值存在性校验 + 正确 shift（断言 `NEG-novalue-nohang`）。

### D6 `color.ui=always` → 合并分支候选静默变空
- 现象：git 自己能列出已合并的 `feature/merged`，脚本返回 `[]`（ANSI 转义残留在分支名里使比对失配）。
- 修复：所有 git 调用加 `-c color.ui=never`（断言 `F14-color`）。

### D7 版本扫描不尊重 `.gitignore`
- 现象：被忽略的 `vendor/sub/Cargo.toml` 被当成版本文件 → 假"版本不一致"。排除只靠硬编码目录黑名单。
- 修复：文件池改为 `git ls-files` ∪ `git ls-files -o --exclude-standard`（断言 `F10-*`）。

### D8 自检在**非 git 目录**上 5/5 通过
- 现象：`smoke_test.ps1 --repo <非git目录>` → `5 passed, 0 failed`，因为它只验"能解析出 `is_git` 键"。且 `.sh` 版只测 `.sh`、`.ps1` 版只测 `.ps1`，**parity 永不可能被测到**。
- 修复：冒烟升级为"双实现都跑 + 逐字段 diff + 负例断言"；深测交给 `evals/run_evals.*`（断言 `F1-notgit`、`all-parity`）。

### D9 无远程仓库时"未推送"语义三方不一致
- 现象：契约说 `unpushed_commits` 无 range 时为 `null`，实现给 `[]`，`judgment-criteria` 说"无 upstream 时全部提交视为未推送"。本仓库（15 提交、无远程）因此被判"干净"。
- 修复：契约统一 `null` 语义 + 新增 `unpushed_branches` 字段给 Phase 2 第三条判据做机器支撑（断言 `F6-unpushed-branch`）。

### D10 宿主子串误判 + 凭据泄漏面
- 现象：remote URL 路径里含 `github.com` 即 `is_github=true`（自建 GitLab 会误判并驱动 `gh pr create`）；`remote -v` 原文可能含 token 并进入报告。
- 修复：按**主机名**判定 + 新增 `remote_url_masked`（断言 `F11-*`）。

### D11 文档同步扫描是低精度提示，却被当成裁决
- 现象：文档只写函数名（不写文件名）时 `docs_needing_update` 恒为空（**漏报**）；刚按它改完文档后又因自指而误报。字段名本身诱导"文档无需更新"的误读。
- 修复：更名 `docs_mentioning_changes` + 新增 `docs_stale_candidates` + 明确"门槛通过条件是逐条对照 diff"（断言 `F5`/契约 §4）。

### D12 fixture 生成静默失败 → 152 条"字段不存在"假失败（2026-10-22 实测，另一轮）

- 现象：在关掉 MSYS 路径转换的 shell（`MSYS2_ARG_CONV_EXCL=*`，部分 Agent 运行时会设置）里，`git -C /c/...` 直接报 `cannot change to`；两个 fixture 生成器把这些错误全丢了，**21 个 fixture 全部退化成"非 git 目录"而生成器仍 `exit 0`**。回归于是报 152 条"字段不存在"（557 中），读起来像断言或脚本回归，实际是 fixture 从未建成。
- 复现：`MSYS2_ARG_CONV_EXCL='*' bash evals/run_evals.sh` → 修复前 `152 failed`；修复后立刻以**退出码 2** 停下并打印 git 原文。
- 修复（PR #17）：`init_repo` / `New-FixtureRepo`、`add_commit` / `Add-Commit` 里的 `git init` / `add` / `commit` 失败即写 stderr 并退出 2（`.ps1` 新增 `Fail` 以对齐 `.sh` 的 `die`，否则两侧退出码一个是 1 一个是 2）。
- 归类：与 D1 / D9 / D11 同属"**失败不可见**"。任何吞 stderr 的采集或生成步骤，都可能把"生成失败"伪装成"断言失败"（假红）或"没有该信号"（假绿）。评审清单 `assets/templates/pr-review.md` B 组第 1 条即为此设。

## 被这次审计推翻的历史声明

1. `docs/VALIDATION.md` 曾称 "`.sh` 与 `.ps1` 输出一致（parity 确认）"——**已证伪**（见 D4/D3）。
2. `CHANGELOG.md` 曾称 4 个 eval 在 fixture 上各 5/5 通过——仓库内**没有 fixture、没有 runner、没有结果文件**，该声明不可复现。已把可复现的验证搬进 `evals/`。
3. `SKILL.md` 曾内联各 reference 的速查副本，导致 force push 禁止范围被窄化、受保护名单漏项、核心文档集三处不一致——**副本已删除，只留路由**。

## 回归清单（改完必须全绿）

```powershell
pwsh -NoProfile -File evals\run_evals.ps1            # 三层校验：严格 JSON + parity + 断言表
pwsh -NoProfile -File scripts\smoke_test.ps1 --repo . # 快速冒烟（双实现 + 负例）
bash evals\run_evals.sh                               # bash 侧（需 bash + python3）
```
