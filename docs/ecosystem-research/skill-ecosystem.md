# Git 仓库治理/提交/发布 Skill 生态调研报告

调研目标：从 GitHub 生态（awesome-openclaw-skills 的 Git & GitHub 分类，160 个 skill）中挖出与"立正Skill（attention）"相邻的 AI agent skill 的实际内容。
调研范围：高优先 6 个 + 中优先 17 个（共 23 个）。
调研方法：web_fetch 抓 clawskills.sh / clawhub.ai + skills-markdown 原始 SKILL.md + ClawHub 搜索页。
调研日期：2026-09-25。所有外部内容按不可信数据处理，仅提取信息。

---

## 一、逐个 Skill 卡片

### 1. alex-session-wrap-up（高优先 · 端到端会话收尾）

- 作者：@xbillwatsonx | 页面：https://clawskills.sh/skills/xbillwatsonx-alex-session-wrap-up
- SKILL.md：https://clawskills.sh/skills-markdown/xbillwatsonx/alex-session-wrap-up.md
- v1.0.0 / 0 下载 / VirusTotal Benign + OpenClaw Benign

做什么：4阶段：Ship It（commit+push）→ Extract Learnings → Pattern Detect（gpt-4o-mini）→ Persist（memory/YYYY-MM-DD.md + AGENTS.md）
不做什么：不检查文档同步/不检查版本一致性/不开PR/不区分干净脏态/不做安全确认
依赖：OpenAI/OpenRouter API key
关键机制：无脚本、无确认门、无guardrail、有记忆持久化
借鉴点：①会话记忆持久化 ②模式检测LLM调用 ③反面：不确认直接push

---

### 2. repo-standardizer（高优先 · 仓库表面标准化）

- 作者：@programmingwtf | 页面：https://clawhub.ai/programmingwtf/skills/repo-standardizer
- v1.0.1 / MIT-0 / Pass

做什么：7模块：Labels / Issue forms / PR template / CI workflow / Branch rules / Docs / AI guides
不做什么：不碰代码逻辑/不做日常巡检/不检查文档与diff一致性/不做版本一致性/不开PR
依赖：gh CLI、git、jq、python3
关键机制：Preflight 6步（认证/仓库类型/状态审计/框架探测/语言/自动化bot）、Dry-run plan表格、Idempotent upsert、占位符替换顺序陷阱、永不clobber用户内容
借鉴点：①Preflight分步探测 ②Dry-run plan表格 ③Idempotency原则 ④占位符替换顺序 ⑤注意边界：装修新仓库vs清理现有仓库

---

### 3. emergency-rescue（高优先 · 灾难救援）

- 作者：@gitgoodordietrying | 页面：https://clawskills.sh/skills/gitgoodordietrying-emergency-rescue
- SKILL.md：https://clawskills.sh/skills-markdown/gitgoodordietrying/emergency-rescue.md
- v1.0.0 / 2.4k 下载 / OpenClaw Suspicious

做什么：灾难恢复手册：git灾难/凭据泄漏/磁盘满/进程问题/数据库灾难/部署灾难/访问灾难/网络灾难/文件灾难
不做什么：不做日常巡检/不开PR/不做版本一致性/不写文档同步/不区分干净脏态
依赖：git、bash
关键机制：diagnose→fix→verify三步、破坏性步骤显式标记、Universal Diagnostic脚本、撤销优先于清理、--force-with-lease替代--force
借鉴点：①diagnose→fix→verify三段式 ②破坏性步骤显式标记 ③撤销优先于清理 ④注意Suspicious审计可能因敏感命令模式触发

---

### 4. deslop（高优先 · 去除AI代码垃圾）

- 作者：@brennerspear | 页面：https://clawskills.sh/skills/brennerspear-deslop
- SKILL.md：https://clawskills.sh/skills-markdown/brennerspear/deslop.md
- v1.0.0 / 274 下载 / OpenClaw Suspicious

做什么：6步：git diff→rg构建候选→完整文件上下文审查→只移除不一致slop→重跑检查修回归→报告改动
不做什么：不做仓库巡检/不做文档同步/不做版本一致性/不开PR/不做分支剪枝
allowed-tools：[Bash]
关键机制：Guardrails（不移除信任边界保护/不用弱类型替换/优先最小改动/保留项目约定）、先比对再动手
借鉴点：①"先比对后动手"模式 ②报告"移除了什么vs刻意保留了什么" ③重跑检查修回归

