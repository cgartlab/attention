# 生态调研：GitHub 上与立正（attention）功能相近的 Skill 与工具

> 调研日期：2026-09-30
> 调研对象：立正Skill（attention）的功能邻近生态——同类 Agent Skill、分支清理 CLI、版本/CHANGELOG 自动化工具、提交前守门工具链。
> 结论定位：不是竞品清单，而是回答三个问题——**谁在做同样的事 / 谁在立正的边界外做得好 / 立正自己有哪些已被证实的缺陷**。
>
> **⚠️ 勘误指针（2026-10-01）**：本文有两条结论已被后续**独立复核与真实实验推翻**，请以 `docs/research/p2-verification.md` 为准——
> ① §4.1/§4.2/§8-P2-10 的 patch-id 口径（"topic 整段 vs main 逐 commit"）**只对 squash 有效，对多 commit rebase 永远匹配不上**，正确口径是两侧都逐 commit；
> ② §4.5/P1-6 的 rulesets 用法（在 `rulesets` 列表里找 `rules[].type=="deletion"`）**取不到数据**，正确端点是 `GET /repos/{o}/{r}/rules/branches/{branch}`。
> 另有 §6.3 关于 workflow/job 级 skip 的表述方向写反，也已在该文档中更正。本文正文**保留原样**以维持调研的可追溯性。

---

## 0. 调研方法与可信度分级

### 0.1 方法

五路并行取证 + 一手实测复核：

| 路线 | 对象 | 方法 |
|---|---|---|
| A | `LinnnnYue/git-repo-hygiene` | `raw.githubusercontent.com` 直取全量 4 文件，逐段精读 |
| B | 23 个生态 skill（awesome-openclaw-skills 的 Git 分类，160 个中筛出） | ClawHub / clawskills.sh / skills-markdown 端点抓 SKILL.md |
| C | 9 个分支清理工具 | 定位源码行号 + 3 组可复现 git 实验 |
| D | 7 个版本/CHANGELOG 工具 | README + 源码（含 release-please 18 个 `src/strategies/*.ts`、commit-analyzer `default-release-rules.js`） |
| E | 8 个守门工具链 | 官方文档 + VS Code 真实 ruleset（API 实测） |
| F | 立正自身 | 构造 6 组 fixture 实测两个脚本实现，独立复核路线 C 的 bug 报告 |

**外部内容一律按不可信数据处理**：仅提取信息，未执行任何仓库的安装脚本，未修改自身 git 配置。

### 0.2 可信度分级（下文每个结论都带标记）

- **【实测】** — 本轮亲自执行 git/脚本命令，附可复现命令。可信度最高。
- **【源码行】** — 读到具体文件行号。
- **【文档原文】** — 工具官方 README / 文档 / 源码注释的原文引用。
- **【待复核】** — 来自并行调研但未独立验证。**不能直接作为缺陷定论**，只能作为候选。
- **【推断】** — 基于已知事实的推理，未实测。

---

## 1. 结论速览（TL;DR）

1. **生态里没有一个做同样的事。** 23 个被调研的 Git 治理类 skill，没有一个把「状态快照 → 干净/脏态分流 → 修复 → 文档同步门槛 → 版本一致性 → 开 PR → 收尾报告」串成完整链路；立正是唯一一个在 9 个能力维度上全部具备的。这既是护城河，也意味着**没有参照系**——没有现成的最佳实践可抄，也没有人会来做同样的事。

2. **只有一个真正的同类物，但它做的是另一件事。** `git-repo-hygiene` 是 Git 仓库治理类 Agent Skill 中唯一与立正形态一致者，但它关注「可交接性」（文件组织、`.gitignore`、LICENSE 识别、大文件拆分、静默失败点），立正关注「同步与发布就绪」（分支、版本、PR）。**两者能力空间高度互补而非重叠**：43 个能力点中，立正 19 项它完全没有、15 项立正完全没有、12 项部分对应、**0 项完全对应**。

3. **立正存在 3 项可验证的实现缺陷，其中 1 项可导致数据丢失。** 这是本次调研最实质的发现，详见 §5。最值得注意的：
   - `release_involved` 在 PowerShell 实现中**恒为 `false`**，而在 bash 实现中为 `true`——立正的核心价值主张「发行版本门槛」在它自己的开发/验证环境（Windows/pwsh）下失效。
   - `branch_cleanup_audit` 的远程合并判定用**本地** `main` 而非 `origin/main` 作基准。当本地 main 领先且未 push 时，会把远程分支误报为「已合并」，据此删除会导致**只存在于该远程分支的提交永久丢失**。

4. **立正在 squash/rebase 合并语义上是「安全地错」。** `git branch --merged` 底层是 `merge-base --is-ancestor`，而 squash/rebase 重写历史产生新 SHA，因此 squash/rebase 合并过的分支永远不会被判为已合并。方向是安全的（只报祖先分支，绝不会误删），但代价是这类分支被误标为「陈旧未合并」，用户无法区分「真未合并」与「已 squash 合并」。业界有成熟解法（patch-id 比对），见 §4.2。

5. **「涉及 release」判定与 bump 规则内部自相矛盾。** `judgment-criteria.md` 的触发规则 2 只认 `chore(release)` / `feat!` / `BREAKING CHANGE`，不含 `fix:`；但 `release-versioning.md` 的 bump 规则写了「fix→patch」。结果是：**patch 级别 bump 的规则永远不会被触发**。这是文档层逻辑张力，不是实现 bug，但会实际误导执行者。

---

## 2. 生态地图

立正的邻近生态按「与立正的重叠方式」分为四类：

```
                          立正（attention）
                       端到端 Git 发布就绪
                              │
        ┌──────────┬──────────┼──────────┬──────────┐
        │          │          │          │          │
   同类 Agent   分支清理    版本/CHANGE  提交前守门   无对应
   Skill        CLI 工具      自动化工具   工具链      的空白
   (1 个)      (9 个)       (7 个)      (8 个)
   │
   能力互补      立正 Phase 3A  立正 version_     立正 Phase 3B
   非竞争        的对标物      consistency_audit   的「门槛」哲学
                                   的对标物        的对标物
```

- **同类 Skill**：同样面向 agent、同样做仓库治理 → §3
- **分支清理工具**：只做立正 Phase 3A 的一个子动作，但做得极深 → §4
- **版本/CHANGELOG 工具**：只做立正 `version_consistency_audit` + CHANGELOG 门槛 → §5
- **守门工具链**：把「提交前检查」这个动作做了标准化，但做的是机械检查 → §6

---

## 3. 第一类：同类 Agent Skill

### 3.1 git-repo-hygiene（唯一的直接同类物）

**仓库**：`https://github.com/LinnnnYue/git-repo-hygiene` ｜ MIT ｜ 0 star ｜ 2026-09 创建

**形态差异**：这是一个**纯说明书仓库**——全量只有 4 个文件（`SKILL.md` 17,501 B、`README.md` 6,584 B、`LICENSE`、`.gitattributes`），**没有 `scripts/`、没有 `references/`、没有模板**。所有命令内联在 SKILL.md 正文里。对比立正的 5 个采集脚本 × 2 套实现 + 8 份 references + 4 份模板，工程化程度差一个量级。

**核心判据**（`SKILL.md` §何时用，原文）：

> 问题不在代码正确性，而在**可交接性**。改的应是「让人一眼看懂现状」的能力，不是功能。

**流程**：审计（只读）→ 三分法判定 → `git mv` 归档 → 脚本化验收。

