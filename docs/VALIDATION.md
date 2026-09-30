# 跨 harness 验证记录

> 本文档只记**可复现**的验证：给出命令、环境与结果。历史版本曾包含"parity 已确认"一类**无法复现**的声明，已在 2026-09-30 的 P6 中删除（依据见 `docs/QUALITY-AUDIT.md`）。**不可测的部分单列在第 5 节，不写成"通过"。**

## 0. 怎么跑

```powershell
# 脚本层三层校验（严格 JSON + .sh/.ps1 逐字段 parity + 断言表）
pwsh -NoProfile -File evals/run_evals.ps1 -FixturesDir "$env:TEMP\attention-evals-a"
bash evals/run_evals.sh --fixtures-dir "$env:TEMP/attention-evals-b"      # bash 侧（需 python 做严格 JSON）

# 快速冒烟（双实现 + 负例断言）
pwsh -NoProfile -File scripts/smoke_test.ps1 --repo .
bash scripts/smoke_test.sh --repo .
```

结果文件落在 `evals/results/<时间戳>-<short-sha>.json`（入库，作为证据）。**并发跑多个 runner 时必须各给一个 fixtures 目录**，否则会互相删除重建 fixture 产生假失败。

## 1. 验证环境（2026-09-30）

| 组件 | 版本/位置 |
|---|---|
| OS | Windows（仓库位于 D: 盘 **exFAT**——不支持硬链接，harness 的原子写工具在此必然失败，需改用普通写入） |
| pwsh | PowerShell 7.6.5 |
| bash | GNU bash 5.3.15（Git for Windows，`C:\Program Files\Git\bin\bash.exe`） |
| git | 2.55.0.windows.3 |
| node | v26.7.0（fixture 里的测试用） |
| python | `%APPDATA%\uv\python\cpython-3.12…\python.exe`（**本机 `python3`/`python` 是 Microsoft Store 别名存根，执行即失败**；bash runner 会自动扫描并用 `ATTENTION_EVAL_PYTHON` 覆盖） |
| gh | 2.99.0（**已登录真实账号**——因此本文中一切 gh 写操作都是被刻意禁止的，不是没试） |

## 2. 脚本层回归结果

| 校验 | 命令 | 结果 |
|---|---|---|
| 三层校验（pwsh 侧 runner） | `pwsh -NoProfile -File evals/run_evals.ps1` | **493 passed / 0 failed / 493** |
| 三层校验（bash 侧 runner，独立实现） | `bash evals/run_evals.sh` | **493 passed / 0 failed / 493** |
| 快速冒烟（双实现 + 负例） | `pwsh …/smoke_test.ps1 --repo .` | 5 passed / 0 failed |
| 快速冒烟（bash） | `bash …/smoke_test.sh --repo .` | 5 passed / 0 failed |
| `--repo` 无效 | `… --repo <不存在>` | 两实现均 `[FAIL] --repo path not found`、退出 1（**不再静默分析当前目录**） |

**三层校验**：① 严格 JSON——`System.Text.Json` / python `json.load` 解析，拒绝字符串内裸控制字符；② parity——同 fixture、同参数下 `.sh` 与 `.ps1` 的**字段集与逐字段值**必须一致（路径形态、数组顺序、`null` vs `[]` 全算差异）；③ 断言表——`evals/script-assertions.json`（65 条）。

**改前基线（同一套断言、原始脚本）**：用 `git worktree add --detach <path> HEAD` 取未修改的脚本，把 `evals/` 复制进去，跑**同一个 runner 与同一份断言表**：

| 状态 | 结果 | 证据文件 |
|---|---|---|
| 改前（原始 HEAD `ef75840`） | 260 passed / **106 failed** / 366 | `evals/results/20260930-233235-ef75840-BASELINE-head.json` |
| 改后（P6 完成时） | **366 passed / 0 failed** / 366 | `evals/results/20260930-230925-ef75840.json`（pwsh 侧）、`…231506…`（bash 侧） |

失败项与 `docs/QUALITY-AUDIT.md` 的缺陷清单一一对应（严格 JSON、parity 路径形态、缺失新字段、`release_violved` 两实现取值不同、`vendor/` 泄漏、宿主误判、颜色注入、`--repo` 无效时返回当前仓库数据、漏值挂死、`protected` 重复等）。这是本技能第一次有**同一批断言**支撑的"红→绿"证据。

### 第二轮（P0/P1 落地：基准分离、Cargo 继承、vendor 排除、gh rules、lease）

| 阶段 | 结果 | 说明 |
|---|---|---|
| 只加 fixture + 断言（先红） | 455 passed / **36 failed** / 491 | 36 = 18 条新断言 × 2 实现；F1–F14 既有断言无一变红（未削弱任何一条） |
| 批次 A（`branch_cleanup_audit`） | 479 / **12** / 491 | 本地/远程合并基准分离 + 基准守卫 + `cleanup.protect` + `gh rules` |
| 终态（+ 版本改造、`tip_sha`、端点纠偏） | **493 / 0 / 493** | pwsh 与 bash 两套 runner 结果一致 |

本轮修正的是一处**由 P6 引入的回归**：P6 把"本地合并判定"也改用了 `origin/<默认分支>`，导致"本地已合并、尚未推送"的分支被**漏报成空集**（假阴性）。现在本地用本地默认分支、远程用 `origin/<默认分支>` 并加基准守卫（`remote_base_unverified` + 警告）。F18/F19 覆盖这两个方向。