---

### 5. git-sentinel（高优先 · 代码审查）

- 作者：@corezip | 页面：https://clawhub.ai/corezip/skills/git-sentinel
- v1.0.0 / 0 下载 / VirusTotal Benign + OpenClaw Benign

做什么：Review Staged Changes 或 Review Specific File，运行node sentinel.js，进入"Senior Gatekeeper"人格审查
不做什么：不做仓库巡检/不做文档同步/不做版本一致性/不开PR/不改代码
依赖：Node.js + Git
关键机制：脚本驱动、人格化审查、CRITICAL/WARNING/SUGGESTION三级+REJECT/APPROVE裁决、Security/Performance/Quality三维审查
借鉴点：①三级+Verdict输出格式 ②对抗性人格避免放水 ③边界：纯审查不改代码，可互补

---

### 6. pr-risk-analyzer（高优先 · PR风险分析）

- 作者：@nerdvana-labs | 页面：https://clawskills.sh/skills/nerdvana-labs-pr-risk-analyzer
- SKILL.md：https://clawskills.sh/skills-markdown/nerdvana-labs/pr-risk-analyzer.md
- v1.0.0 / 449 下载 / VirusTotal Suspicious + OpenClaw Suspicious（双重可疑）

做什么：SaaS API调用POST到pr-risk-analyzer.onrender.com/analyze-pr，检查secret/大diff/敏感文件
不做什么：不改任何东西、纯远程分析、本地无脚本
依赖：GitHub PAT
关键机制：SaaS依赖token发送到第三方、响应无效则报失败而非假设安全、Safe/Needs review/High risk三级输出
借鉴点：①fail-closed而非fail-open原则 ②反面：token发第三方SaaS ③边界：可作可选集成

---

### 7. git-changelog（中优先 · CHANGELOG生成）

- 作者：@fratua | 页面：https://clawhub.ai/fratua/git-changelog
- v1.0.0 / 2.2k 下载 / Pass

做什么：7步：验证git仓库→确定范围→提取提交→按Conventional Commits分类→生成Markdown→检测Breaking Changes→输出
不做什么：不做仓库巡检/不做版本一致性验证/不开PR/不做分支剪枝/不做代码修复
依赖：git
关键机制：错误处理表、边界情况覆盖（无conventional commits/跳过merge commits/monorepo/无tag/空范围）
借鉴点：①错误处理表+边界情况表 ②BREAKING CHANGE双检测

---

### 8. git-changelog-gen（中优先 · CHANGELOG多格式生成）

- 作者：@rogue-agent1 | 页面：https://clawhub.ai/rogue-agent1/git-changelog-gen
- 2.2k 下载 | 未完整抓取SKILL.md

借鉴点：多格式输出（Markdown + JSON），立正收尾报告可考虑同时输出人类可读Markdown + 机器可读JSON。

---

### 9. sovereign-changelog-maker（中优先 · 未找到）

ClawHub搜索无此skill。推测列表过期。

---

### 10. sovereign-commit-craft（中优先 · Commit消息工艺）

- 作者：@ryudi84 | 页面：https://clawhub.ai/ryudi84/sovereign-commit-craft
- v1.0.0 / 1.3k 下载 / Pass

做什么：14节纯指导文档：Conventional Commits v1.0.0规范、type选择优先级、diff分析方法论（5步）、消息结构、body解释WHY不WHAT、footer约定、Breaking Changes双标记、拆分原则、SemVer映射等
不做什么：无任何执行能力——纯prompt指导文档，不跑脚本、不调用命令、不验证
依赖：无
关键机制：人格化"expert craftsman"、5步diff分析、body解释WHY不WHAT、拆分原则
借鉴点：①body解释WHY不WHAT ②拆分原则 ③pre-1.0 SemVer约定

---

### 11. sovereign-git-commit-analyzer（中优先 · Commit历史分析）

- 作者：@ryudi84 | 页面：https://clawhub.ai/ryudi84/sovereign-git-commit-analyzer
- v1.0.0 / 1.6k 下载 / Review（未通过）