**9 类触发信号**：根目录散落一次性脚本；`git status` 长期挂未跟踪文件；`.gitignore` 里写了某文件名但该文件已在库中；同类文件「一半入库、一半被忽略」；GitHub License 显示 `NOASSERTION`；文档相对链接指向被忽略目录；单文件 1500 行以上；十几个子类重复同一段样板；「能跑但没人知道哪里在悄悄失败」。

#### 3.1.1 立正完全没有的 15 项能力（【文档原文】）

| # | 能力 | 要点 |
|---|---|---|
| 1 | `.gitignore` 规则与实际入库矛盾探测 | `grep -vE '^\s*(#|$)' .gitignore` 逐条 `git ls-files --error-unmatch` 比对，一次钓出「规则失效」与「同类文件策略不一」两类病根 |
| 2 | `.gitattributes` 行尾/二进制策略检查 | `* text=auto eol=lf` 防跨平台 CRLF diff |
| 3 | 根目录白名单检查 | `git ls-files \| grep -v "/" \| sort` |
| 4 | GitHub License `spdx_id` 识别检查 | `gh api repos/<o>/<r> --jq '.license.spdx_id'`，`NOASSERTION` 的根因「几乎总是：标准许可证正文后面追加了额外内容」 |
| 5 | 三分法文件归档 | 运行必需 / 项目资产 / 一次性过程产物 / 本地垃圾 → `archive/{scripts,release-notes,score-tables,design}/` + `archive/README.md` 索引 |
| 6 | `git mv` 而非 `mv` + `git add` | 保 `git log --follow` 历史连续 |
| 7 | 归档只搬运、不改写 | 「归档区的价值就是『当时就是这么做的』」 |
| 8 | 归档后立刻重写 `.gitignore` | 否则归档文件被旧规则吞掉 |
| 9 | 五条高频陷阱清单 | 见下表 |
| 10 | LICENSE `NOASSERTION` 修复法 | 只留纯正文，中文说明移入 README「协议」章节；**中文版权署名不影响识别** |
| 11 | Python 静默失败点 AST 审计 | `except...: pass` + 失败后用户可见状态不一致 + 三分类处置 + 故障注入演练 |
| 12 | 大文件拆分（AST 机械分段 + 兼容门面） | 门面用模块级 `__getattr__` 动态转发，不用 `from x import *` |
| 13 | 重复样板收敛（模板方法基类） | 只加新兜底出口，不统一对外契约 |
| 14 | 验收命令清单四条 | 用户可自行重跑复核 |
| 15 | 执行纪律 8 条 | 可移植的元纪律 |

#### 3.1.2 五条陷阱（与立正工作流相关的两条）

**陷阱一：`.gitignore` 无前导斜杠 → 规则匹配任意层级（最隐蔽）**【文档原文】

> 双重危害：既让归档后的文件被误忽略（`git add` 静默跳过，人以为加上了），又造成「同类文件一半入库一半被忽略」——因为早期入库的文件在规则生效前就已进库，`.gitignore` 对**已跟踪文件无效**，规则形同虚设却无人发现。

```gitignore
preview3.py    # ✗ 匹配任意目录下的 preview3.py，包括 archive/scripts/preview3.py
/preview3.py   # ✓ 只匹配仓库根目录
```

**陷阱二：`.gitignore` 对已跟踪文件无效**【文档原文】

> 若某文件已在库中，追加忽略规则**不会**让它消失，`git status` 也不报错。要真正移除需 `git rm --cached <file>`。审计时必须用脚本核对，不能只看 `.gitignore` 内容。

> **对立正的注意**：立正硬禁止「纳入 `.gitignore` 文件」（见 `autonomy-and-safety.md`），但这两条陷阱描述的是**用户可能自己手动做的动作**，其后果（静默失效、规则形同虚设）立正没有能力检测。

#### 3.1.3 三条值得直接吸收的元纪律（【文档原文】，与技术栈无关）

> **量化结论一律脚本产出，不用印象值。** 写「13 处」而实测是「12 处」这种事一定会发生。凡要写进文档的数字，先跑一遍**可重跑**的脚本，并把脚本留在仓库里——下一个人才能复核你凭什么这么说。

> **验收口径优先用 AST / 结构化判定，不用文本 grep。** 文本口径无法区分代码与注释（说明性注释必然要提到你要消灭的旧写法，必然误报），换个变量名又漏报。

> **测试耗时突变必须解释。** 同规模用例从 1.5s 掉到 0.06s，往往说明之前那次「通过」其实打了真实网络请求（伪绿）。跑得快不必然是坏事，但差异必须能说明白——说不明白就是有东西不受你控制。

第三条尤其值得注意：立正 `smoke_test` 若出现耗时突变，这是**信号**而非噪音。

#### 3.1.4 两者的取向差异（关键，不是优劣）

| 维度 | 立正 | git-repo-hygiene |
|---|---|---|
| 确认层数 | **三层**（只读自动 → 本地变更需计划批准 → 远程不可逆需最终确认） | **一层**（审计只读 → 用户确认后再动） |
| 硬禁止清单 | 有（7 项：force push 默认分支、直接 push 默认分支、删未合并分支、删受保护分支、纳入 `.gitignore`、detached HEAD 提交、改 `.git/config`） | 无显式禁止清单 |
| 保守取向 | 保守 = 多检查（拿不准归脏态） | 保守 = 多保留（「删 0 项也是成果」） |
| 脚本形态 | 黑盒脚本 + JSON 契约 + 双 shell 实现 + 无脚本回退 | 0 脚本，命令内联在正文 |
| 读者分层 | 明确「新手可跳过技术细节」 | 技术向说明书 |

**判断**：立正的「三层确认 + 硬禁止清单」适合 agent 自动执行（有明确的「什么能自动做」边界）；git-repo-hygiene 的「纪律性安全模型」更适合人工执行。立正在可执行性上领先，git-repo-hygiene 在**仓库结构治理的具体知识密度**上领先。

### 3.2 23 个生态 skill 的能力矩阵

调研范围：awesome-openclaw-skills 的 Git & GitHub 分类（160 个 skill）中筛出的高优先 6 个 + 中优先 17 个。抓到实际内容 19 个（83%）。

**9 维度能力矩阵**（状态快照 / 干净脏态分流 / 分支剪枝 / 文档同步门槛 / 版本一致性 / 开PR / 分层安全确认 / 收尾报告 / 双shell脚本）：

| Skill | 交集维度 | 定位 |
|---|---|---|
| **立正** | **9/9 全有** | 端到端发布就绪 |
| repo-standardizer | 3（文档创建、dry-run、收尾报告） | 一次性仓库装修，不碰代码逻辑 |
| task-review-workflow | 3（删 task branch、handoff、PR） | 起点是「已有 PR」 |
| git-summary | 2（快照、报告） | 纯只读，不做任何操作 |
| alex-session-wrap-up | 2（快照、收尾） | 会话收尾 + 记忆持久化 |
| 其余 18 个 | ≤1 | 单点功能 |

**完整 23 个卡片**见 `docs/ecosystem-research/skill-ecosystem.md`（289 行）。

#### 3.2.1 立正独有的 7 个差异化空白点

调研范围内**没有任何 skill** 具备下列能力，全部只有立正在做：

