# 立正Skill 通用化开发计划

> 目标：让立正成为**任意 harness / Agent 环境**都能用的 Git 项目巡检与修复 skill——不绑定某一操作系统、某一 shell、某一 harness。
> 状态：v0.1.0（pwsh 脚本，已在 Windows/DSH 环境验证）；本计划目标是跨 harness 通用化（版本号贯穿保持 0.1.0，升 1.0 由用户定）。

## 进度（截至本轮）

- **P1 脚本解耦** ✅ 完成：bash(.sh) + pwsh(.ps1) 双实现 + `scan-recipes.md` 契约 + Phase 0 shell 探测；**bash 已在 git-bash 验证**（发现 `C:\Program Files\Git\bin\bash.exe`，5/5 smoke + parity）。
- **P2 Agent Skills 对齐** ✅ 完成（文档/徽章/frontmatter）；安装验证（`npx skills add`）待推送 GitHub（用户暂不建远程）。
- **P3 无脚本回退 + 依赖最小化** ✅ 完成。
- **P4 跨 harness evals** ✅ 完成：bash + pwsh，5 脚本 parity 全过（见 `docs/VALIDATION.md`）。
- **P5 通用化打磨** 🔶 部分：多宿主 PR / missing_core_docs / AGENTS.md / smoke_test 已完成；i18n / CONTRIBUTING / 更多版本生态 待定。
- 关键里程碑：第 5 轮发现本环境自带 git-bash，使 P1 bash 验证与 P4 parity 成为可能；第 6 轮深度 parity 抓到 next_steps.sh 一个真 bug 并修。
## 一、调研发现（GitHub 类似 skill 与可移植性信号）