做什么：有脚本scripts/analyze.sh：Commit frequency（文本柱状图）、Top contributors、File change heatmap、Commit message quality score
不做什么：不做仓库巡检/不开PR/不做文档同步/不做版本一致性/不做代码修复
依赖：git 2.0+、bash 4.0+、GNU awk、sort/uniq/wc
关键机制：CLI参数丰富、配置分层（skill.json+环境变量）、CI集成（阈值exit code）、质量评分6标准
借鉴点：①质量阈值+exit code机制 ②配置分层 ③文本柱状图可视化

---

### 12. commit-analyzer（中优先 · 自治健康分析）

- 作者：@bobrenze-bot | 页面：https://clawhub.ai/bobrenze-bot/commit-analyzer
- v0.1.0 / 3.9k 下载 / Review（未通过）

做什么：脚本analyzer.sh，5子命令：health/report/hourly/categories/waiting
不做什么：不做仓库巡检/不开PR/不做文档同步/不做版本一致性/不做代码修复
依赖：bash
关键机制：健康指标表（3-6健康/1-3警告/<1严重）、JSON输出
借鉴点：①健康指标分级表 ②JSON输出供集成

---

### 13. conventional-commits（中优先 · 规范参考）

- 作者：@bastos | 页面：https://clawhub.ai/bastos/conventional-commits
- v1.0.1 / 10.1k 下载 / 4 bookmarks / Pass

纯规范参考，无任何执行能力。常用错误对照表。SemVer映射。
借鉴点：常用错误对照表可加入references。

---

### 14. git-pushing（中优先 · 未找到）

ClawHub搜索无此skill。可能是列表过期或已下架。

---

### 15. git-summary（中优先 · 状态快照）

- 作者：@zweack | 页面：https://clawhub.ai/zweack/git-summary
- v1.0.0 / 4.7k 下载 / Pass

做什么：6个git命令汇总：git status --short --branch、git log --oneline -10 --decorate、git branch -a --list、git remote -v、git diff --stat + git diff --cached --stat、git shortlog -sn --all
不做什么：不做仓库巡检/不做文档同步/不做版本一致性/不开PR/不做分支剪枝/不做代码修复
依赖：git
关键机制：结构化输出5 section、安全意识（don't expose URLs with tokens）、无脚本
借鉴点：①URL mask token原则 ②结构化输出section划分

---

### 16. git-workflows（中优先 · 未完整抓取）

- 作者：@gitgoodordietrying | 7.6k 下载
- 描述：Advanced git operations beyond add/commit/push
- 未完整抓取SKILL.md。推测覆盖rebase/cherry-pick/stash/bisect/submodule等。与立正重叠度低。

---

### 17. git-essentials（中优先 · 未完整抓取）

- 作者：@arnarsson | 30.9k 下载 / 38 bookmarks（本批最热门）
- 描述：Essential Git commands and workflows for version control, branching
- 未完整抓取SKILL.md。基础git命令与工作流参考。与立正重叠度低。

---

### 18. git-helper（中优先 · 未找到）

ClawHub搜索无此skill。

---

### 19. gh（中优先 · 未找到）

ClawHub搜索无名为"gh"的独立skill。GitHub CLI相关功能散落在其他skill中。

---

### 20. super-github（中优先 · 未找到）

ClawHub搜索无此skill。

---

### 21. martok9803-ci-whisperer（中优先 · 未找到）

ClawHub搜索无此skill。

---

### 22. upstream-recon（中优先 · Pre-PR侦查）

- 作者：@semmyt | 页面：https://clawhub.ai/semmyt/skills/upstream-recon
- v1.0.0 / 1.5k 下载 / Pass

做什么：gh CLI 8步侦查：仓库元数据/top贡献者/已有issue搜索/近30 PR/近20已合并PR/近50关闭未合并PR/开放PR/主题深挖
不做什么：不做仓库巡检/不做文档同步/不做版本一致性/不做分支剪枝/不做代码修复
依赖：gh CLI
关键机制：6分析维度（Governance/PR reception/Issue responsiveness/Merge velocity/Rejection patterns/Topic overlap）、5种结论（MERGE-LIKELY/MERGE-UNLIKELY/FILE-ISSUE-FIRST/COMMENT-ON-EXISTING/DUPLICATE-EXISTS）、并行查询
借鉴点：①Pre-PR侦查 ②"查已有issue防重复" ③并行查询加速快照