1. **端到端「让项目就绪/可发布」工作流**——没有一个 skill 把「快照→分流→修复→文档同步→版本一致性→开PR→收尾」串成链路
2. **文档同步门槛**——没有一个在提交前验证「核心文档是否与实际 diff 同步」。repo-standardizer 只创建缺失文档，不检查已有文档是否过时
3. **跨文件版本一致性验证**——没有一个跨 package.json / CHANGELOG / tag / README 校验版本
4. **干净/脏态分流**——没有一个根据工作区状态走不同处理分支
5. **双 shell 实现**——没有一个同时提供 bash + pwsh 两套采集脚本
6. **三层安全确认模型**——只读自动 / 本地变更需计划批准 / 远程不可逆需最终确认
7. **面向新手的收尾报告**——「主叙事不含字段名/命令串/JSON 键，技术信号另放末尾可选小节」

#### 3.2.2 生态做得更好的 12 个可吸收点

**最关键的 5 个**：

1. **deslop 的「先比对后动手」模式**：对每个修改点先比对周边代码再决定，避免误删。立正 Phase 3B 修代码时应采用此模式，guardrail 应更具体。
2. **upstream-recon 的 pre-PR 侦查**：开 PR 前调查目标仓库已有 issue / 合并文化 / 拒绝模式，输出 5 种结论：`MERGE-LIKELY` / `MERGE-UNLIKELY` / `FILE-ISSUE-FIRST` / `COMMENT-ON-EXISTING` / `DUPLICATE-EXISTS`。立正可附「已检查 #N 无重复」声明。
3. **repo-standardizer 的幂等性模型**：每个动作可安全重复执行。立正应保证**重复运行不产生重复提交、不重复开 PR**——当前立正没有显式的幂等性声明。
4. **task-review-workflow 的「永不删 main」**：显式写进规则。
5. **emergency-rescue 的 diagnose→fix→verify 三步**：立正每次修复操作后应有 verify 步骤。

**另外 7 个**：dry-run plan 表格、body 解释 WHY 不 WHAT、quality threshold 机制、session memory 持久化、`CRITICAL/WARNING/SUGGESTION` 三级 + Verdict、并行查询加速、URL mask token。

#### 3.2.3 生态的反面教训（5 个反模式）

| 反模式 | 谁踩的 | 立正应对 |
|---|---|---|
| 不确认直接 push | alex-session-wrap-up | 已有：三层确认 ✓ |
| token 发到第三方 SaaS | pr-risk-analyzer（VirusTotal + OpenClaw **双重** Suspicious） | 不应发生 |
| 纯指导不执行 | sovereign-commit-craft | 立正既有诊断也有执行 ✓ |
| 描述密集出现敏感命令模式 | emergency-rescue、deslop（均被标 Suspicious） | ⚠️ **需注意**：立正 SKILL.md/README 中 force push、`--delete` 等词汇密集，可能被审计误报。建议措辞上区分「我们要做的动作」与「被禁止的动作」 |
| 只做一次性装修 | repo-standardizer | 立正价值在日常巡检 ✓ |

**第三个反模式值得立正警惕**：ClawHub/VirusTotal 的审计对「描述里密集出现敏感命令」敏感。立正在文档里大量列举禁止动作（`git push --force`、`git push --delete`、`git branch -D`），这可能与 emergency-rescue / deslop 的命中原因同源。这不是缺陷，但值得知道这个风险存在。

---

## 4. 第二类：分支清理 CLI 工具（立正 Phase 3A 的对标物）

9 个工具逐个对照见 `docs/ecosystem-research/branch-cleanup-tools.md`（515 行，含源码行号引用）。本节只列对立正有实质影响的部分。

### 4.1 各工具的合并判定手段对照

| 工具 | 手段 | 能抓 squash | 能抓 rebase |
|---|---|---|---|
| **nkt/git-cleanup**（Rust） | `git diff-tree -p mb tip \| git patch-id --stable` 与 main 侧逐 commit patch-id 比对；+ `--first-parent`；+ 10000 commit 扫描上限 | ✅ | ✅ |
| **hartwork/git-delete-merged-branches**（★916） | 三级 effort：L1 `--merged` / L2 `git cherry` / L3 `git commit-tree` 造合成 squash commit 再 cherry | ✅ (L3) | ✅ (L2) |
| **herdr-branch-cleanup**（Rust） | 源码注释直说「git branch --merged lies」，改用 `tip_sha == gh pr list --head --state merged headRefOid` | ✅ | ✅ |
| **aesteve-rh/git-prune-merged** | `pr.head.sha == branch tip`（GitHub PR 元数据） | ✅ | ✅ |
| 其余 4 个 **+ 立正** | 仅 `git branch --merged` | ❌ | ❌ |

**结论**：立正用的是这 9 个工具中技术含量最低的那一档，且只有 4 个工具（含立正）用同样的办法。

### 4.2 【实测】squash/rebase 合并下 `--merged` 必然失效

这是本次调研中最重要的技术发现之一。**立正的删除路径是 sound 的**（`--merged` 只报祖先分支，所以永远不会删掉未合并的工作），**但漏判方向会产生误导性信号**。

复现命令：

```powershell
git checkout -q -b feature2
echo f2 | Set-Content f2.txt
git add .; git commit -q -m "feat: feature2"
git push -q -u origin feature2
git checkout -q main
git merge -q --squash feature2 -m "squash feature2"
git fetch -q
git branch -r --merged main
git merge-base --is-ancestor origin/feature2 main; echo "exit=$LASTEXITCODE"
```

实测输出：

```
Squash commit -- not updating HEAD
branch -r --merged main         => [ origin/HEAD -> origin/main, origin/feature, origin/main ]
is-ancestor origin/feature2 main exit=1
```

**要点**：squash merge 后，`origin/feature2` 的 tip 不在 main 的祖先链上（`exit=1`），所以 `--merged` 正确**不**报它。但它是**已经合并交付**的分支——立正会把它归入 `local_stale_unmerged_report`，标注「陈旧未合并」，用户看到后可能以为还有工作没交付，实则已完成。

**根因**：squash/rebase **重写提交历史**，产生新 SHA，新 SHA 不在 main 的祖先链上，而 `git branch --merged` 底层就是 `merge-base --is-ancestor`。

**业界解法**：nkt/git-cleanup 的 patch-id 方案——内容哈希比对，同时抓 squash + rebase。立正落地方式见 §8 的「P2 值得做」。

> ⚠️ **勘误（2026-10-01，见 `docs/research/p2-verification.md` §1）**：上面"同时抓 squash + rebase"**只对 squash 成立**。多 commit rebase 下，"topic 整段 patch-id vs main 逐 commit patch-id"实测交集为空（N 个提交合成 1 个 patch-id 不可能匹配 N 个独立的）；正确口径是**两侧都逐 commit**。另实测 cherry-pick 必然误报，这才是"只报告不删"的真正理由。

### 4.3 【实测】远程合并判定用本地 base — ⚠️ 数据丢失风险

**这是本次调研发现的唯一涉及数据丢失的缺陷**，已独立复现。

**问题**：`scripts/branch_cleanup_audit.sh:49` 与 `scripts/branch_cleanup_audit.ps1:101` 都是

```
git branch -r --merged "$DEFAULT"
```

`$DEFAULT` 是 `main`（**本地分支**），不是 `origin/main`。

复现：

```powershell
git init --bare -q --initial-branch=main origin.git
git clone -q origin.git work; Set-Location work
# 初始 main + feature 分支，feature 已 push
git checkout -q -b feature; echo f | Set-Content f.txt
git add .; git commit -q -m "feat: feature"; git push -q -u origin feature
# 关键：本地 main 合并 feature，但不 push
git checkout -q main
git merge -q --no-ff feature -m "merge feature"
git fetch -q
```