| 仓库 | 语言 | 教给立正什么 |
|------|------|--------------|
| [automazeio/ccpm](https://github.com/automazeio/ccpm) (8.4k★, Shell) | Shell | 已是 **Agent Skill**，明确"works with any Agent Skills–compatible harness: Claude Code, Codex, OpenCode, Factory, Amp, Cursor"；有 eval_score 徽章与"Skill Structure"约定 |
| [gviiisen/repo-context-ledger](https://github.com/gviiisen/repo-context-ledger) (105★, Python) | Python | 跨 agent（Codex/Claude/Cursor/Copilot/Grok）；用 `npx skills@latest add …` 安装；只读 Workflow Plan + 模糊意图先问清而非猜 |
| [toroleapinc/claude-brain](https://github.com/toroleapinc/claude-brain) (90★, Shell) | Shell | 自称 cross-platform，但平台仅 **Linux/macOS/WSL**——原生 Windows 不在其列；slash 命令（/brain-init）；git-based sync + 语义合并 |
| [mhattingpete/claude-skills-marketplace](https://github.com/mhattingpete/claude-skills-marketplace) (679★) | — | "Git automation + testing + code review"技能合集，与立正领域高度重叠，可对标 |
| [pcx-wave/vibe-skill](https://github.com/pcx-wave/vibe-skill) (118★, Shell) | Shell | 用 git diff 监督子任务——"git 作为验证手段"的同思路 |

**三条关键信号：**
1. **跨 harness 的标准答案是 Agent Skills**（agentskills.io / skills.sh，`npx skills add <owner>/<repo>`）。它定义了被 Claude Code、Codex、Cursor、OpenCode、Factory、Amp 共同识别的 skill 格式与安装机制。要做"任意 harness"，对齐它比自创格式高效得多。
2. **可移植脚本语言 = bash 或 python，绝非 PowerShell**。连"cross-platform"的 claude-brain 也只覆盖 Linux/macOS/WSL。立正当前的 .ps1 是可移植性硬伤。
3. **运行时依赖越少越好**：git（必需、跨平台）+ gh（可选、PR 用）。不要把 Python/Node/pwsh/bash 写进运行时硬依赖——它们只该出现在"一次性安装"或"可选增强"里。

## 二、现状差距分析

| 维度 | 现状 (v0.2.0) | 目标 (v1.0) | 差距 |
|------|---------------|-------------|------|
| 脚本语言 | 仅 PowerShell (.ps1) | 任意 harness 可跑 | bash 环境跑不了 .ps1；本 DSH/Windows 环境又无 bash |
| 格式/分发 | 自有目录约定 | Agent Skills 标准 | 未对齐 agentskills.io，无法 `npx skills add` |
| 运行时依赖 | 隐式 pwsh | git(+可选 gh) | pwsh 不是所有 harness 预装 |
| 覆盖 harness | DSH/Windows-pwsh 一处验证 | Claude Code/Codex/Cursor/OpenCode 等 | 仅 1 处验证 |
| 报告语言 | 已改大白话 (v0.2.0) | 保持 | ✅ 已达标 |
| 自动化测试 | 无 | （用户明确推迟） | 暂不纳入 |

## 三、可移植性架构设计（推荐方案）

核心思路：**采集逻辑与 shell 解耦**——同一份 git 命令清单，多种 shell 实现，Phase 0 探测后选路径。

### 脚本策略：双实现 + 共享配方 + 无脚本回退（三层）

1. **共享配方层**：把 5 个脚本的采集逻辑抽成一份 shell 无关的 *git 命令配方 + JSON 契约*（`references/scan-recipes.md`）。这份配方是"单一事实源"——所有实现都照它来，避免双份漂移。
2. **bash 实现层**（`scripts/*.sh`）：覆盖 Linux/macOS/WSL/Claude Code/Cursor 等 bash 可用的环境（主流）。
3. **pwsh 实现层**（`scripts/*.ps1`，保留现有）：覆盖 Windows/pwsh 环境（如本 DSH）。
4. **无脚本回退层**：当某 harness 既不能跑 .sh 也不能跑 .ps1（或只让模型直接执行命令）时，模型按 `references/scan-recipes.md` 的配方，用 harness 给的任何 shell **直接跑 git 命令**并自行组装 JSON。仅作兜底，非主路径。

> 为什么三层而非"重写成 bash 一把梭"：本 DSH/Windows 环境无 bash，纯 bash 重写会让立正在此处跑不起来；而立正正是在这里开发与验证的，不能自断验证环境。双实现 + 回退，覆盖最广。

### Phase 0 增强：运行时探测
在现有前置探测里加：
- **shell 探测**：bash 可用？→ 优先 `.sh`；否则 pwsh 可用？→ 用 `.ps1`；否则 → 无脚本回退。
- **依赖复核**：git 必需（缺则停止说明）；gh 可选（缺则 PR 降级为就绪产物）。
- 把"运行时只依赖 git(+可选 gh)，无 Python/Node 强制"写进 `references/environment-and-prereqs.md`。

### 分发策略：对齐 Agent Skills
- 按 agentskills.io / skills.sh 规范整理目录与 frontmatter（调研其确切约定后适配，**保留 name=attention**）。
- README 提供 `npx skills add <owner>/attention` 安装路径（Node 仅一次性安装用，非运行时）。
- 加 agentskills.io 兼容徽章。

## 四、分阶段路线图

### Phase P1 — 脚本解耦（shell 双实现）
- **任务**：抽 `references/scan-recipes.md`（5 脚本的 git 命令配方 + JSON 契约）；照配方写 `scripts/*.sh`（与 .ps1 同契约）；Phase 0 加 shell 探测与选择。
- **产出**：`references/scan-recipes.md`；`scripts/*.sh`；更新 `references/environment-and-prereqs.md`。
- **验收**：bash 侧（Linux/macOS/WSL/Claude Code 之一）与 pwsh 侧（本 DSH）跑同一套 evals，JSON 输出一致，断言全过。
- **风险/缓解**：双份维护 → 共享配方清单是单一事实源，实现照抄。

### Phase P2 — Agent Skills 标准对齐
- **任务**：调研 agentskills.io/skills.sh 的 frontmatter、目录、安装机制；按规范适配 attention 结构（**保留 name**）；README 加安装说明与徽章。
- **产出**：合规目录/frontmatter；README 安装段；agentskills.io 徽章。
- **验收**：`npx skills add <owner>/attention` 能在至少 2 个兼容 harness 安装并被触发。
- **注意**：Node 仅安装时用；运行时不依赖。

### Phase P3 — 无脚本回退 + 依赖最小化
- **任务**：写无脚本回退用法（模型按 `scan-recipes.md` 直接跑 git）；审计所有脚本/引用，确保无 OS/shell-profile 隐式假设（已 -NoProfile 规避 PSReadLine 等）。
- **产出**：`references/scan-recipes.md` 含"无脚本怎么用"段；`environment-and-prereqs.md` 明确依赖边界。
- **验收**：在"仅 git+gh、无脚本运行时"假设下，模型能手动采集并产出与脚本一致的判断；缺 gh 时降级为 PR 就绪产物。

### Phase P4 — 跨 harness evals 验证
- **任务**：在 ≥2 个不同 harness（本 DSH/pwsh + 一个 bash 类）跑全套 evals，iteration-2 benchmark。
- **产出**：`attention-workspace/iteration-2/` benchmark。
- **验收**：4 evals 在两个 harness 都过断言。
- **注**：本 env subagent 不可用，bash 侧 evals 在那侧环境跑。

### Phase P5 — 通用化打磨
- 报告/文档双语（中/英可切换，对标 claude-brain/repo-context-ledger 的 README.zh）。
- 版本生态补全（已覆盖 node/rust/python/jvm/dotnet/ruby；补 go.mod、helm Chart 等）。
- PR 多宿主：GitHub(gh) 全功能；GitLab(glab)/Bitbucket/Gitea 降级为就绪产物。
- CHANGELOG/release 流程固化。

## 五、明确推迟（用户已指示）

- **自动化测试 / CI**：用户明确"自动化也是之后的事情"——P4 的 evals 仍是手动/半自动，不引入 CI。
- **建立远程**：用户明确"不着急建立远程"——P2 的 `npx skills add` 路径先设计好，实际推送待用户点头。

## 六、风险与权衡

| 风险 | 权衡/缓解 |
|------|-----------|
| 双脚本维护成本 | 共享 `scan-recipes.md` 为单一事实源；.sh/.ps1 照抄 |
| Agent Skills 标准仍在演进 | 跟踪 agentskills.io 规范；保持向前兼容 |
| 无脚本回退失去黑盒确定性 | 仅作兜底；主路径仍是脚本 |
| 跨 harness evals 受 subagent 可用性限制 | 在能跑的环境跑；本 env 用父代理自跑适配 |
| bash 在原生 Windows 缺失 | pwsh 实现层覆盖；回退层兜底 |

## 七、版本策略与里程碑

**版本策略**：技能尚不完善，贯穿 P1–P5 **版本号保持 0.1.0**，不随阶段递增。阶段产出记入 CHANGELOG `[Unreleased]`，不切版本号。是否升至 1.0.0 由用户在 P5 完成后决定，不在本计划内自动切。

**阶段里程碑（不绑版本号）**：
- P1 完成 — bash+pwsh 双实现，shell 探测。
- P2 完成 — Agent Skills 对齐，可 `npx skills add`。
- P3 完成 — 无脚本回退 + 依赖最小化。
- P4 完成 — ≥2 harness evals 通过。
- P5 完成 — 通用化打磨（双语、版本生态补全、多宿主 PR）。


---

# 附：P6 质量加固（2026-09-30）

> 触发：一次针对性质量审计查出 11 类**实测**缺陷（详见 `docs/QUALITY-AUDIT.md`）。P6 的目标不是加功能，而是**让"承诺"与"机器实际行为"对齐**，并把验证从声明升级为可复现。

## 八、P6 阶段

- **度量先行**：新增 `evals/`（现为 21 个 fixture + 83 条断言 + 双实现 runner，三层校验：严格 JSON / parity / 断言表）。**先建度量再改代码**——此前的 3 类缺陷之所以能长期存活，正是因为没有任何断言能发现它们。
- **契约硬化**：`scan-recipes.md` 确立四条元规则（路径形态、`null` vs `[]`、失败必须可见、字段名即语义），并新增 `unpushed_branches`、`remote_reachable`、`release_signals`、`monorepo_mode`/`packages`、`remote_url_masked`、`gh_query_state` 等字段；`docs_needing_update` 更名为 `docs_mentioning_changes`（旧名会诱导"文档无需更新"的误读）。
- **脚本成对修复**：16 项（`--repo` 校验、漏值死循环、`.sh` 非法 JSON、`release_involved` 恒 false、parity 漂移、颜色注入、`.gitignore` 尊重、未跟踪 TODO、宿主解析与脱敏等），`.sh` 与 `.ps1` 同步。
- **SKILL.md 去冗余 + 补缺口**：删除全部内联"速查副本"（历次硬伤的共同根因），只留路由 + 三条铁律；新增 **Phase 2.5 意图分流**（干净态也可能有交付任务；该半阶段后续已并入 Phase 2 的统一"状态 × 意图"分流表，不再单列）、**工作分支步骤**、**非交互环境 fallback**（无 `ask_user_question` 时停下等确认，禁止自批）、幂等规则、报告可发布判定。
- **文档一致性清扫**：每条规则只在**一个**文件里完整定义，其余只写路由；修掉"远端已无对应 ref"这类**逻辑上不可判定**的规则（`fetch --prune` 后恒假）；补 `version-file-inventory.md`（跨生态版本文件与 lockfile 详表）、`changelog-sections.md`（分节表 + `hidden`/`skip` 语义 + 溯源守则）、`plan-table.md`（计划表模板）。
- **打包层**：`description` 补英文触发句（英文 harness 触发面）、补 `compatibility` 字段。

## 九、P6 的验收（与本计划其余阶段的差异）

P1–P5 的验收多为"在某环境跑通一次"，P6 改为**可重复执行的断言**：

```powershell
pwsh -NoProfile -File evals/run_evals.ps1     # 三层校验，红→绿有据
pwsh -NoProfile -File scripts/smoke_test.ps1 --repo .
```

并明确记录**不可测边界**（`docs/VALIDATION.md`）：远程操作、真实 GitHub PR、`npx skills add` 安装链路在本开发环境不可验证——**不把"跑不了"写成"通过"**。

## 十、P6 仍未覆盖（留给后续）

- CI（依赖远程仓库；用户当前明确不建远程）。
- 跨 harness 触发率评测（需要英文环境与多 harness，本环境只能做 DSH 侧）。
- `docs/ecosystem-survey.md` 与 `docs/ecosystem-research/` 里的行业对照结论**尚未全部落地**（如守门工具链的规则集思路、分支清理工具的边界实验）——本阶段只吸收了与"版本/CHANGELOG/分支剪枝"直接相关的部分。