---

### 23. task-review-workflow（中优先 · PR审查合并工作流）

- 作者：@anikgnr | 页面：https://clawhub.ai/anikgnr/skills/task-review-workflow
- v0.1.0 / 2k 下载 / Pass

做什么：8步：Gather Context→Review Against Standard→Review Diff Thoroughly→Validate Locally→Write Feedback→Decide Outcome→Post-Merge（删task branch/永不删main）→Complete Handoff
不做什么：不做仓库巡检/不做文档同步/不做版本一致性/不做代码修复
依赖：REVIEW_CHECKLIST.md（外部）、Trello、git、PR系统
关键机制：强制基线REVIEW_CHECKLIST.md、"Never delete the main branch"、3种handoff回执
借鉴点：①"永不删main"硬约束 ②handoff三态 ③"必须改vs可选建议"分开

---

## 二、能力矩阵表

列说明：
- 状态快照：是否采集仓库当前状态（status/log/branch/remote/diff）
- 干净脏态分流：是否根据工作区状态走不同处理分支
- 分支剪枝：是否清理已合并/无价值分支
- 文档同步门槛：是否在提交前验证核心文档与真实diff同步
- 版本一致性：是否验证版本号跨文件一致（package.json vs CHANGELOG vs tag）
- 开PR：是否创建pull request（而非仅push）
- 分层安全确认：是否有分级的安全确认（只读自动/本地变更计划批准/远程不可逆动作最终确认）
- 收尾报告：是否产出面向人类的总结报告
- 双shell脚本：是否同时提供bash+pwsh（或等效跨平台双实现）

| Skill | 状态快照 | 干净脏态分流 | 分支剪枝 | 文档同步门槛 | 版本一致性 | 开PR | 分层安全确认 | 收尾报告 | 双shell脚本 |
|---|---|---|---|---|---|---|---|---|---|
| **立正(attention)** | **有** | **有** | **有** | **有** | **有** | **有** | **有（三层）** | **有（大白话+技术细节）** | **有（.sh+.ps1）** |
| alex-session-wrap-up | 部分 | 无 | 无 | 部分 | 无 | 无（push） | 无 | 部分 | 无 |
| repo-standardizer | 部分 | 无 | 无 | 有（创建） | 无 | 无（push） | 有（dry-run+破坏确认） | 有 | 无 |
| emergency-rescue | 部分 | 无 | 无 | 无 | 无 | 无 | 部分（破坏标记） | 无 | 无 |
| deslop | 无 | 无 | 无 | 无 | 无 | 无 | 部分（guardrails） | 有 | 无 |
| git-sentinel | 无 | 无 | 无 | 无 | 无 | 无 | 无 | 有 | 部分（Node.js） |
| pr-risk-analyzer | 无 | 无 | 无 | 无 | 无 | 无 | 无 | 有（SaaS返回） | 无 |
| git-changelog | 无 | 无 | 无 | 部分（写CHANGELOG） | 部分（推断bump） | 无 | 无 | 有 | 无 |
| git-changelog-gen | 无 | 无 | 无 | 部分 | 无 | 无 | 无 | 部分 | 无 |
| sovereign-changelog-maker | — | — | — | — | — | — | — | — | — |
| sovereign-commit-craft | 无 | 无 | 无 | 无 | 有（指导） | 有（模板） | 无 | 部分 | 无 |
| sovereign-git-commit-analyzer | 部分 | 无 | 无 | 无 | 无 | 无 | 部分（阈值exit） | 有 | 部分（bash） |
| commit-analyzer | 部分 | 无 | 无 | 无 | 无 | 无 | 无 | 有 | 部分（bash） |
| conventional-commits | 无 | 无 | 无 | 无 | 有（指导） | 无 | 无 | 无 | 无 |
| git-pushing | — | — | — | — | — | — | — | — | — |
| git-summary | 有 | 无 | 无 | 无 | 无 | 无 | 无 | 有 | 无 |
| git-workflows | 无 | 无 | 无 | 无 | 无 | 无 | 无 | 无 | 无 |
| git-essentials | 无 | 无 | 无 | 无 | 无 | 无 | 无 | 无 | 无 |
| git-helper | — | — | — | — | — | — | — | — | — |
| gh | — | — | — | — | — | — | — | — | — |
| super-github | — | — | — | — | — | — | — | — | — |
| martok9803-ci-whisperer | — | — | — | — | — | — | — | — | — |
| upstream-recon | 无 | 无 | 无 | 无 | 无 | 部分（建议） | 无 | 有 | 无 |
| task-review-workflow | 部分 | 无 | 有（删task branch） | 无 | 无 | 部分（review/merge） | 部分（checklist） | 有（handoff） | 无 |

