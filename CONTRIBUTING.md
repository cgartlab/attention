# Contributing

欢迎贡献。这个仓库是**立正（attention）** Agent Skill：一个"任意 Git 项目巡检与修复"的技能。

## 先读这三份

1. `SKILL.md` —— 工作流（只做**路由 + 流程**，规则细则都在 references）
2. `AGENTS.md` —— 机器面约定（提交规约、成对改脚本、契约三处同步、加规则要配对减规则、自检命令）
3. `docs/VALIDATION.md` —— 怎么验证、哪些**不可测**（别把"跑不了"写成"通过"）

## 提交前必须绿的两件事

```powershell
pwsh -NoProfile -File evals/run_evals.ps1 -FixturesDir "$env:TEMP\attention-evals-dev"
pwsh -NoProfile -File scripts/smoke_test.ps1 --repo .
```

bash 侧（需要 python 做严格 JSON 校验）：

```bash
bash evals/run_evals.sh --fixtures-dir "$TMPDIR/attention-evals-dev"
bash scripts/smoke_test.sh --repo .
```

发布前另跑 `scripts/release_preflight.ps1|sh`（只读的发布闸门）。

## 硬规矩（违反会被要求返工）

- **提交信息用 conventional commits**（`feat`/`fix`/`docs`/`chore`/`test`/`refactor`），body 讲 **WHY**（diff 已经说明 WHAT）。
- **改脚本要成对**：`.sh` 与 `.ps1` 必须同步改，行为逐字段一致（`all-parity` 是硬断言）。
- **改契约要四处同步**：`references/scan-recipes.md`（单一事实源）+ `.sh` + `.ps1` + `evals/script-assertions.json` 的断言。
- **不要在 `SKILL.md` 里复述 references 的规则**：SKILL.md 只做路由 + 流程 + 六条元规则（核心理念 3 + 铁律 3）。
- **加规则要配对减规则**：加一条规则必须指出哪条可删或合并；`SKILL.md` 元规则净增长必须 ≤ 0。
- **不得削弱断言**：`evals/script-assertions.json` 是评测基准；只允许新增，改既有断言必须在 PR 里说明理由。
- **不许编造**：文档/版本/建议只反映真实 diff 与真实信号；"没查成"写成"没查成"（`null` + `warnings[]`），不得写成"没有"。

## 新增一个采集能力时

1. 先写 fixture + 断言（此时应当是**红**的），把它跑一遍记录失败数；
2. 实现两套脚本，把它们跑到**绿**；
3. 同步契约、`--help` 文本与 `docs/VALIDATION.md`；
4. PR 描述里贴出"红 → 绿"的前后数字。

## PR 检查清单

- [ ] `run_evals`（两套 runner）与 `smoke_test` 全绿
- [ ] 断言只增不减（或已说明为何必须改）
- [ ] `.sh` / `.ps1` 成对且 parity 绿
- [ ] 契约/docs 已同步（含 `CHANGELOG.md` 的 `[Unreleased]`）
- [ ] 提交信息符合 conventional commits，body 讲清 WHY
