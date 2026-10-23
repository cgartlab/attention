# issue / PR 评论话术（四种，只在这四种情况下发言）

> 用于值守循环。评论属**对外可见、会通知他人**的远程写动作（`references/autonomy-and-safety.md` 动作档位表）——执行前需确认；内容必须遵守下面骨架，不许自由发挥。
> 通用纪律：不刷屏（同一结论只发一次）、不邀功（不写"我已完美修复"）、不替代修复（能修就先修，别用评论当交付）、中文大白话、命令与路径用代码格式。

## 1. 进度更新（只在阶段变化时，且是**编辑同一条**评论）

```markdown
<!-- attention:progress -->
{"stage":"review","branch":"fix/123-timeout","pr":42,"verified_sha":"3fca424","updated":"2026-10-22T21:40:00+08:00"}

**进度**：已定位为 `scripts/foo.sh` 的超时未设上界，正在改；PR #42 的回归还差 pwsh 侧未跑。
下一步：跑完两侧回归 → 贴计数 → 请求评审。
```

- ❌ 不写"我还活着""正在处理中"这类无信息量的更新。
- ❌ 不为同一阶段重复发评论（改同一条）。

## 2. 阻塞回复（修不了，但不是方向错误）

```markdown
**卡住了：缺运行环境，不是代码问题**

我在 PR #42 上验证时卡在：`pwsh` 未安装（`pwsh: command not found`），因此 `.ps1` 侧回归跑不了。

已确认的部分：
- bash 侧回归：`557 passed / 0 failed / 557`
- 冒烟：`10 passed / 0 failed`

需要谁做什么：装上 PowerShell 7 后，我这边可以继续补 pwsh 侧证据并推进合并。
在此之前我不会合并（L1 客观信号不完整）。
```
必须包含：卡点是什么、**证据**（命令+输出）、已确认的部分、需要谁做什么、当前判定（`BLOCKED`）。

## 3. 关闭理由（先评论，后关闭；顺序不可逆）

```markdown
**关闭理由：改动已在 main 上，无需重复合并**

判据：`git diff main <head>` 输出为空——本 PR 的改动集已完全包含在 `c4be1a8` 里（由 #16 squash 合并进来的）。
证据：
```
$ git diff --stat main fix/xyz
(空)
```

如判断有误请直接 reopen 并在下面说明，我再继续。
```
必须包含：判据（对应 `judgment-criteria.md` §关闭判据 的一行）、可复核的命令与输出、一句"如判断有误请 reopen"。

## 4. 合并证据（合并前最后一次评论：把"为什么可以合"钉死）

```markdown
**合并依据**

- L1 客观信号：CI `linux/bash` ✅、`linux/pwsh` ✅（run 39799702710）；`mergeable=MERGEABLE`；分支未落后
- L2 内容门：`pr-review.md` A–F 全过；断言零放宽（`script-assertions.json` 只有新增）；文档数字已同步
- L3 授权门：本轮对话已授权"非 UI 可直接合"；`ui_touched=none`
- 实跑：bash 557/557、pwsh 557/557、冒烟 10/10（worktree 隔离目录，SHA `3fca424`）

合并方式：squash；源分支随后带 lease 删除。
```
必须包含：四层逐条的**事实**（不是"已检查"），以及 UI 判定结论。强 UI 时这条评论改成"等人工确认"版本，并内联截图。

## 强 UI 时专用（替代第 4 种，且不合并）

```markdown
**视觉改动，等你确认（我不合并）**

改前 / 改后（同一 SHA `abc1234`）：
| 改前 | 改后 |
|---|---|
| ![before](https://raw.githubusercontent.com/<owner>/<repo>/attention/evidence-pr-42/docs/evidence/pr-42/before-1440.png) | ![after](https://raw.githubusercontent.com/<owner>/<repo>/attention/evidence-pr-42/docs/evidence/pr-42/after-1440.png) |

覆盖：1440×900 与 390×844；浅色/深色各一张，共 4 张。
`ui_touched=strong`（命中 `assets/**`）→ 按规则**禁止自动合并**，请你确认后自行点合并。
```
