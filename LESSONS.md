# LESSONS — attention

> 立正 Skill（attention）：任意 Git 项目的"站好队"巡检与修复 Agent Skill；`scripts/` 下 `.sh` 与 `.ps1` 双实现，JSON 契约 + `evals/` 三层校验。
> 本仓库从真实失误沉淀的「教训→规则」清单。**会话开始先全文阅读并遵循其中所有规则**；出现新失误按 §维护 追加。
> 权威依据：Anthropic Claude Code memory/best practices（<200 行、具体可验证、第二次犯同样错即写入）；社区 lessons.md 惯例（Boris Cherny，Anthropic）。
> 来源：本仓库 AGENTS.md 的工作约定 / 改本仓库时 / evals 目录 + 已验证 fix 提交；预填为种子，后续由 Agent 在真实工作中增长。

## 维护
- **触发**：用户纠正 / Agent 自查到的失误 / 非显而易见的 gotcha。
- **格式**：`### <主题>` 下，每条 = 失误（具体场景）→ 规则（最小可执行指令），一行可验证。
- **只记项目特有、不可从代码推断的**；通用最佳实践不写；含糊措辞（"小心""注意"）删掉。
- **重复出现** → 升级进 `AGENTS.md` 硬规则；**月度审阅**裁剪过期项；目标 < 200 行。

## 双实现成对

- 失误：只改 `.sh` 不改 `.ps1`，两侧漂移出 16 项缺陷 → 规则：改脚本必须成对改 `.sh` 与 `.ps1`（commit 8fd551a）
- 失误：ps1 的 worktree 扫描恒空（`Git1` 只返回首行）→ 规则：需要多行输出时用 `GitOut`（commit eaf20cf）
- 失误：shell 选择只看"文件在不在" → 规则：按能否执行探测选 shell，不是看文件存在（见 AGENTS.md「工作约定」）

## 契约同步

- 失误：改了契约只改一处 → 规则：改契约要四处同步——`references/scan-recipes.md` + `.sh` + `.ps1` + `evals/script-assertions.json`，只改一处即为漂移（见 AGENTS.md「改本仓库时」）
- 失误：契约里的 null 语义与路径约定没硬化 → 规则：契约必须可判定，含 null 语义与路径规范（commit 3aca3ec）
- 失误：速查副本里残留旧规则，被当成现行答案 → 规则：`SKILL.md` 只做路由 + 三条铁律，不复述 `references/` 的规则（见 AGENTS.md「改本仓库时」）
- 失误：加规则只加不减，元规则淹没工作流 → 规则：加一条必须指出可删/可合并的一条；核心理念 + 铁律净增长 ≤ 0（见 AGENTS.md「改本仓库时」）

## 评测与 fixture

- 失误：fixture 生成在仓库内，"非 git 目录"负例失效 → 规则：fixture 默认落在系统临时目录（见 AGENTS.md「evals/ 目录」）
- 失误：并发跑多个 runner，互相删除重建 fixture 产生假失败 → 规则：用 `-FixturesDir`／`--out-dir` 指定不同目录（见 AGENTS.md「evals/ 目录」）
- 失误：为了让 eval 变绿而放宽断言 → 规则：改断言等于改评测基准，必须同时说明理由，不得为了变绿而放宽（见 AGENTS.md「evals/ 目录」）
- 失误：TODO/扫自己命中 `evals/` 测试数据与调研目录 → 规则：扫描必须排除 `evals/` 与调研目录（commit 0eb698b）
- 失误：TODO grep 命中扫描器自身源码 → 规则：排除 `.ps1` 与 `.sh` 脚本自身（commit ea1f6a5、622ffad）
- 失误：`gh_authed` 断言 flake → 规则：外部 API 状态要做基准分离与守卫（commit d491a48、6b9da32）
- 失误：fixture 生成里的 `git init`/`add`/`commit` 失败被 `>/dev/null 2>&1` 吞掉，21 个 fixture 悄悄退化成非 git 目录，回归报 152 条"字段不存在"假失败 → 规则：fixture 生成里的 git 写操作失败必须 `die`/`throw` 并带 git 原始 stderr（退出 2），不得 exit 0 放过
- 失误：断言表涨到 83 条，四份文档还写着 81 条 → 规则：改动 `script-assertions.json` 时同步 `AGENTS.md`/`README.md`/`docs/DEVELOPMENT-PLAN.md`/`docs/VALIDATION.md` 里的条数与 checks 总数
- 失误：CI 负例与产物打包说明和 GitHub 官方行为不符 → 规则：调研结论必须对照官方文档，不照抄假设（commit 840a38f）
- 失误：`.github/workflows/ci.yml` 写好后**从未真正跑过**（仓库私有 + Actions 计费未启动），转公开后首次真跑即挂：`$env:TEMP` 在 Linux 上为空，fixtures 目录落到 `/attention-evals-ci` 被拒 → 规则：写了 CI 不等于 CI 能跑，必须有**一次真实的绿色 run** 才能声称"已适配"；临时目录一律用 runner 提供的跨平台变量（`RUNNER_TEMP` / `${{ runner.temp }}`）
- 失误：`.ps1` 缺 `fixtures.sh` 的根目录守卫（`.ps1` 会无条件 `Remove-Item -Recurse`）→ 规则：两面实现凡有"删除/重建目录"的分支，两侧都要有等价的路径守卫，不能只在一侧补

## 安全与不可逆动作

- 失误：无交互环境下自批了变更计划 → 规则：无 `ask_user_question` 时把计划写出来并停下等确认，不得自批（见 AGENTS.md「工作约定」）
- 失误：把"没查成"写成"没有" → 规则：写 `null` + `warnings[]`，不得写成"没有"（见 AGENTS.md「工作约定」）
- 失误：远端不可逆动作直接执行 → 规则：push / 删远程分支 / 开 PR / 推 tag 需最终确认；永不 force push、不删未合并或受保护分支、**永不删默认分支**（见 AGENTS.md「工作约定」）
- 失误：让采集脚本自己提交/推送/删分支 → 规则：脚本只做只读采集，所有变更动作由 Agent 按 `SKILL.md` 显式执行（见 AGENTS.md「工作约定」）

## 报告与验证

- 失误：收尾报告里堆 JSON 键与命令串 → 规则：主叙事面向项目作者（含新手），技术信号另放末尾"📋 技术细节"小节（见 AGENTS.md「工作约定」）
- 失误：把 `verify` 写成空转检查 → 规则：自检要指向真正会失败的检查（`smoke_test`），不要写 no-op（commit b96ff07）