实测输出：

```
branch -r --merged main         => [ origin/HEAD -> origin/main, origin/feature, origin/main ]
branch -r --merged origin/main  => [ origin/HEAD -> origin/main, origin/main ]
is-ancestor origin/feature main         exit=0
is-ancestor origin/feature origin/main exit=1
```

**含义**：本地 main 已合并 feature 但**尚未 push** 时，`--merged main` 报出 `origin/feature`（误报为「已合并」），而 `--merged origin/main` 正确为空。

**后果**：立正 Phase 3A 会把 `origin/feature` 列为 `remote_merged_candidates`，若用户批准远程删除，而该分支上有**只存在于该远程分支的提交**（例如 rebase 后的分叉、或 squash 前的原始历史），这些提交**永久丢失**。

**触发条件**：本地 main 领先 `origin/main` 且未 push。这在立正自己的工作流里**很常见**——Phase 3A 干净态会 `git pull --ff-only`，但如果用户刚在本地合并了东西还没推，就会命中。

**修法**：

```bash
# 改前
rmerged=$(git branch -r --merged "$DEFAULT" 2>/dev/null | sed 's/^[* ]*//; s/[[:space:]]*$//')
# 改后
if git rev-parse --verify --quiet "origin/$DEFAULT" >/dev/null; then
  rmerged=$(git branch -r --merged "origin/$DEFAULT" 2>/dev/null | sed 's/^[* ]*//; s/[[:space:]]*$//')
  remote_base_unverified=false
else
  rmerged=""
  remote_base_unverified=true    # JSON 新增字段：基准不可验证时显式标注
fi
```

**注意**：两套实现（`.sh:49` 和 `.ps1:101`）**同样地错**，符合 AGENTS.md「改脚本要成对」的约束——修的时候必须成对改。

### 4.4 【实测】立正在远程存在性检测上比标杆工具更干净

一个值得记录的正向发现。立正用 `git ls-remote origin` 缓存 + `grep -Fq` 直接比对真实存在性（`branch_cleanup_audit.sh:46-47`），而 nkt/git-cleanup 要先 `git fetch --prune`（**写操作**）再查本地 ref。

立正作为**只读审计**不需要 fetch，这个设计更干净，也符合它「脚本绝不自己改动仓库」的约定。这是少数几项「立正比业界标杆更好」的地方。

### 4.5 【待复核】GitHub API 端点可用于查询「仓库保护分支」

立正文档承诺了「仓库保护分支」但代码没做（见 §7.6）。以下端点已由调研方实测可用：

- `GET /repos/{o}/{r}/rulesets` — 返回数组
- `GET /repos/{o}/{r}/rules/{ref}` — 列出实际作用于某 ref 的规则（跨仓库+组织+企业汇总）
- `GET /repos/{o}/{r}/branches/{b}/protection` — legacy branch protection
- 判断「能否删」：ruleset 的 `rules[]` 里出现 `type == "deletion"`

> ⚠️ **勘误（2026-10-01，见 `docs/research/p2-verification.md` §2）**：`GET /rulesets`（列表）**不返回 `rules`/`conditions`**（实测只回 `id/name/target/enforcement/source/_links`），据此判删除保护**永远判不出来**。`GET /rules/{ref}` **404 不存在**。正确端点是 **`GET /repos/{o}/{r}/rules/branches/{branch}`**（返回该分支实际生效的 active 规则，已替你过滤 `enforcement` 和 ref 匹配）；**分支不存在时返回 `[]` + 200**（陷阱，须先确认分支存在）。

**更彻底的方案**（可作为立正的「下一步建议」输出）：仓库 Settings → Pull requests → 开 "Automatically delete head branches"，让 GitHub 自己在合并时删源分支，工具只负责报告——**完全消除不可逆风险**。

---

## 5. 第三类：版本与 CHANGELOG 自动化工具

7 个工具逐个对照见 `docs/ecosystem-research/release-automation.md`（358 行，附全部 URL）。

### 5.1 各工具速览

| 工具 | 触发时机 | 判定方式 | 自动推 tag/Release | 面向 |
|---|---|---|---|---|
| **semantic-release**（24k★） | CI 每次推分支 | commit 前缀 → release type | 是，且自动 publish | 全自动 CI 发版 |
| **release-it**（9k★） | 人手动 | 交互 prompt 选 version | 视配置 | 人肉 + 自动结合 |
| **fabiospampinato/bump**（417★） | 人手动 | 命令参数指定版本 | 默认 tag+commit，Release 需手动 | 单人 Node 项目 |
| **release-please**（Google） | GitHub Action 监听推送 | commit 前缀 → semver；`Release-As: x.x.x` 覆盖 | 是，先开「Release PR」再自动 tag | Monorepo |
| **changesets** | PR 作者手写 changeset | 手写 `.changeset/*.md` 里的 semver 类型 | 否 | Monorepo（npm） |
| **git-cliff** | 任意 CI / 本地 | `[bump]` 段 regex 规则 | 否（只写 CHANGELOG） | CHANGELOG 生成器 |
| **conventional-changelog** | 任意脚本 | `conventional-recommended-bump` | 否（只输出建议） | CHANGELOG 生成器 |

**贯穿性发现**【源码行】：所有工具的默认「涉及 release」判定都**只信任 commit message**。它们从不检查 diff 是否真的改了某个 API、也从不检查 CHANGELOG 是否已更新。

> 立正「只反映真实 diff」的原则与业界做法是**正交的**：前者相信机器读的 diff，后者相信人写的 commit 前缀。立正不是落后于业界，而是走了另一条路——但这也意味着立正缺少业界那套「从 commit 语义推断版本级别」的成熟规则集。

### 5.2 【文档原文】业界对「fix:」的处理与立正矛盾

`semantic-release` 的 `commit-analyzer/lib/default-release-rules.js` 默认规则：

- `breaking: true` → `major`
- `revert: true` → `patch`
- `type: feat` → `minor`
- **`type: fix` / `perf` → `patch`**

`git-cliff` 的默认 `no_increment_regex` 是 `chore|ci|docs`——即 `fix` **会**触发增量。

**立正 `judgment-criteria.md` 的「涉及 release」规则 2**：提交信息含 `chore(release)` / `feat!` / `BREAKING CHANGE`。

**不含 `fix:`。** 结果是：一个仓库里绝大多数 patch 发布由 `fix:` 触发，立正全部不触发。而 `release-versioning.md` 又写了「fix→patch」的 bump 规则——**这条规则永远不会被执行到**（除非通过其他两条触发后由用户手动指定 patch）。

这是文档层的逻辑张力，不是实现 bug，但会实际误导执行者。**建议**：要么把 `fix:` 加入触发条件，要么从 bump 规则里删掉「fix→patch」，二选一。

### 5.3 跨语言版本文件清单（`version_consistency_audit` 的边界）

基于 release-please 18 种策略源码的完整清单：