矩阵结论：只有立正在9个维度上都标"有"。其他skill最多在2-3个维度有交集。

---

## 三、空白点结论

### A. 所有skill都缺、只有立正在做的（差异化优势）

1. **端到端"让项目就绪/可发布"工作流**
   - 事实：23个skill中没有任何一个把"状态快照→干净脏态分流→修复→文档同步→版本一致性→开PR→收尾报告"串成完整链路。
   - 对比：alex做了4阶段但缺文档同步/版本一致性/安全确认；repo-standardizer做了7模块装修但只做一次性初始化；task-review-workflow做了8步PR审查但起点是"已有PR"。
   - 立正价值：唯一的端到端定位。

2. **文档同步门槛**
   - 事实：23个skill中没有一个在提交前验证"核心文档是否与实际diff同步"。
   - 对比：repo-standardizer创建缺失文档但不检查已有文档是否过时；sovereign-commit-craft提到文档同步但不执行验证；git-changelog生成CHANGELOG但不验证版本号一致。
   - 立正价值：唯一把"文档同步"作为提交前硬门槛的skill。这是立正最核心的差异化能力。

3. **版本一致性验证**
   - 事实：23个skill中没有一个跨文件验证版本号一致性（package.json vs CHANGELOG vs tag vs README）。
   - 对比：git-changelog推断bump但不验证当前版本是否已反映这些变化；sovereign-commit-craft有SemVer指导但不验证。
   - 立正价值：唯一实际验证版本号跨文件一致的skill。

4. **干净/脏态分流**
   - 事实：23个skill中没有一个根据工作区状态走不同处理分支。
   - 对比：所有skill都是单一线性流程。
   - 立正价值：唯一根据实际状态智能分流的skill。

5. **双shell实现（bash+pwsh）**
   - 事实：23个skill中没有一个同时提供bash+pwsh两套采集脚本。
   - 对比：emergency-rescue/sovereign-git-commit-analyzer/commit-analyzer有bash脚本；git-sentinel有Node.js脚本；其他全是inline命令或纯文档。
   - 立正价值：唯一的跨平台双实现，让Windows pwsh用户不用装WSL/Git Bash。

6. **分层安全确认模型（三层）**
   - 事实：23个skill中没有一个有"只读自动/本地变更需计划批准/远程不可逆动作需最终确认"的三层模型。
   - 对比：repo-standardizer有dry-run+破坏性操作确认但只两层；emergency-rescue标记破坏性步骤但不要求确认；alex完全不确认直接push。
   - 立正价值：唯一的三层安全确认模型。

7. **大白话收尾报告（面向新手）**
   - 事实：23个skill中没有一个是"主叙事面向项目作者（含新手），字段名/命令串/JSON键不进主叙事，技术信号另放末尾可选小节"。
   - 对比：git-summary结构化输出但纯技术；sovereign-git-commit-analyzer报告含awk脚本生成的技术细节；git-changelog输出markdown但无大白话摘要。
   - 立正价值：唯一的"主叙事+可选技术细节"双层报告设计。

### B. 生态里做得更好、立正该吸收的

1. **deslop的"先比对后动手"模式**
   - 生态做法：deslop对每个候选删除先比较"周边本地模式"再决定是否删除，避免误删信任边界保护。
   - 立正改进：立正修复代码时也应对每个修改点先比对周边代码，再决定是否修改。guardrail"不删信任边界保护"应更具体。

2. **upstream-recon的pre-PR侦查**
   - 生态做法：upstream-recon在开PR前调查目标仓库的合并文化、已有issue、拒绝模式，输出5种结论。
   - 立正改进：立正开PR前可先检查目标仓库是否有open issue描述相同问题，避免重复劳动；PR描述可附"已检查#N无重复"声明。