**本轮的实测性证据（非文档推断）**：
- `gh` 端点纠偏：`GET /rulesets` 列表**不含** `rules`/`conditions`（实测只回 `id/name/target/enforcement/source/node_id/created_at/updated_at/_links`）；正确端点是 `GET /repos/{o}/{r}/rules/branches/{branch}`，实测 `any(.[]; .type=="deletion")` 在 `nodejs/node` 的 `main` 上为 true；**分支不存在时返回 `[]` + HTTP 200**（陷阱）。活体端到端：临时仓库 remote 指向真实 `nodejs/node`，两套实现同形输出 `protected_from_rulesets=["main","v22.x"]`。
- 远程删除必须带 lease：`git push origin --force-with-lease=<branch>:<sha> --delete <branch>`；**不带 lease 的删除会静默丢掉确认窗口内他人推送的提交**（已用裸仓库 + 两个 clone 复现数据丢失）。
- patch-id 口径纠偏：survey 的"topic 整段 vs main 逐 commit"**只对 squash 有效**，对多 commit rebase 永远匹配不上（实测交集为空，改成两侧逐 commit 后全部命中）；另实测 **cherry-pick 必然误报**，这才是"只报告不删"的真正理由。详见 `docs/research/p2-verification.md`。
- `git branch -d` 与 `-D` 都拒绝删除被 worktree 检出的分支（故该检查属报告层改进，不是安全修复）。

**实现坑（供后续维护者）**：pwsh 中 `function f { return ,$out }` 的调用处若再套 `@(...)`，会得到"只含一个数组元素"的嵌套数组（`Count=1`，元素被串成 `System.Object[]`），曾让 Cargo members 解析静默变空。

## 3. 断言覆盖的边界

| fixture | 覆盖 |
|---|---|
| F1 非 git 目录 / F2 零提交仓库 / F3 detached HEAD | 负例、`head_short=null`、根提交回退 |
| F4 敌意命名 + CRLF / F8 仅 CRLF 版本文件 | 严格 JSON、路径形态、控制字符转义 |
| F5 脏态 WIP + 测试失败 | 状态字段、未跟踪文件里的 TODO |
| F6 干净 + 在轨 + 已合并/未合并分支 | 剪枝候选、陈旧阈值、`unpushed_branches` |
| F7 多生态版本不一致 / F9 依赖 version 在前 / F10 被忽略目录内的版本文件 | `consistent`、顶层 version、`.gitignore` 尊重 |
| F11 宿主解析 + token 脱敏 | 按主机名判定、`remote_url_masked`、输出不含凭据 |
| F12 发布信号 | `chore(release)` / `feat!` / `fix:` / `BREAKING CHANGE:` footer |
| F13 monorepo / F14 颜色注入 | `monorepo_mode`/`packages`、`color.ui=always` 下候选不漏 |
| NEG-PATH / NEG-FILE / NEG-NOVALUE | `--repo` 无效与漏值 |

## 4. 行为层 eval（需 agent 执行）

4 个行为用例（`evals/evals.json`：clean-sync / dirty-wip-fix / version-bump-release / non-github-fallback）曾用子代理各跑一轮（独立 fixture、互不共享目录）。结论：**14 条断言满足 13 条**，唯一未满足的是"在 GitHub 上创建 PR"——本环境无法建立可用远程，实际交付到了"PR/MR 就绪产物 + 手动指引"（与 skill 的降级设计一致）。

**P6 修复后的定点复测（eval-3 场景：干净树 + 版本不一致 + 用户明示发版/提 PR）**：用更新后的 skill 重跑同一场景（独立 fixture），结论——

- Phase 2 判为**干净态**；**Phase 2.5 意图分流**按 `SKILL.md` 的表格与示例把请求导向 Phase 3B 的门槛与交付步骤（修复前，这一请求在字面流程里无家可归）。
- **工作分支步骤生效**：在受保护名单内的 `main` 上先 `git switch -c chore/align-version-1.1.0` 再提交（修复前，脏态路径根本没有这一步，agent 只能自行发明）。
- **版本门槛拦住了，但拦它的是 `consistent=false` 而非信号层**：该场景下 `release_signals=[]`、`release_involved=false`（版本改动已在提交里、工作树干净 → 变更集为空 → 信号层按构造为空）。子代理如实指出"若只看 `release_signals`/`release_involved` 会误判为不涉及 release"——这正是此前门槛失效的形态；现在由 `judgment-criteria.md` 的门槛层（"版本承载文件之间已不一致 → 需要 bump"）加上用户明示意图兜住。
- 该轮为 delegated 执行：环境约定"确认视为已批准"，与 skill 的非交互硬规则（写出计划并停下、不得自批）冲突，子代理按环境指令执行并**显式记录了这次偏离**——说明该硬规则已被读到，但它在"上层指令要求继续"与"skill 要求停下"之间仍需要人裁决。
**两条方法论限制（必须一并记录）**：

1. **"无 skill 基线"在本环境无法强制**：skill 已安装在 `~/.dsh/skills/attention` 并被自动发现，某个"基线"子代理实际加载并使用了它。因此本文不提供可比的 with/without 基准数字。
2. **任何远程步骤不可测**：本地路径传输要经 shell、`git://` 的 receive-pack 会挂死——所以 fetch/pull/push/PR/MR 只验证到"失败被如实记录并降级"，未验证到"成功"。

## 5. 未被验证的部分（诚实清单）

- 任何远程操作的成功路径（push / 删远程分支 / PR/MR 创建 / 推 tag）。
- `npx skills add cgartlab/attention` 安装链路（需先推送仓库）。
- 跨 harness 的**触发率**（本环境只能观察到 DSH 的 skill 目录能正常加载）。
- Cargo workspace 成员级版本继承（成员写 `version.workspace = true` 时无字面值可抓；目前只保证根 `[workspace.package].version` 被计入，无 fixture 覆盖）。
- CI（用户当前明确不建远程，故不做）。