| 生态 | 版本文件 | 立正是否覆盖 |
|---|---|---|
| Node | `package.json.version` + **`package-lock.json`**（根 `version` + `packages[""].version`）+ `npm-shrinkwrap.json` | `package.json` ✓，**lockfile ✗** |
| Python | `pyproject.toml`（`[project].version` 或 `[tool.poetry].version`）+ `setup.py` + `setup.cfg` + `<pkg>/__init__.py` 的 `__version__` + `version.py` | 前两个 ✓，**其余 ✗** |
| Rust | `Cargo.toml`（workspace 根 + 每个 crate）+ `Cargo.lock` | 部分 ✓，**继承语法与 lockfile ✗**（见 §7.4） |
| Go | **`go.mod` 不含版本号**——需扫 `VERSION` 或 `version.go` | 只检测存在性 ✓ |
| Java | `pom.xml`（所有，含 parent）+ `build.gradle` + `gradle.properties` | ✓ |
| PHP | `composer.json` + `VERSION` | ✗ |
| Ruby | `lib/<pkg>/version.rb` + `Gemfile.lock` | `*.gemspec` ✓，**其余 ✗** |
| Swift / .NET | `Package.swift` + `Info.plist` + `*.podspec`；`*.csproj` + `Directory.Build.props` | `.csproj` ✓，**其余 ✗** |
| 通用兜底 | `VERSION` / `version.txt` | ✗ |

**关键观察**【待复核】：**lockfile 是「版本一致性的双源」**——包管理器不会自动同步它们，release-please 的策略源码明确处理它们。立正目前完全不覆盖，是清单里最大的缺口。

### 5.4 CHANGELOG 规范对照

- **分类不同源**：Keep a Changelog 用 `Added/Changed/Fixed/Security`（用户视角），Conventional Commits 用 `feat/fix/refactor/chore`（作者视角）。
- **`refactor:` 处理分歧**：git-cliff 单列；release-please 隐藏；semantic-release 不显示。
- **`docs:` 处理分歧**：release-please 的 Python/Java 策略把 `docs` 提升为 releasable unit，Node 策略归到 Documentation section。
- **`[Unreleased]` 段**：只有 git-cliff 模板天然支持（`{% if version %}## [tag]{% else %}## [unreleased]{% endif %}`）——立正应对齐 git-cliff 的模板。
- **Monorepo 分节**：所有工具都坚持「一个包一个 CHANGELOG.md」，无集中式。立正也应如此。

### 5.5 反幻觉克制强度排序（本次调研最有启发性的一张表）

从「最克制」到「最激进」：

| 排序 | 工具 | 克制机制 |
|---|---|---|
| 1 | **changesets** | 作者手写，工具**零推断** |
| 2 | **bump** | commit message 原文，无分组，强制 review |
| 3 | **git-cliff** | `filter_unconventional` + `skip: true` + `no_increment_regex` 三层过滤 |
| 4 | **conventional-changelog** | `recommended-bump` **只建议不强制** |
| 5 | **release-please** | Release PR 模式，人 merge 才生效 |
| 6 | **release-it** | 交互 prompt，人每步确认 |
| 7 | **semantic-release** | 全自动，无克制（信任 commit message 的极端） |

**立正的独特定位**：changesets 是「作者手写用户影响」（人写，工具存）；立正是「工具从 diff 反向推导用户影响」（工具看 diff，作者审阅）。**这在主流工具里没有直接对应物。**

**建议**：把这条定位写进 `SKILL.md` 作为「反编造守则」：

> CHANGELOG 条目必须满足其一：
> 1. 直接来自 diff 中新增/修改的**公开 API 表面**
> 2. 直接来自 diff 中新增/修改的**用户可见字符串**（README、错误消息、日志）
> 3. 直接来自 diff 中新增/修改的**配置项或依赖**
> 4. 以上皆不满足 → `［待补充：X］` 占位符
>
> **不采信** commit message / PR 标题 / issue 链接等「作者声明」作为 CHANGELOG 内容。

---

## 6. 第四类：提交前守门工具链

立正「门槛即护栏」理念（文档同步与版本一致性门槛放在**提交之前**）的业界对标物。

### 6.1 工具矩阵

| 工具 | 形态 | Windows | 绕过方式 |
|---|---|---|---|
| **pre-commit** | Python 框架，per-hook 缓存（`repo+rev` 为 key） | ✓ 官方测试 | `--no-verify` / `SKIP=hook-id` |
| **prek**（8.5k★，2024-10 创建） | Rust 重写，共享 toolchain，内置部分 hook | ✓ winget/scoop/PowerShell | 同上 + `--group` |
| **lefthook** | Go 二进制，并行优先 | ✓ | `--no-verify` / `LEFTHOOK=0` |
| **husky**（2KB，~1ms 启动） | Node，用 `core.hooksPath` | ✓ 官方声明 | `--no-verify` / `HUSKY=0` |
| **commitlint** | commit-msg 检查器（非框架） | ✓ | — |
| **gitleaks**（30k★） | 密钥扫描，pre-commit 集成 | ✓ Go 单二进制 | — |
| **actionlint**（4.3k★） | Actions YAML 静态检查 | ✓ Go | — |
| **trufflehog** | 旧版密钥扫描，活跃度下降 | ✓ | — |

**关键纠正**：prek 的真实仓库是 **`j178/prek`**（非 `supreme-supreme/prek`，后者 404）。被 CPython / Airflow / FastAPI / Ruff 等 29+ 项目采用。

**prek 的两个值得注意的特性**【文档原文】：
- `--cooldown-days`：新发布版本冻结 N 天，避免刚发布的工具立即影响生产
- impostor-commit 检测：验证 SHA 修订符是否真的指向预期的上游 ref（防供应链攻击）

### 6.2 Git 钩子阶段全景（给「文档同步门槛」选时机）

| 钩子 | 时机 | 能阻止？ | 对「文档同步门槛」的适用 |
|---|---|---|---|
| pre-commit | `git commit` 前，取 staged 内容 | ✅ | pre-commit 主战场 |
| **prepare-commit-msg** | 消息模板准备好、编辑器启动前 | ✅ | ⭐ **最佳拦截点**——能改消息，且**不受 `--no-verify` 抑制** |
| commit-msg | 消息写完后、提交前 | ✅ | 可加「提交信息须提及 CHANGELOG」规则 |
| post-commit | commit 成功后 | ❌ | 仅适合「提交后自动补文档」——但立正的安全分层不允许本地变更不经计划批准 |
| pre-push | push 前，全量检查 | ✅ | 推送前强制跑文档同步检查，可覆盖全量历史 |
| **服务端 pre-receive / update** | push 更新 ref 前 | ✅ | 企业 GitLab/自建 Git 服务端守门 |

**关键事实**：`prepare-commit-msg` 是 Git 原生钩子中**唯一不受 `--no-verify` 抑制**的阶段。这意味着如果立正要给项目配一条「提交时注入文档同步提醒」的钩子，这是唯一无法被用户跳过的时机。

### 6.3 GitHub 服务端守门能力边界（关键限制）

基于 VS Code 主分支真实 ruleset（API 实测）：

**Rulesets 能强制的**：`deletion`（禁止删除受保护分支）、`non_fast_forward`（禁止 force push）、`pull_request`（`required_approving_review_count`、`dismiss_stale_reviews_on_push`、`require_last_push_approval`、`require_code_owner_review`、`require_extra_approval_for_unattributed_changes`、`allowed_merge_methods`）、`required_status_checks`、`signed_commits`、`content_patterns`。

**不能强制的 6 项**（这是立正存在价值的根本原因）：

| 不能强制的 | 说明 |
|---|---|
| ❌ **CHANGELOG 更新** | GitHub 无语义级检查，必须靠 CI workflow + required status check 间接实现 |
| ❌ 文档版本号与 package.json 一致 | 同上 |
| ❌ diff 内容的语义一致性（「改了 README 就要改 CHANGELOG」） | 同上 |
| ❌ 本地 `--no-verify` | 服务端规则管不到本地 |
| ❌ 限制谁提交到非受保护分支 | 仅 branch 级 |
| ❌ commit message 内容 | 除非配合 Actions + required check |