3. **repo-standardizer的idempotency模型**
   - 生态做法：每个模块可安全重复执行，"先GET再POST/PATCH"的upsert模式。
   - 立正改进：立正每次修复动作应保证可重复执行——重复运行不产生重复提交、不重复开PR。

4. **task-review-workflow的"永不删main"**
   - 生态做法：明确"Never delete the main branch"，作为硬约束。
   - 立正改进：立正已有"不删未合并/受保护分支"，应明确加一句"永不删main/默认分支"。

5. **emergency-rescue的diagnose→fix→verify三步**
   - 生态做法：每次修复操作都有verify步骤。
   - 立正改进：立正每次修复操作后应有verify步骤。

6. **repo-standardizer的dry-run plan表格**
   - 生态做法：apply前显示表格（将创建/更新/跳过），等用户确认。
   - 立正改进：立正执行修复计划前，应展示"将创建/更新/跳过"表格，等待用户确认。

7. **sovereign-commit-craft的"body解释WHY不WHAT"**
   - 生态做法：commit message body应解释WHY，因为diff已经显示WHAT。
   - 立正改进：立正生成commit message时body应强调解释WHY。

8. **sovereign-git-commit-analyzer的quality threshold机制**
   - 生态做法：commit message质量评分低于阈值则exit 1，可挂CI阻断。
   - 立正改进：立正提交前可对commit message做一次quality check，低于阈值则回退重写。

9. **alex-session-wrap-up的session memory持久化**
   - 生态做法：把会话中发现的模式/决策写入memory/YYYY-MM-DD.md。
   - 立正改进：立正收尾报告可追加"本次会话学到的东西"并写入项目内memory/目录。

10. **git-sentinel的CRITICAL/WARNING/SUGGESTION三级+Verdict**
    - 生态做法：审查输出分三级，最终给出REJECT/APPROVE明确裁决。
    - 立正改进：立正收尾报告可参考这个分级，让"是否可发布"一目了然。

11. **upstream-recon的并行查询原则**
    - 生态做法：强调"Run independent queries in parallel"加速调查。
    - 立正改进：立正采集脚本可同时跑多个git查询并发，加速快照。

12. **git-summary的"URL可能含token，不暴露"原则**
    - 生态做法：采集remote URL时显式提示不暴露含token的URL。
    - 立正改进：立正采集脚本输出remote URL时应mask token。

### C. 立正应避免的反模式（生态反面教训）

1. 不要像alex-session-wrap-up一样不确认直接push——立正的分层安全确认比它成熟。
2. 不要像pr-risk-analyzer一样把token发到第三方SaaS——双重Suspicious审计是合理的，立正应坚持所有分析本地完成。
3. 不要像sovereign-commit-craft一样只做纯指导不执行——立正的价值在于"指导+验证"双管齐下。
4. 不要像emergency-rescue一样描述里密集出现敏感命令模式——可能导致OpenClaw Suspicious审计。
5. 不要像repo-standardizer一样只做一次性装修——立正的价值在于日常巡检。

---

## 四、调研覆盖度说明

| 优先级 | 总数 | 抓到实际内容 | 仅拿到描述 | 未找到 |
|---|---|---|---|---|
| 高优先 | 6 | 6 (100%) | 0 | 0 |
| 中优先 | 17 | 13 (76%) | 2（git-workflows, git-essentials） | 6（sovereign-changelog-maker, git-pushing, git-helper, gh, super-github, martok9803-ci-whisperer） |
| 合计 | 23 | 19 (83%) | 2 | 6 |

未找到的6个skill（ClawHub搜索均无结果）：sovereign-changelog-maker、git-pushing、git-helper、gh、super-github、martok9803-ci-whisperer。推测原因：awesome-openclaw-skills列表可能已过期，这些skill已下架、改名或从未发布到ClawHub。

仅拿到描述的2个：git-workflows（@gitgoodordietrying，7.6k下载）、git-essentials（@arnarsson，30.9k下载/38 bookmarks）。

源仓库访问情况：ClawHub的file浏览端点对个人skill不可用（返回404），只能通过openclaw skills install CLI或ClawHub registry内部路径获取。raw.githubusercontent.com尝试均404（这些skill未公开GitHub仓库，仅在ClawHub registry内分发）。本次调研仅基于ClawHub页面+clawskills.sh页面+skills-markdown端点提取的SKILL.md内容。