**服务端守门的「最后一公里」问题**：服务端只能强制「check 结果必须 success」，但 check 本身是 CI 跑的脚本。所以真正的强制力 = **Rulesets 强制 required status check + CI workflow 里有语义检查脚本 + workflow 不能被 `[skip ci]` 跳**。

⚠️ **一个容易被忽略的绕过点**：被 skip 的 job 会**上报 "Success"**，不会阻止合并——即使是 required check。所以立正若建议项目配置 required status checks，必须同时禁用 workflow 的 skip 选项。

### 6.4 立正 vs 工具链：互补而非替代

| 维度 | 立正（分层确认） | 工具链（钩子+CI） |
|---|---|---|
| 检查时机 | 模型决定（动态） | 钩子触发（静态） |
| 绕过成本 | 高（需说服模型 + 人工批准） | 低（`--no-verify` / `[skip ci]`） |
| 检查内容 | **语义级**（理解 diff、理解项目） | 语法级/格式级 |
| 强制力 | 中（依赖模型遵守规则） | 高（服务端不可绕） |
| 反馈速度 | 慢（模型推理） | 快（毫秒级） |
| 覆盖场景 | 多步骤工作流（「让项目归位」） | 单点检查 |
| 可审计性 | 低（模型黑盒） | 高（脚本可读、CI 日志可查） |

**判断**：立正不该试图替代工具链——那只会得到「比 pre-commit 更慢、比 gitleaks 更不擅长密钥扫描」的劣化产品。立正该做的是**站在工具链之上**：

- **交给工具链**：格式化（prettier/black）、密钥扫描（gitleaks）、提交消息格式（commitlint）、workflow 语法（actionlint）、版本号字符串匹配（CI）
- **立正做**：文档语义同步判断、多步骤归位、远程动作确认、项目上下文感知

**最有价值的集成建议**：立正开 PR 时检查项目是否配置了 required status checks；没有则建议添加，并让「文档同步」成为合并前硬门槛。这样立正享受工具的强制力（CI required status checks 不可绕），工具链享受立正的语义理解（比 linter 更聪明）。

**另一条可借鉴的机制**：gitleaks 的 **baseline 化**——`--baseline-path` 把历史发现的密钥记入基线，后续只报告新增。立正的文档同步检查应支持同样的「历史豁免」：旧文档没同步不算失败，只检查本次变更引入的不一致。这对立正「不编造、只反映真实 diff」的理念完全一致。

---

## 7. 【实测】立正自身的可验证缺陷

> 本节是本次调研的实质贡献。§7.1–7.5 由构造 fixture 实测得出，附可复现命令。
> **可信度：最高**（本轮亲自执行）。§7.6 为文档层漂移发现，§7.7 为设计取向差异。

### 7.1 E1 `release_involved` 在 PowerShell 实现中恒为 `false`

**契约要求**（`references/scan-recipes.md`）：`version_consistency_audit` 的 `release_involved` = 「任一版本文件路径与某变更路径后缀匹配（任一向）；或任一变更 basename == 某版本文件 basename」。

**实验**：单包 Node 项目，bump `package.json` 的 `version` 字段。

```powershell
git init -q probe-single --initial-branch=main
'{ "name": "single", "version": "1.0.0" }' | Set-Content probe-single\package.json
git -C probe-single add .; git -C probe-single commit -q -m "chore: init"
'{ "name": "single", "version": "1.0.1" }' | Set-Content probe-single\package.json
git -C probe-single add package.json
pwsh -NoProfile -File scripts\version_consistency_audit.ps1 --repo probe-single
```

实测输出：

```json
{
  "version_files": [ { "file": "D:\\...\\probe-single\\package.json", "ecosystem": "node", "version": "1.0.1" } ],
  "changed_files": [ "package.json" ],
  "release_involved": false        // ← 应为 true
}
```

**`version_files` 明确包含 `package.json`，`changed_files` 明确包含 `package.json`，版本号确实从 1.0.0 变成 1.0.1，但 `release_involved` 是 `false`。**

三个 fixture 均复现（单包 Node、Cargo workspace、多生态探测目录），排除偶发。

### 7.2 E2 `version_files[].file` 输出违反路径契约

`references/scan-recipes.md` 契约写明：

> JSON 内路径统一正斜杠（`.ps1` 已做 `\`→`/`）

实测 `.ps1` 输出：

```json
"file": "D:\\2-Area\\github-repos\\attention\\__attention_test\\probe-single\\package.json"
```

**反斜杠 + 绝对路径**，违反契约的两条要求。

### 7.3 E3 双实现行为分叉（AGENTS.md 契约被违反）

同一 fixture、同一变更，两个实现的输出：

| 字段 | `.sh` 实现 | `.ps1` 实现 |
|---|---|---|
| `version_files[].file` | `package.json`（相对、正斜杠）✓ | `D:\...\package.json`（绝对、反斜杠）✗ |
| `release_involved` | **`true`** ✓ | **`false`** ✗ |

AGENTS.md 明确要求「改脚本要成对」「防双份漂移」，`scan-recipes.md` 要求「跨 shell 输出**同形 JSON**」。两者都被违反。

**⚠️ 更值得注意的是**：`CHANGELOG.md` [Unreleased] 记录了一条

> version_consistency_audit.sh 质量修复：去掉重复的 release_involved 二次扫描（改为首次扫描收集路径内联计算，**与 .ps1 一致**）

即：`.sh` 已被改造成「与 `.ps1` 一致」——**改到了错误的一边**。`.sh` 原本是对的，被改成和 `.ps1` 的错误对齐了。**parity 声明与实测矛盾**。

**影响面**：立正的核心价值主张之一是「发行版本门槛」，而触发这个门槛的第一条条件是「变更集触及版本文件」。这条在立正自己的开发/验证环境（Windows/pwsh，见 `environment-and-prereqs.md` §6 的说明）下**完全不生效**。只有另外两条触发条件（`chore(release)`/`feat!` 前缀、用户明示）还能工作。

**根因推测**（【推断】，需读源码确认）：`.ps1` 输出的 `version_files[].file` 是绝对路径 + 反斜杠，而 `changed_files` 是相对路径 + 正斜杠。当两者做「后缀匹配」或「basename 相等」比较时，路径分隔符和根不一致导致匹配失败。`.sh` 输出相对路径，故能正常匹配。

**修复方向**：让 `.ps1` 的输出与契约对齐（相对路径 + 正斜杠），这是「改对的一边」的正确方向。

### 7.4 E4 Cargo workspace 继承版本漏检

`release-versioning.md` 写了「workspace 用 `[workspace.package].version` + 成员 inherit」，但脚本的匹配规则未覆盖 TOML 的两种官方继承语法。

**fixture**：

```toml
# Cargo.toml
[workspace]
members = ["packages/a", "packages/b"]
[workspace.package]
version = "2.0.0"

# packages/a/Cargo.toml
[package]
name = "pkg-a"
version.workspace = true          # TOML 1.0 语法

# packages/b/Cargo.toml
[package]
name = "pkg-b"
version = { workspace = true }    # TOML 0.5 语法
```

**实测输出**：

```json
{
  "version_files": [ { "file": "...\\Cargo.toml", "ecosystem": "rust", "version": "2.0.0" } ],
  "distinct_versions": [ "2.0.0" ],
  "consistent": true
}
```

**只有根的 `2.0.0` 被抓到，两个成员完全漏检**——`consistent: true` 是在**没有任何成员版本可比对**的情况下得出的，即一致性判断**空转**。

**与 eval 的关系**：`evals/evals.json` 的 eval-3 prompt 明确是「顺便 cargo workspace 那个版本也得一起对齐」。**eval 覆盖了场景，但实现抓不到**——这是「测试存在但无法验证能力」的典型状态，比没有 eval 更危险（给了虚假的安全感）。

### 7.5 E5 `vendor/` 目录未排除 → 一致性误报

**fixture**：根 `package.json` version=1.0.1 + `vendor/sub/Cargo.toml` version=3.3.3 + `.venv/lib/pyproject.toml` version=7.7.7。

**实测输出**：

```json
"version_files": [
  { "file": "...\\package.json",            "ecosystem": "node", "version": "1.0.1" },
  { "file": "...\\vendor\\sub\\Cargo.toml", "ecosystem": "rust", "version": "3.3.3" }
],
"consistent": false
```

- `vendor/` **被纳入** → 第三方依赖版本污染了项目版本一致性判断，产生 `consistent: false` 误报
- `.venv/` **被正确排除**（7.7.7 未纳入）→ 说明排除表是有意识设计的，只是漏了 `vendor/`

契约的排除列表：`node_modules|.git|/target|/dist|/build|.venv|/venv|__pycache__|/obj|/bin`——无 `vendor/`。

Python 的 `vendor/` 惯例（pip vendor / pipenv vendor）和 Rust 的 vendored deps 都会落在这里。

### 7.6 文档与契约漂移清单

读 `references/` 对照 SKILL.md 发现 6 处漂移：

| # | 漂移 | 位置 |
|---|---|---|
| B1 | **受保护名单不一致**：SKILL.md §3.2 写 `main master develop dev trunk release/* prod production gh-pages`，**缺 `gh-readonly`**；而 `branch-model-and-protection.md` 和 `scan-recipes.md` 都含 `gh-readonly` | SKILL.md §3.2 |
| B2 | **`core_docs_relevance_scan` 范围不一致**：定义是「README 索引的文档」（`core-docs-sync.md`），实现是「全部 `docs/**/*.md` 前 50 个」（`scan-recipes.md`）。实现更宽松，会导致 `docs_needing_update` 噪声过多 | core-docs-sync.md ↔ scan-recipes.md |
| B3 | **`missing_core_docs` 有字段无算法**：`scan-recipes.md` 的 JSON 契约声明了 `missing_core_docs(str[])`，但同一节的「git 命令」清单没有说明它怎么算。**无脚本回退路径**的模型无法据此复现该字段 | scan-recipes.md §next_steps_analysis |
| B4 | **「涉及 release」与 bump 规则自相矛盾**：触发条件不含 `fix:`，但 bump 规则含「fix→patch」→ patch 规则永不可达 | judgment-criteria.md ↔ release-versioning.md |
| B5 | **`core_docs_relevance_scan` 的启发式脆弱**：用「文档内容是否字面包含变更文件 basename」判断相关性。basename 冲突（`index.js`、`main.go`、`__init__.py`、`mod.rs` 大量同名）会造成大量误报；且抓不到无字面文件名引用的 API 表格 | core-docs-sync.md |
| B6 | **版本文件清单偏窄**：缺 lockfile 系列、`Gemfile.lock`、`setup.cfg`、`composer.json` 等（对照见 §5.3） | release-versioning.md |

**B1 值得单独注意**：`gh-readonly` 是 GitHub Pages 的只读镜像分支，被误删会造成 Pages 站点中断。

### 7.7 一个设计取向的差异（非缺陷）

git-repo-hygiene 的「删 0 项也是成果」与立正的「拿不准归脏态」取向相反：

> **删 0 项也是成果。** 若判定全部产物都有保留价值，就一个都不删。用户要的是「清爽且可查」，不是「删得多」。

立正 Phase 2 倾向「多检查」（拿不准归脏态），git-repo-hygiene 倾向「多保留」（拿不准就不删）。两者都对，但立正的分支剪枝路径需要**明确区分**「无候选可删」和「候选被判定保留」——否则用户看不出「立正检查过了但没删」与「立正没检查」的区别。这其实立正已经做到了（`branch_cleanup_audit` 输出候选清单），值得在收尾报告里显式说清。

---

## 8. 可吸收清单（按优先级）

### P0 必修（涉及数据丢失或核心价值失效）

| # | 项 | 落点 | 理由 |
|---|---|---|---|
| 1 | 远程合并判定改用 `origin/$DEFAULT`，加 `rev-parse --verify` 守卫，失败时 JSON 标注 `remote_base_unverified: true` | `branch_cleanup_audit.sh:49` + `.ps1:101` **成对** | 唯一涉及数据丢失的缺陷 |
| 2 | 修 `.ps1` 的 `version_files[].file` 为相对路径 + 正斜杠，使 `release_involved` 恢复工作 | `version_consistency_audit.ps1` | 立正核心价值主张在自己的环境下失效 |
| 3 | 更新 `CHANGELOG.md`：`.sh` 的 parity 声明与实测矛盾，需重新核对方向 | `CHANGELOG.md` [Unreleased] | 错误的 parity 声明会误导后续维护者 |

### P1 强烈建议

| # | 项 | 落点 | 理由 |
|---|---|---|---|
| 4 | Cargo workspace 继承语法（`version.workspace = true` / `version = { workspace = true }`）解析 | `version_consistency_audit` | eval-3 覆盖场景但实现抓不到 |
| 5 | `vendor/` 加入排除列表 | 同上的排除表 | 避免第三方依赖污染一致性判断 |
| 6 | 真正实现文档承诺的「仓库保护分支」查询：`gh api repos/{o}/{r}/rulesets`，`rules[]` 含 `type=="deletion"` 即禁删，**无权限静默降级** | `branch_cleanup_audit` | 文档承诺了但代码没做 |
| 7 | 受保护名单支持 `git config --get-all cleanup.protect` 持久化 | 同上的保护名单 | 用户配一次全仓库共享，脚本不用改 |
| 8 | 「涉及 release」规则 2 加入 `fix:`，或从 bump 规则删掉「fix→patch」 | `judgment-criteria.md` + `release-versioning.md` | 消解文档层逻辑矛盾 |
| 9 | lockfile 版本字段扫描（package-lock / Cargo.lock / Gemfile.lock / pnpm-lock） | `version_consistency_audit` | lockfile 是版本一致性的双源 |

### P2 值得做

| # | 项 | 落点 | 理由 |
|---|---|---|---|
| 10 | 「疑似已 squash/rebase 合并」报告分类（**只报告不删**）：`git diff-tree -p mb tip \| git patch-id --stable` 与 main 侧 `git log --first-parent -p` 逐 commit patch-id 比对 | `branch_cleanup_audit` 新增字段 | 解决「陈旧未合并」误标问题。**三个边界**：跳过空 diff（否则空 patch-id 假阳性）、必加 `--first-parent`（否则 merge 子树污染映射）、主分支侧算逐 commit patch / topic 侧算整段 range 当一个 patch（两边 patch-id 空间才一致）。**不进入删除候选**——patch-id 是内容哈希，理论上可能碰撞 |
| 11 | 新增 `gitignore_consistency_audit`（第 6 个采集脚本） | `scripts/` + `scan-recipes.md` | 立正完全没有的仓库卫生能力，且是 git-repo-hygiene 的核心价值 |
| 12 | 新增 `references/common-pitfalls.md`，先收 `.gitignore` 无前导斜杠 + 对已跟踪文件无效两条 | `references/` | 与硬禁止清单互补（那些是「不许做」，这是「你做了但没生效」） |
| 13 | Phase 4 报告新增「✅ 你如何复核」小节（验收命令清单） | `assets/templates/status-report.md` | 用户可自行重跑复核，与「大白话」设计互补 |
| 14 | 文档同步门槛新增 LICENSE `spdx_id` 识别检查 | Phase 3B 第 5 步 | 立正核心文档集含 LICENSE* 但只检查内容同步，不检查 GitHub 侧识别 |
| 15 | 删除前检查分支是否被 worktree 检出（`git worktree list --porcelain`） | `branch_cleanup_audit` | `-d` 会拒绝所以不会真出事，但报告更友好 |
| 16 | 远程删除加 `--force-with-lease=<branch>:<审计时的sha>` | 远程删除动作 | 防确认窗口内他人推送（9 个工具中只有 hartwork 用了） |
| 17 | 幂等性声明：重复运行不产生重复提交、不重复开 PR | SKILL.md | 立正目前无显式幂等性保证 |

### P3 观察但暂不做

- **monorepo 分节**（所有工具都坚持「一个包一个 CHANGELOG」）——立正当前定位是「任意 Git 项目」而非 monorepo 专家
- **多目标分支**（required_target_branches 集合交集，对 main+develop 双集成线有用）
- **`gh pr list` 作为置信度增强字段**（不作为删除依据）
- **Python 静默失败点 AST 审计**——语言特化 + 会引入 Python 依赖，与立正「不要求 Python」的约定冲突。**应作为独立可选 skill，不并入立正主流程**
- **三分法文件归档全套**——会显著扩大立正范围，偏离核心定位。**建议只在 Phase 1 快照里加一个「未跟踪文件分类建议」字段（按三分法分类，但不执行归档动作，由用户决定）**

### P4 明确不吸收

- **git mv / 归档只搬运不改写**——立正不执行文件移动动作
- **Python 门面设计细节**（`__getattr__` vs `from x import *`）——立正不做代码重构
- **重复样板收敛（模板方法基类）**——同上，语言特化
- **git-repo-hygiene 的「删 0 项也是成果」取向**——与立正的「多检查」取向相反，不吸收

---

## 9. 差异化定位结论

### 9.1 立正的位置

**立正是最早做「端到端 Git 发布就绪」的 agent skill。** 23 个被调研的同类 skill 中没有一个具备这条链路；9 个分支清理工具只做其中一个子动作；7 个版本工具只做另一个；8 个守门工具只做机械检查。

**但**：立正在分支清理和版本判定这两个「子动作」上，用的是同类工具里技术含量最低的方案。护城河在**编排**，不在**单项**。

### 9.2 三条战略含义

1. **不要把立正做成「更好的 pre-commit」**。守门工具链已经把这个动作标准化到毫秒级、可 CI 强制、可服务端强制。立正该做的是站在工具链之上，做工具链做不了的语义判断和流程编排（见 §6.4）。

2. **单项能力要追上业界标杆，至少要跟上**。特别是：
   - 分支清理：patch-id 方案是标杆（nkt/git-cleanup），立正当前只到 `--merged` 一档
   - 版本一致性：lockfile 是必修课，立正当前完全不覆盖
   - 这些不是差异化，是**及格线**

3. **立正的独有价值应该被显式声明**。当前「反幻觉守则」散落在 `core-docs-sync.md` 里，建议提炼进 SKILL.md 作为一等公民（见 §5.5 的建议文本）。这是业界没有的东西。

### 9.3 一句话总结

> 生态里没有人和立正做同样的事——这既是护城河，也意味着没有最佳实践可抄。立正在编排上是唯一的，在单项能力上是最弱的。当前最紧急的事不是加新能力，而是**修掉已经证实会让核心价值失效的实现缺陷**（§7.1–7.3），以及**修掉那个会导致数据丢失的判定基准**（§4.3）。

---

## 附录 A：来源清单

### 同类 Skill
- `https://github.com/LinnnnYue/git-repo-hygiene` — 4 文件全量抓取（SKILL.md 17,501 B / README 6,584 B / LICENSE / .gitattributes）
- `https://github.com/VoltAgent/awesome-openclaw-skills` — 160 个 Git 分类 skill 索引（52k★）
- ClawHub / clawskills.sh / skills-markdown 端点 — 23 个 skill 的 SKILL.md 抓取

### 分支清理工具
- `https://github.com/nkt/git-cleanup`（Rust，patch-id 标杆方案）
- `https://github.com/hartwork/git-delete-merged-branches`（★916，三级 effort）
- `herdr-branch-cleanup`（Rust，源码注释：「git branch --merged lies」）
- `https://github.com/aesteve-rh/git-prune-merged`（GitHub PR 元数据比对）

### 版本 / CHANGELOG 工具
- `https://github.com/semantic-release/semantic-release`（24k★）+ `commit-analyzer/lib/default-release-rules.js`
- `https://github.com/release-it/release-it`（9k★）
- `https://github.com/fabiospampinato/bump`（417★）
- `https://github.com/googleapis/release-please`（18 个 `src/strategies/*.ts`）
- `https://github.com/changesets/changesets` + `docs/decisions.md`
- `https://github.com/orhun/git-cliff` + `config/cliff.toml`
- `https://github.com/conventional-changelog/conventional-changelog`
- `https://keepachangelog.com/en/1.1.0/` ｜ `https://www.conventionalcommits.org/en/v1.0.0/`

### 守门工具链
- `https://github.com/pre-commit/pre-commit` ｜ `https://pre-commit.com/`
- `https://github.com/j178/prek`（8.5k★，**注意 org 是 j178**）｜ `https://prek.j178.dev/`
- `https://github.com/evilmartians/lefthook` ｜ `https://lefthook.dev/`
- `https://github.com/typicode/husky` ｜ `https://typicode.github.io/husky/`
- `https://github.com/conventional-changelog/commitlint` ｜ `https://commitlint.js.org/`
- `https://github.com/rhysd/actionlint`（4.3k★）
- `https://github.com/gitleaks/gitleaks`（30k★）｜ `https://gitleaks.io/`
- `https://github.com/trufflesecurity/truffleHog`
- `https://git-scm.com/docs/githooks`
- `https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets`
- VS Code 主分支真实 ruleset（API 实测）：`https://github.com/microsoft/vscode/rules/139683`

## 附录 B：详细报告

| 文件 | 行数 | 内容 |
|---|---|---|
| `docs/ecosystem-research/branch-cleanup-tools.md` | 515 | 9 个工具卡片 + 策略对照表 + 3 组 git 实验原始输出 |
| `docs/ecosystem-research/release-automation.md` | 358 | 7 个工具卡片 + 跨语言版本文件清单 + 反幻觉克制排序 |
| `docs/ecosystem-research/skill-ecosystem.md` | 289 | 23 个 skill 逐个卡片 + 能力矩阵 |

## 附录 C：实验 fixture 位置

所有实测 fixture 位于 `__attention_test/`（已被 `.gitignore` 排除）：

- `probe-single/` — 单包 Node，用于 E1/E2/E3
- `probe-ws/` — Cargo workspace 继承版本，用于 E4
- `probe-version/` — 多生态探测，用于 E5
- `probe-merge/` — 裸仓库 + clone，用于 §4.2 / §4.3 的合并语义实验
