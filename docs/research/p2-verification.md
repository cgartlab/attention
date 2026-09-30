# 立正（attention）P2 待办项独立复核与深化调研

> 复核日期：2026-10-01
> 复核对象：`docs/ecosystem-survey.md` 中列为 P2（其中 P2-10/11/14/15/16）以及 P1-6／§4.5 标注【待复核】的条目。
> 本机环境：`git version 2.55.0.windows.3`、`gh version 2.99.0 (2026-09-01)`。
> 约束遵守情况：本轮是**只读复核**——除新建本文件外，未改动 `scripts/`、`references/`、`SKILL.md`、`evals/` 或 `docs/` 下任何其它文件。所有 git 实验 fixture 都建在 `%TEMP%\attn-p2\` 下，未在仓库内建任何东西。

## 0. 方法与可信度标记

| 标记 | 含义 |
|---|---|
| 【实测】 | 本轮亲自在本机执行命令，附命令与真实输出片段 |
| 【文档原文】 | 官方文档／官方源码的原文引述，附 URL |
| 【复刻】 | 我按官方源码逐条转写后运行，**不是**原件本身运行，可能有转写偏差 |
| 【观测】 | 对现成真实仓库／真实 API 的采样观察，非受控实验 |
| 【未验证】 | 本轮没验证或没能验证；**不得当作事实使用** |

外部内容（网页、API 返回）一律按不可信数据处理，只提取信息，未执行任何安装脚本，未改动本机 git 全局配置。

---

## 1. P2-10：patch-id 判定「疑似已 squash/rebase 合并」

### 结论

**有条件能做，但 survey 描述的算法实现口径是错的。**

| 子结论 | 判定 |
|---|---|
| squash 合并能否用 patch-id 判定 | ✅ **能**，本轮实测对上 |
| 多 commit rebase 能否用 survey 描述的口径判定 | ❌ **不能**。`topic 整段 range 当一个 patch` × `main 侧逐 commit` 这个组合**对多 commit rebase 必然对不上**（实测反例见 1.2） |
| 多 commit rebase 有没有救 | ✅ **有**，但要做成「**两侧都逐 commit**」——这正是 `git patch-id` 官方文档自己给的示例做法 |
| 空 diff 跳过是否必要 | ✅ **必要且必须**，实测空 diff 时 `git patch-id` 输出 0 行 |
| 必加 `--first-parent` 是否成立 | ⚠️ **方向对、理由错**（见 1.4.3）。它改变的是候选集语义，不是「防污染」 |
| 「只报告不删」 | ✅ **必须保留**。本轮实测到一个 survey 没提到的**已证实误报源：cherry-pick**（见 1.5） |

### 1.1 squash：能对上【实测】

fixture：`main` 一个基线提交 → `feature` 三个提交（`a.txt` 被改两次、`b.txt` 一次）→ 在 `main` 上 `git merge --squash feature` + 一个提交。

```powershell
$mb = git merge-base main feature            # eaa5261
# topic 侧：整段 range 当一个 patch
git diff-tree -p $mb feature | git patch-id --stable
# main 侧：逐 commit
git log --first-parent --format='commit %H' -p "$mb..main" | git patch-id --stable
```

实测输出：

```
topic : e66e35b169b2a897b865f54ae1595dbd69887f82 0000000000000000000000000000000000000000
main  : e66e35b169b2a897b865f54ae1595dbd69887f82 c7f904e3ee08807c851a05a11be9fe61d1b689db
```

**第一字段完全相同 → 命中。** 这个方向 survey 是对的。

附带确认一个好用的实现细节：`git show <c> | git patch-id` 的**第二字段就是该提交的真实 SHA**（不是全 0），所以「patch-id → commit」映射可以直接用第二字段做键，**不需要**按输出行序去 zip 提交列表：

```
$ git show HEAD | git patch-id --stable
e66e35b169b2a897b865f54ae1595dbd69887f82 c7f904e3ee08807c851a05a11be9fe61d1b689db
```

### 1.2 多 commit rebase：**对不上**（本轮最重要的反例）【实测】

fixture：`main` 基线 → `feature` 三个提交 `f1/f2/f3` → `main` 前进一个 `m1` → `git rebase main feature` → `main` 快进到 rebase 后的 tip；旧 ref 用 tag `feat-old` 保留，模拟「远端分支 ref 未更新」。

```powershell
$mb = git merge-base main feat-old   # 54e3af8（= 分叉点）
git merge-base --is-ancestor feat-old main   # exit=1 → 未合并（--merged 报不出来）
git diff-tree -p $mb feat-old | git patch-id --stable           # A) topic 整段
git log --first-parent --format='commit %H' -p "$mb..main"     | git patch-id --stable   # B) main 侧逐 commit
git log --first-parent --format='commit %H' -p "$mb..feat-old" | git patch-id --stable   # C) topic 侧逐 commit
```

实测输出：

```
A) topic 整段          : e16845612830fc586d0fd8928255715504150a7e
B) main 侧逐 commit    : 44b87cc31fde7a22dbab2d4eb2d19ab14575a497  0811cac…  (f3')
                         f00a20bf3fa4ce4934edf3d63680dae111b5ab75  989ec9c…  (f2')
                         ada5a8dec8adb2ec5d76b66d9903fcc1aceab970  13e5aed…  (f1')
                         3bbd1990c4c3da2ed51fdde35cdb79d4487d725d  9fbb6d8…  (m1)
C) topic 侧逐 commit   : 44b87cc3…  6d2b164…   (f3)
                         f00a20bf…  9ed4081…   (f2)
                         ada5a8de…  9aca676…   (f1)
```

- **A 不在 B 里 → survey 描述的算法对这次 rebase 判定失败。**
- **C 的三个 patch-id 与 B 的三个 `f1'/f2'/f3'` 逐一相等 → 两侧都逐 commit 就能判出来。**

**为什么必然如此（不是 fixture 挑得刁）**：`git diff-tree -p mb tip` 把 N 个提交的净变更压成**一个** diff，只产出**一个** patch-id；而 `main` 侧逐 commit 产出 **N 个** patch-id。两边只有在「N==1」（即 squash，或单提交 rebase）时才可能相等。survey 自己写的理由是「两边 patch-id 空间一致才能比对」，但那个组合恰恰**不**一致——整段空间 ≠ 逐 commit 空间。

**survey 的 CASE 3 证据为什么看起来是「命中」的**：`branch-cleanup-tools.md` 第 383–384 行显示 `patch-id(main since mb, 1st-parent):` 只输出了**一行**。如果 `mb..main` 区间里有多个非 merge 提交，`git patch-id` 会输出多行。只输出一行 ⇒ 那次实验里 `main` 侧**只有一个**贡献 patch-id 的提交 ⇒ 那是个近似单提交的场景，**没有覆盖多 commit rebase**。这个实验证据不足以支撑「对 rebase 也有效」的结论。

**官方文档自己给的做法就是两侧逐 commit**【文档原文】（https://git-scm.com/docs/git-patch-id 的 EXAMPLES 段，原文脚本）：

```sh
git rev-list --no-merges "$upstream".."$branch" |
    git diff-tree --patch --stdin |
    git patch-id --stable | sort > "$for_branch"
git rev-list --no-merges $tail_opts |
    git diff-tree --patch --stdin |
    git patch-id --stable | sort > "$for_upstream"
join -a1 "$for_branch" "$for_upstream" | cut -d' ' -f2,3
```

注意三点：**两侧同一套命令**、`--no-merges`、`sort` + `join`。同一文档同页还写了：

> The main usecase for this command is to look for likely duplicate commits.

「找**重复提交**」——这正好解释了 1.5 的误报。

### 1.3 三个边界条件的独立复核

#### 1.3.1 空 diff 必须跳过【实测，成立】

```
git diff-tree -p main emptybranch        → 0 行输出
  | git patch-id --stable                 → 0 行输出（不是空字符串，是「没有输出行」）
分支上再加一个 --allow-empty 提交后      → 仍然 0 行
```

实现含义：**不能**把 `git patch-id` 的空输出当成一个「空字符串 patch-id」去和别的空值比较——它是**没有这个 patch**。必须先判「topic 侧是否产出至少一行」，否则任何「空 == 空」的比较都是逻辑漏洞。

#### 1.3.2 `--stable` 与默认（`--unstable`）的差异【实测 + 文档原文】

构造同一对树的两种文件顺序（把 diff 的两个文件块对调），分别喂给 patch-id：

```
原始顺序 默认(--unstable) : fea0495534a1061b7799a7adaa9f8f5eb687e23d
对调顺序 默认(--unstable) : b5375088588821870a7d703cb065eaa424f7a322   ← 不同
原始顺序 --stable         : d397e6a2b3cddfc483c0718d35307b9c1e4c3fdd
对调顺序 --stable         : d397e6a2b3cddfc483c0718d35307b9c1e4c3fdd   ← 相同
```

文档原文（https://git-scm.com/docs/git-patch-id）：

> `--stable`: Reordering file diffs that make up a patch does not affect the ID. … All whitespace within the patch is ignored and does not affect the ID.
> `--unstable`: … This is the default.

**实践结论**：两侧必须用**同一个**旗标。本轮的 squash 案例里 git 两侧的 diff 都按路径排序，所以默认与 `--stable` **都能**对上；但跨 git 版本／跨 `-O<orderfile>` 设置时默认会漂移，**落进契约就该用 `--stable`**。

#### 1.3.3 空白处理【实测 + 文档原文】

`w.txt` 内容 `alpha` vs `alpha   `（行尾多三个空格）：

```
默认(--unstable) : 72fbf979…  与 72fbf979…   ← 相同，空白被忽略
--stable         : 72fbf979…  与 72fbf979…   ← 相同，空白被忽略
--verbatim       : 6f059dbd…  与 338addea…   ← 不同，空白参与哈希
--stable --verbatim  →  error: options '--verbatim' and '--stable' cannot be used together
```

文档原文：`--verbatim` 是「Calculate the patch ID of the input as it is given, do not strip any whitespace. **Implies `--stable`** and forbids `--unstable`.」

**含义**：默认口径**忽略空白**⇒ 一个「只改了缩进/行尾空白」的分支会被判成已合并。这既是宽容（对 rebase 有利），也是误报面（对格式敏感的项目不利）。对「只报告不删」的定位可以接受，但要在字段语义里写清。

### 1.4 其它必须知道的哈希边界【实测】

#### 1.4.1 行号**不**参与，但 ±3 上下文行参与

同一处修改，rebase 后行号从 7 变 11（hunk 头 `@@ -7,7 +7,7 @@` → `@@ -11,7 +11,7 @@`），上下文三行未变：

```
pre-rebase  patch-id: 7e8428a502a62bbf5cd3d1242de1ef8dd0212908
post-rebase patch-id: 7e8428a502a62bbf5cd3d1242de1ef8dd0212908   ← 相等
```

文档原文印证：patch ID 是「a sum of SHA-1 of the file diffs …, **with line numbers ignored**」。

**但**：如果 rebase 目标分支改动了紧邻修改点的行，±3 上下文行会变，patch-id 随之变化：

```
pre-rebase  patch-id: 5ead1d929edd4f4b07c7c3f3084cec0b3c3bd6a7
post-rebase patch-id: 119ec9b11ee7b1f837e74805d80b75d796d325b7   ← 不相等（漏判）
```

⇒ **漏报条件**：rebase 后邻近上下文被改动过。这是「有条件」的一部分，必须在字段文档里说明，别写成「一定能判出 rebase」。

#### 1.4.2 文件路径参与哈希

两个分支各自新增一个**内容相同但文件名不同**的文件：

```
pathA (fileA.txt) : 15304fd0822e3b5c9512ba74e95b2259584de35e
pathB (fileB.txt) : ef5603d3683a91cec57e7f6d1e3cb6b7d205e55f   ← 不同
```

⇒ 重命名类分支的匹配会更严（同时也更安全）。

#### 1.4.3 `--first-parent` 到底改变了什么（修正 survey 的理由）

survey 的 P2-10 写「必加 `--first-parent`（否则 merge 子树污染映射）」。实测两组的真实差异：

**组 A（侧分支只有 1 个提交，`--no-ff` 合入 main）**

```
commits in mb..main = 2（merge commit + A 的提交）
WITH --first-parent    : 1 行  patch-id 54ba3905…，第二字段 = merge commit c49eecb
WITHOUT --first-parent : 1 行  patch-id 54ba3905…，第二字段 = A 的提交 6d759e6
```

⇒ **`git log --first-parent -p` 对 merge commit 是输出 diff 的**（diff 相对第一父）。所以「merge commit 没有 diff」这个常见假设在这里不成立。

**组 B（侧分支有 2 个提交）**

```
commits in mb..main = 3
WITH --first-parent    : 1 行 = 9db0c89d…（merge commit 相对第一父的合并后 diff = f1+f2）
WITHOUT --first-parent : 2 行 = f00a20bf…(a2)、ada5a8de…(a1)
待判分支 D（内容 = 仅 a1）:
  MATCH with --first-parent?    False
  MATCH without --first-parent? True
```

**结论**：`--first-parent` 的作用是把 main 侧候选集从「**历史里任意提交**的内容」收窄成「**主线提交 + 各 merge commit 相对第一父的 diff**」。它**确实**减少候选（也就减少检出），但要说「否则 merge 子树污染映射」并不准确——被排除的那些侧分支提交，其内容**确实**已经在 main 里，把它们算作「疑似已合并」算不上污染。真实理由是**确定性 + 扫描深度可控**（配合 10000 提交上限）。

同时暴露一个实现硬约束：**两种模式下 patch-id 输出行数都 ≠ 提交数**（有 merge 时）。所以映射**必须**用第二字段（commit id）做键，不能按行序 zip。

### 1.5 误报面：**cherry-pick 是已证实的误报源**

fixture：`main` = 基线 → `u.txt` → 提交 X（新增 `shared.txt`）；分支 `y` 从基线 cherry-pick X（得到**不同 SHA、相同内容**的提交）。

```
main log: 4a90256 feat: add shared.txt / 5052992 chore: unrelated / 461aac0 chore: base
y    log: a61b3dc feat: add shared.txt / 461aac0 chore: base
is-ancestor y main        exit=1        → y 未合并
git branch --merged main  → main（不含 y）→ --merged 判定正确
topic 整段 patch-id       = 54ba390524c2698fdad47a2aeb1ec89679d3b3c5
main 侧逐 commit          = 54ba3905…(X) , c2b4ec96…
⇒ 命中 → 会把「未合并的 y」标成「疑似已合并」  ← 误报
对照分支 unrel           = 66e8045fa35d4a32797a525fe5984b0ac9e42285 → 不在 main 侧 → 不误报
```

这与官方文档对该命令的定位完全一致：「The main usecase for this command is to look for likely **duplicate commits**」——**内容重复 ≠ 已合并**。cherry-pick、`git format-patch | git am`、从同一 commit 派生的多个分支、以及「补丁被手工重放」，都会命中。

survey 提到的另一个误报面（理论碰撞）概率可忽略；**cherry-pick 不是理论问题，是必然命中的**，而 survey 通篇没提。

### 1.6 另两条边界（survey 提了但用的场景不同）

**【实测】分支在 squash 合并后又有新提交 → 正确地不命中：**

```
squash 后（feature 未变）      : topic 整段 = 9db0c89d…  main 侧含 9db0c89d…  → MATCH   ✅
feature 再加一个提交 f3 之后   : topic 整段 = e1684561…  main 侧不含          → NO MATCH ✅（不会误报）
```

这是「整段 range 当一个 patch」这个口径**唯一**的好处：合并不是全量时，净 diff 变了，自然不命中。（代价就是 1.2 的 rebase 失效。）

**【实测】main 在 squash 之后继续前进 → 仍然命中（口径对 main 前进是稳健的）：**

```
mb = merge-base(main, feature) 不随 main 前进而变
main 侧再追加一个提交 m2 后，原始 squash 的 patch-id 9db0c89d… 仍在 main 侧集合里 → 仍 MATCH ✅
```

### 1.7 「只报告不删」的取舍

**必须保留，理由比 survey 给的更强**：

1. survey 的理由是「内容哈希理论上可能碰撞」——概率极低，这条理由本身偏弱。
2. 真正的理由：**patch-id 命中的语义是「存在内容等价的提交」，而不是「该分支的提交都被 main 接纳」**。cherry-pick 场景下内容等价但分支未合并，语义上是**假阳性**，且我实测必然发生。用它做删除依据会删掉分支引用（对象还在，但要 GC 前才安全，对用户是「工作没了」的观感）。
3. 加上 1.3.3 的空白忽略、1.4.1 的上下文敏感、1.4.2 的路径参与、1.5 的 cherry-pick，命中集合是一个**有噪声的集合**，不适合当删除门槛。

**误报面汇总**（本轮实测）：

| 场景 | 会不会命中 | 判定是否正确 |
|---|---|---|
| squash 合并 | 会 | ✅ 正确（真已合并） |
| 多 commit rebase（邻近上下文未变） | 会（需两侧逐 commit 口径） | ✅ 正确 |
| 多 commit rebase（邻近上下文被改） | 不会 | ⚠️ 漏报 |
| 单提交 rebase | 会 | ✅ 正确 |
| cherry-pick 内容 | 会 | ❌ **误报** |
| 只改空白的差异 | 会 | ❌ **误报** |
| 与 base 无 diff 的空分支 | 不会（patch-id 无输出） | ✅ 不适用 |
| 合并后分支又有新提交 | 不会 | ✅ 正确 |
| main 在合并后继续前进 | 仍会 | ✅ 正确（稳健） |
| 无关分支（对照） | 不会 | ✅ 正确 |

### 1.8 对 attention 的具体建议

**落点**：`branch_cleanup_audit`（`.sh` + `.ps1` 成对）+ `references/scan-recipes.md`。

1. **新增字段，不进删除候选**
   - 字段名建议：`resubmitted_candidates`（「内容已在主分支出现过」）或 `squash_or_rebase_merged_candidates`。
   - 元素结构建议：`{ branch, tip_sha, evidence: "patch-id-match", matched_main_commit, compare_mode }`。
   - **不要**把命中项从 `local_stale_unmerged_report` 里搬走——它仍然「未合并」（ancestry 上确实不是祖先）。正确做法是**追加一个正交维度**：`stale_unmerged` 里每条加 `content_merged_suspected: true|false`，或单独输出一份映射。这样「真未合并」与「疑似已合并」在报告层可区分，而不是被替换。

2. **判定口径必须写成「两侧逐 commit」**
   - topic 侧：`git rev-list --no-merges <mb>..<branch>` → `git diff-tree --patch --stdin` → `git patch-id --stable` → 取第一字段集合。
   - main 侧：`git rev-list --no-merges <mb>..origin/$DEFAULT` → 同一条管道 → 取第一字段集合。
   - 判定：topic 侧集合 **⊆** main 侧集合（全部命中才叫「疑似已合并」；部分命中只写证据、不改标签）。
   - **不要**用「整段 range 当一个 patch」那一口径，它对多 commit rebase 无效（1.2）。
   - 用官方文档的 `--no-merges` 口径即可，**不必**依赖 `--first-parent` 的 merge-diff 行为（1.4.3 证明那层语义不好解释）；如果要用 `--first-parent`，只是为了让 main 侧扫描深度可封顶。

3. **必须的守卫（缺一不可）**
   - topic 侧 patch-id 输出为空 → 直接跳过该分支，不产出任何候选（1.3.1）。
   - 两侧同一个 `--stable`。
   - 用输出行的**第二字段**（commit id）做键；不要按行序 zip（有 merge 时行数对不上，1.4.3）。
   - 扫描上限沿用深度封顶（参考 nkt 的 10000），超限时置 `scan_truncated: true`，**并降级为「未判定」而不是「未命中」**。

4. **字段语义必须写清「不构成删除依据」**
   在 `scan-recipes.md` 该字段旁显式写：
   > 该字段是「内容等价」证据，**不是** ancestry 证据。cherry-pick、等价补丁重放、仅空白差异都会命中。**不得**据此删除本地或远程分支；命中项仍走「陈旧未合并 → 只报告不删」原路径。

5. **报告层**（`assets/templates/status-report.md`）
   主叙事里不要出现 `patch-id`；用人话表达，例如「有 3 个分支的内容看起来已经进过主线了（可能是 squash 或 rebase 合并的），但它们的分支记录没删——要不要我列给你看？」技术字段留到「📋 技术细节（可选）」。

6. **无脚本回退路径**
   在 `scan-recipes.md` 里给出**逐条可复制**的命令（不能只写字段名，参考 survey §7.6 B3 的老问题）。给 bash 与 pwsh 两版管道。

### 1.9 可复现命令序列（squash + rebase 两条）

```powershell
# ---- squash ----
$T="$env:TEMP\p2-squash"; git init -q --initial-branch=main $T; Set-Location $T
git config user.email t@e.x; git config user.name t
"base" | Set-Content base.txt; git add .; git commit -q -m base
git checkout -q -b feature
"a1" | Set-Content a.txt; git add .; git commit -q -m a1
"b1" | Set-Content b.txt; git add .; git commit -q -m b1
"a2" | Set-Content a.txt; git add .; git commit -q -m a2
$mb = git merge-base main feature
git checkout -q main; git merge -q --squash feature; git commit -q -m "squash feature"
git diff-tree -p $mb feature | git patch-id --stable
git log --first-parent --format='commit %H' -p "$mb..main" | git patch-id --stable   # 两行第一字段应相同

# ---- rebase（旧 ref 残留）----
$R="$env:TEMP\p2-rebase"; git init -q --initial-branch=main $R; Set-Location $R
git config user.email t@e.x; git config user.name t
"base" | Set-Content base.txt; git add .; git commit -q -m base
git checkout -q -b feature
"f1" | Set-Content f1.txt; git add .; git commit -q -m f1
"f2" | Set-Content f2.txt; git add .; git commit -q -m f2
"f3" | Set-Content f3.txt; git add .; git commit -q -m f3
git tag feat-old                       # 模拟「远端/本地 ref 未更新」
git checkout -q main; "m1" | Set-Content m1.txt; git add .; git commit -q -m m1
git rebase -q main feature; git checkout -q main; git merge -q --ff-only feature
$mb = git merge-base main feat-old
# ❌ survey 口径：整段 vs 逐 commit → 对不上
git diff-tree -p $mb feat-old | git patch-id --stable
git log --first-parent --format='commit %H' -p "$mb..main" | git patch-id --stable
# ✅ 正确口径：两侧都逐 commit
git rev-list --no-merges "$mb..feat-old" | git diff-tree --patch --stdin | git patch-id --stable | sort
git rev-list --no-merges "$mb..main"     | git diff-tree --patch --stdin | git patch-id --stable | sort
```

---

## 2. `gh api repos/{owner}/{repo}/rulesets` 的语义（P1-6 / §4.5【待复核】）

### 结论

**能做，且 `gh` 只读权限足够；但 survey §4.5 把端点用错了，会导致「看起来实现了、实际永远判不出来」。**

一句话：**不要遍历 `/rulesets` 再读 `/rulesets/{id}` 找 `rules[].type == "deletion"`，直接对每个候选分支调 `GET /repos/{o}/{r}/rules/branches/{branch}`，看返回数组里有没有 `type == "deletion"`。** 这个端点由服务端完成「哪个 ruleset 作用于这个 ref」和「enforcement 是否生效」的全部计算。

### 2.1 ① rulesets 与旧 branch protection API 的关系与差别

| 维度 | Rulesets | Legacy branch protection |
|---|---|---|
| 端点 | `GET /repos/{o}/{r}/rulesets`（列表）、`/rulesets/{id}`（详情）、**`/rules/branches/{branch}`（某分支实际生效的规则）** | `GET /repos/{o}/{r}/branches/{branch}/protection` |
| 层级 | 仓库级 + **组织级 + 企业级**（一次调用全汇总） | 仅仓库级 |
| 只读可读性 | **可读**。实测无认证访问 `https://api.github.com/repos/microsoft/vscode/rulesets` → **HTTP 200**；`/rules/branches/main` → **HTTP 200** | **不可读**。实测无认证 → **HTTP 401**；带 token 但非仓库管理员访问 `microsoft/vscode/branches/main/protection` → **HTTP 404**（GitHub 用 404 隐藏存在性，不是 403） |
| 目标类型 | branch / tag / push / repository | 只有 branch |

【实测】无认证对照：

```
list rulesets (public repo, no auth): 200
branch rules (no auth):               200
repos/microsoft/vscode/branches/main/protection (no auth): 401
repos/microsoft/vscode/branches/main/protection (authed, non-admin): 404
```

**这条差别直接决定立正的选择**：立正是只读审计、不假设自己是仓库管理员，所以 **legacy branch protection 这条线必须放弃**；rulesets 这条线可用。

### 2.2 ② 判定「禁止删除」应看哪个字段

**核心纠正（本轮最硬的发现）**：`GET /repos/{o}/{r}/rulesets`（**列表**端点）**不返回** `rules`、`conditions`、`bypass_actors`。

【实测】对 `microsoft/vscode` 的 4 个 ruleset 逐个探测键的存在性：

```json
{"id":5351760,"name":"microsoft-production-ruleset","enforcement":"active","target":"branch",
 "source":"microsoft","has_conditions":false,"has_rules":false,"has_bypass":false}
{"id":7988222,...,"has_conditions":false,"has_rules":false,"has_bypass":false}
{"id":17452597,...,"has_conditions":false,"has_rules":false,"has_bypass":false}
{"id":139683,...,"has_conditions":false,"has_rules":false,"has_bypass":false}
```

列表元素只有：`id / name / target / source / source_type / enforcement / created_at / updated_at / node_id / _links`。

所以 survey §4.5 写的「判断『能否删』：ruleset 的 `rules[]` 里出现 `type == "deletion"`」——**在列表端点上根本取不到 `rules[]`**。必须逐个 `GET /rulesets/{id}`，那又多一层调用，还要自己算 `conditions.ref_name` 匹配、还要自己过滤 `enforcement`、还要自己过滤 `target`（见下面的反例）。

**正确字段（推荐路径）**：

```
GET /repos/{owner}/{repo}/rules/branches/{branch}
→ 200 [ { "type": "deletion", "ruleset_id": 714773, "ruleset_source_type": "Repository", ... }, ... ]
```

- **`type == "deletion"` 命中 ⇒ 该分支禁止删除。** 就这一个字段够用。
- `ruleset_id` / `ruleset_source_type`（实测取值：`"Repository"`、`"Organization"`）可用于报告里说明「是谁在保护它」。
- `parameters` 只对 `pull_request`、`required_status_checks` 等类型有值，`deletion` 的 `parameters` 是 `null`。

【实测】`microsoft/vscode` 的 `/rules/branches/main`：

```json
[{"parameters":null,"ruleset_id":5351760,"ruleset_source_type":"Organization","type":"deletion"},
 {"parameters":null,"ruleset_id":5351760,"ruleset_source_type":"Organization","type":"non_fast_forward"},
 {"parameters":{...},"ruleset_id":5351760,"ruleset_source_type":"Organization","type":"pull_request"},
 {"parameters":null,"ruleset_id":7988222,"ruleset_source_type":"Repository","type":"deletion"},
 {"parameters":{...},"ruleset_id":7988222,"ruleset_source_type":"Repository","type":"copilot_code_review"}]
```

**关于 `enforcement` 和 `bypass_actors`**：

- `enforcement` 实测有三个取值：`active`、`evaluate`、`disabled`（例：`nodejs/node` 的 ruleset 714785 = `disabled`；`microsoft/vscode` 的 139683 = `evaluate`；`grafana/grafana` 的 17493884 = `evaluate`）。
- **`/rules/branches/{branch}` 已经替你过滤掉了非 active 的 ruleset**【文档原文】（https://docs.github.com/en/rest/repos/rules 的 "Get rules for a branch" 段）：
  > Returns all **active** rules that apply to the specified branch. The branch does not need to exist; rules that would apply to a branch with that name will be returned. All active rules that apply will be returned, regardless of the level at which they are configured (e.g. repository or organization). **Rules in rulesets with "evaluate" or "disabled" enforcement statuses are not returned.**
- 【实测】交叉验证：`nodejs/node` 的 ruleset 714785（`disabled`，规则 `update`，include `~DEFAULT_BRANCH`）在 `/rules/branches/main` 里**完全不出现**（按 `ruleset_id==714785 or type=="update"` 过滤 count=0）；`vscode` 的 139683（`evaluate`）同样不出现。
- **`bypass_actors` 只读拿不到**【文档原文】（https://docs.github.com/en/rest/repos/rules 的 "Get a repository ruleset" 段）：
  > Note: To prevent leaking sensitive information, the `bypass_actors` property is only returned if the user making the API request has write access to the ruleset.

  实测印证：本轮抓到的所有 ruleset 的 `bypass_actors` 一律是 `null`。**⇒ 只读审计下 `bypass_actors == null` 不能解读为「没有绕过者」，不能作为任何判定依据。**（这条对立正很重要：别把「有绕过者 ⇒ 保护形同虚设」写进文档，因为只读环境根本看不见。）
- **必须过滤 `target`**（若走遍历 rulesets 的路线）：`nodejs/node` 的 ruleset 17420826 是 `target: "repository"`，规则是 `repository_transfer/repository_create/repository_delete/repository_visibility`，`conditions.ref_name.include` 是**空数组**。天真地「在 rules 里找 deletion」会把它误当成「禁止删除分支」——**它的 `repository_delete` 是禁止删除整个仓库**，语义完全不同。

### 2.3 ③ 权限

【文档原文】（https://docs.github.com/en/rest/repos/rules）「Get rules for a branch」段：

> Fine-grained access tokens for "Get rules for a branch" … The fine-grained token must have the following permission set: **"Metadata" repository permissions (read)**. This endpoint can be used **without authentication** or the aforementioned permissions if only public resources are requested.

同页「Get a repository ruleset」段同样是 `Metadata (read)`。

【实测】`gh api` 走的是本地已有的 OAuth token；无认证 `curl` 对公开仓库同样是 200。**私有仓库需要该仓库的读权限**——本轮没有私有仓库可测，标为【未验证】。

**⇒ 立正的降级契约**：查询失败（无 `gh`、无网络、403/404、私有仓库无权限）时必须输出 `protection_status: "unverified"`，**绝不能**输出 `"unprotected"`。这与 AGENTS.md「『没查成』必须写成『没查成』」一致。

### 2.4 ④ `conditions.ref_name.include` 的形态

【实测】跨 10 个仓库采到 60+ 个 ruleset，`include` / `exclude` 的真实取值：

| 形态 | 实例 |
|---|---|
| 特殊值 `~DEFAULT_BRANCH` | `microsoft/vscode` 5351760、`nodejs/node` 4562796、`grafana/grafana`、`python/cpython` |
| 特殊值 `~ALL` | `nodejs/node` 612501/612512/612517、`grafana/grafana` 17493883/17493884、`python/cpython` 1609799/1609800 |
| 显式全路径 | `refs/heads/main`、`refs/heads/dev`、`refs/heads/stable`、`refs/heads/beta`（`rust-lang/rust`、`home-assistant/core`） |
| 通配 | `refs/heads/*`、`refs/heads/*/**/*`、`refs/heads/release/**/*`、`refs/heads/renovate/**` |
| 字符类/量词 | `refs/heads/v[2-9][13579].x-staging`、`refs/heads/release-*.*.*` |
| `exclude` 也有值 | `python/cpython` 13908145 exclude=`refs/heads/main,refs/heads/3.*`；`grafana/grafana` 8549063 exclude 一批 `release-13.[1-9]*` |
| **可以是空数组** | `nodejs/node` 17420826（`target: repository`） |

**结论**：
- `~DEFAULT_BRANCH` 与 `~ALL` **确实存在**（survey 的猜测成立）。
- 形态**不统一**：有特殊值、有 `refs/heads/` 全路径、有 glob。**自己实现匹配器是高风险低收益的**——这正是推荐直接调 `/rules/branches/{branch}` 的原因：让服务端做匹配。
- 若一定要本地匹配，至少要处理 `~ALL` / `~DEFAULT_BRANCH` / 带 `*` 与 `**` 的 glob / `[...]` 字符类，成本明显高于一次 API 调用。

### 2.5 ⑤ 分页与错误码【实测】

**分页**

- `GET /rulesets` **是分页的**。`per_page=1` 时响应头：

  ```
  HTTP/2.0 200 OK
  Link: <https://api.github.com/repositories/41881900/rulesets?per_page=1&page=2>; rel="next",
        <...&page=4>; rel="last"
  ```

- `gh api --paginate` 可正常工作（实测 4 个 ruleset 时两者数量一致）。
- **`GET /rules/branches/{branch}` 返回一个普通数组，实测未见分页**（vscode 5 条、nodejs 9 条、rust 13 条一次返回）。**注意**：这不是文档承诺，属【观测】，实现时若担心可显式加 `per_page=100`。

**错误码（`gh api` 的退出码）**

| 情形 | HTTP | `gh` 退出码 | 响应体 |
|---|---|---|---|
| 仓库不存在 | 404 | **1** | `{"message":"Not Found","documentation_url":"…/rules#get-all-repository-rulesets","status":"404"}` |
| ruleset id 不存在 | 404 | **1** | 同上（`…/rules#get-a-repository-ruleset`） |
| 路径写错（`/rules/{ref}`） | 404 | **1** | `{"message":"Not Found",…}` |
| **分支不存在** | **200** | **0** | **`[]`** |
| 无权限（私有仓库） | 403/404 | — | 【未验证】 |

**⚠️ 最容易踩的一条**：分支名不存在时 `/rules/branches/{branch}` 返回 **`[]` + 200**，而文档明说「The branch does not need to exist; rules that would apply to a branch with that name will be returned」——所以 `[]` 的语义是「**没有 active 规则作用于这个名字**」，**不是**「这个分支没有保护」这么简单（分支可能压根不存在，或者分支名拼错了）。实现里应先用本地 ref / `git ls-remote` 的结果确认分支确实存在，再把 `[]` 解读为「未受删保护」。

### 2.6 对 attention 的具体建议

**落点**：`branch_cleanup_audit`（.sh + .ps1 成对）+ `references/scan-recipes.md` + `references/branch-model-and-protection.md`。

1. **端点选择**：对**远程删除候选分支**逐个调
   ```
   gh api "repos/{owner}/{repo}/rules/branches/{branch}" \
     --jq '[.[] | select(.type=="deletion")] | length > 0'
   ```
   **不要**遍历 `/rulesets` + `/rulesets/{id}`。
2. **调用范围**：只对「已进入远程删除候选」的分支调用（通常个位数），不要对全部分支调用——省 API 配额，也避免无谓失败。
3. **JSON 契约新增字段建议**（三处同步：`scan-recipes.md` + `.sh` + `.ps1` + `evals/script-assertions.json`）：
   - `remote_delete_protection`: `"protected"` | `"unprotected"` | `"unverified"`
   - `remote_delete_protection_source`: 命中的 `ruleset_source_type`（`Repository` / `Organization`）或 `null`
   - `remote_delete_protection_warnings`: `[]`（例：`"gh 不可用，未验证分支保护状态"`）
4. **硬边界（写进 `references/branch-model-and-protection.md`）**：
   - `unverified` **不得**降级为 `unprotected`；报告主叙事里要说「**没能确认**它是否受保护」，不能说「它没受保护」。
   - `protected` 时**禁止**进入远程删除建议清单（与现有受保护名单同一层级）。
   - 只用 `type == "deletion"` 一个判据；**不要**依赖 `bypass_actors`（只读恒为 `null`）。
   - 分支名不存在时的 `[]` 要配合本地存在性检查，避免把「拼错名字」当成「没保护」。
5. **完全消除不可逆风险的备选**（survey §4.5 已提，仍成立，且成本为零）：建议用户在仓库设置里打开 **Settings → General → Pull requests → Automatically delete head branches**，让 GitHub 在合并时自己删源分支。立正只报告，不做远程删除动作。这条应作为**首选建议**写进报告，API 查询作为「用户不想开这个开关时」的兜底。

---

## 3. `--force-with-lease=<branch>:<sha>` 与远程分支删除（P2-16）

### 结论

**适用，而且是这个场景下正确的手段。** `--force-with-lease` 不是「只管 push」的选项——它的语义是对**「本次将要被更新的 ref」**做一次 compare-and-swap 检查，**删除也是一种 ref 更新**，所以 lease 同样生效。

实测：`git push origin --force-with-lease=<branch>:<sha> --delete <branch>` **合法，且确实会在 sha 不匹配时拒绝删除**（`stale info`，退出码 1）。而**不带 lease 的 `--delete` 会静默删掉确认窗口内他人推送的提交**（实测已复现数据丢失）。

### 3.1 实测矩阵【实测】

fixture：裸仓库 `origin.git`；`alice` 克隆并推 `main` + `topic`；`bob` 克隆后把 `topic` 前进一个提交并推送；此时 `alice` 的 `origin/topic` 是**过期**的。

```
alice remote-tracking (STALE) = 777fd9dced286369be8d57cd3cb6b81cdba7f83f
remote actual                = 752b4aba421a2fda0d06faa0d6bf11b46d4dccf3
```

| # | 命令 | 结果 | 退出码 |
|---|---|---|---|
| T1 | `git push origin --force-with-lease=topic:<stale> --delete topic` | `! [rejected] (delete) -> topic (stale info)` | **1** |
| T2 | `git push origin --delete topic --force-with-lease`（无显式值，用本地 remote-tracking） | `! [rejected] (delete) -> topic (stale info)` | **1** |
| T3 | `git push origin --delete topic`（**无 lease**） | `- [deleted] topic` ← **bob 的提交被静默丢弃** | 0 |
| T4 | `git fetch` 后 `--force-with-lease=b1:<current> --delete b1` | `- [deleted] b1` | 0 |
| T5 | `--force-with-lease=b1:<乱填的000…0>` `--delete b2`（lease 名字是**另一个**分支） | b2 **被删成功** | 0 |
| T6a | `--force-with-lease=b3:`（expect 不存在） `--delete b3`（b3 **存在**） | `! [rejected] (delete) -> b3 (stale info)` | **1** |
| T6b | `--force-with-lease=nosuchbranch:` `--delete b3`（lease 名字**打错**） | b3 **被删成功**（lease 落空 ⇒ 等于没有） | 0 |
| T7 | 删除一个不存在的远程分支 | `error: unable to delete 'topic': remote ref does not exist` | 1 |

T1/T2/T3 三条合起来就是完整答案：**有 lease → 拒绝；没有 lease → 静默删掉别人的提交。**

### 3.2 文档原文【文档原文】

https://git-scm.com/docs/git-push （`--force-with-lease` OPTIONS 段）：

> This option overrides this restriction **if the current value of the remote ref is the expected value**. `git push` fails otherwise.
> `--force-with-lease=<refname>:<expect>` will protect _`<refname>`_ (alone), **if it is going to be updated**, by requiring its current value to be the same as the specified value _`<expect>`_ (which is allowed to be different from the remote-tracking branch we have for the refname, or we do not even have to have such a remote-tracking branch when this form is used). **If _`<expect>`_ is the empty string, then the named ref must not already exist.**
> Note that all forms other than `--force-with-lease=<refname>:<expect>` that specifies the expected current value of the ref explicitly are **still experimental** and their semantics may change…
> A general note on safety: supplying this option **without an expected value**, i.e. as `--force-with-lease` or `--force-with-lease=<refname>` interacts very badly with anything that implicitly runs `git fetch` on the remote to be pushed to in the background…

同页 `-d` / `--delete` 段：

> All listed refs are deleted from the remote repository. This is the same as prefixing all refs with a colon.

注意这里**没有**任何「删除需要满足 fast-forward」的限制——这正是 T3 能静默丢数据的原因，也是必须显式加 lease 的原因。

**回答「有没有 lease 等价物」**：有，就是 `--force-with-lease=<refname>:<expect>` 本身，不需要 `git ls-remote` + 复核的两步法（但两步法也可以，见 3.3）。

### 3.3 正确命令与三个陷阱

**推荐形式（显式 sha，来自审计时的 `git ls-remote`）**：

```bash
sha=$(git ls-remote --heads origin "$branch" | awk '{print $1}')
[ -n "$sha" ] || { echo "远程分支不存在，跳过"; exit 0; }
git push origin --force-with-lease="$branch:$sha" --delete "$branch"
# 退出码 0 = 删除成功；非 0（stale info / remote ref does not exist）= 确认窗口内有变化，中止并重新审计
```

**陷阱一：lease 的 refname 必须与要删的分支完全一致。**
T5/T6b 实测：lease 写在别的名字上（哪怕写错一个字母）对目标 ref **不施加任何保护**，删除照常成功。所以不能把 lease 写成一个固定字符串。

**陷阱二：优先用「显式 sha」形式，别用裸 `--force-with-lease`。**
文档明说无显式值的形式「still experimental」且与后台 `git fetch` 交互很差。立正本来就在审计阶段用 `git ls-remote` 拿到了 sha，**没有理由**退化成依赖 remote-tracking ref。

**陷阱三：不要用「expect 不存在」的形式来做删除。**
T6a 显示 `--force-with-lease=<branch>:` 在分支存在时会被拒（语义上是「我期望它不存在」），用在删除场景只是绕远路；直接用当前 sha 更直白。

**两点法（等价，无需 lease）——不推荐但可行**：

```bash
# 审计时记录 sha_audit；执行删除前重新确认
sha_now=$(git ls-remote --heads origin "$branch" | awk '{print $1}')
[ "$sha_now" = "$sha_audit" ] || { echo "窗口内有变化，中止"; exit 1; }
git push origin --delete "$branch"
```

**为什么仍推荐 lease**：两点法有一个「检查与删除之间」的窗口（TOCTOU），lease 把检查和删除做成服务器端原子的。立正的定位是「远程不可逆动作需最终确认」，lease 是同一哲学的技术实现。

### 3.4 对 attention 的具体建议

**落点**：`SKILL.md` 的远程删除动作说明 + `references/branch-model-and-protection.md` + `branch_cleanup_audit` 输出的 `tip_sha` 字段。

1. **远程删除一律带 lease**，命令模板固定为
   `git push origin --force-with-lease=<branch>:<sha> --delete <branch>`，
   其中 `<sha>` 取审计阶段 `git ls-remote` 的返回值。
2. **`branch_cleanup_audit` 必须为每个远程分支候选输出 `tip_sha`**（现在契约里有没有要在 `scan-recipes.md` 确认；没有就补，三处同步），否则执行阶段拿不到 lease 期望值。若 sha 缺失，**不得**降级为无 lease 删除——应中止并说明原因。
3. **退出码语义写进 SKILL.md**：非 0 且输出含 `stale info` ⇒ 说明确认窗口内分支被改动，**必须**中止本次删除、回去重新审计，**不得**盲目重试。
4. **删除不存在的远程分支**（`remote ref does not exist`，T7）应视为**幂等成功**（目标状态已达成），在报告里说明「该分支已不存在」，**不要**当成错误让用户以为操作失败。
5. **明确否定**「用 `git push --force-with-lease --delete`（无参数）」这种写法：虽然实测 T2 也能拒绝，但它依赖本地 remote-tracking ref，文档点名它是 experimental 且与后台 fetch 冲突。建议在 references 里写死「**必须显式带 `<branch>:<sha>`**」。

---

## 4. worktree 检出检查（P2-15）

### 结论

**能做，格式稳定，判定方法明确。但它不是安全修复，只是报告友好度改进**——实测 `git branch -d` **和** `git branch -D` **都会拒绝**删除被 worktree 检出的分支。所以 survey 的定位（「`-d` 会拒绝所以不会真出事，但报告更友好」）**方向正确**，本轮进一步确认 `-D` 也拦得住（survey 没提 `-D`）。

### 4.1 `--porcelain` 实测形态【实测】

fixture：主 worktree（main）、一个路径含空格的 linked worktree（feature）、一个 detached HEAD 的 linked worktree。

```
[worktree C:/Users/cgart/AppData/Local/Temp/attn-p2/wt/main repo]
[HEAD b97be74aef5c5630f8da2a9e0a50cc919608c5e2]
[branch refs/heads/main]
[]
[worktree C:/Users/cgart/AppData/Local/Temp/attn-p2/wt/detached dir]
[HEAD b97be74aef5c5630f8da2a9e0a50cc919608c5e2]
[detached]
[]
[worktree C:/Users/cgart/AppData/Local/Temp/attn-p2/wt/linked with spaces]
[HEAD b97be74aef5c5630f8da2a9e0a50cc919608c5e2]
[branch refs/heads/feature]
[]
```

（`[` `]` 是我为了看清空行加的。）

**格式规则（实测 + 文档原文）**：

- 每个 worktree 一个**块**，块之间用**一个空行**分隔（最后一行的尾随空行不一定有，**按块解析，不要按「空行数」解析**）。
- 第一行固定 `worktree <path>`。**路径不加引号**，空格原样保留；Windows 下用正斜杠。
- 第二行固定 `HEAD <40 位十六进制>`。
- 第三行二选一：`branch refs/heads/<name>` **或** `detached`。**detached 时没有 branch 行**——这是判定时最容易踩的点。
- 可选行：`bare`、`locked [<reason>]`、`prunable <reason>`。
- 【实测】顺序：主 worktree 恒在第一（与文档一致），其余按路径排序（我按 `linked with spaces` → `detached dir` 的顺序创建，输出里 `detached dir` 在前）。**⇒ 不要假设「创建顺序」。**
- 【文档原文】（https://git-scm.com/docs/git-worktree ）：
  > `--porcelain`: With `list`, output in an easy-to-parse format for scripts. This format will remain stable across Git versions and regardless of user configuration. **It is recommended to combine this with `-z`.**
  > `-z`: … This makes it possible to parse the output **when a worktree path contains a newline character**.
  > List details of each worktree. The main worktree is listed first, followed by each of the linked worktrees. The output details include whether the worktree is bare, the revision currently checked out, the branch currently checked out (or "detached HEAD" if none), "locked" if the worktree is locked, "prunable" if the worktree can be pruned…
  > Unless `-z` is used any "unusual" characters in the lock reason such as newlines are escaped and the entire reason is quoted as explained for `core.quotePath`.

  ⇒ 想彻底稳妥就用 `-z`（NUL 分隔），否则**只解析 `branch ` 行**（见 4.2），**绝不要**用 `-split ' '` 对 `worktree ` 行取字段。

### 4.2 稳健判定方法

**目标**：给定分支名 `B`，判断它是否被某个 worktree 检出。

**推荐（一次调用，只认 `branch ` 行，完全不碰路径）**：

```bash
# 只取被检出的分支名（不含 refs/heads/ 前缀；detached 的块不产出任何行，天然被忽略）
git worktree list --porcelain | sed -n 's|^branch refs/heads/||p'
# 判定
if git worktree list --porcelain | sed -n 's|^branch refs/heads/||p' | grep -Fxq -- "$B"; then
  echo "分支 $B 正在被 worktree 检出"
fi
```

要点：
- **只匹配 `^branch refs/heads/` 开头的行** ⇒ detached HEAD、bare、prunable 的块自动不参与，不需要特殊处理。
- `grep -Fxq`（**整行精确匹配**）而不是 `grep -q`，避免 `feature` 命中 `feature-x`。
- **完全不需要解析路径**，所以「路径含空格」这个问题根本不会出现。
- 如果确实要报出「在哪个路径」，那就用「块」解析：以空行为分隔符切块，块内取第一行去掉字面前缀 `worktree `（**保留剩余原文，不 trim 内部空格**）。

**pwsh 版对应写法**：

```powershell
$checkedOut = (git worktree list --porcelain) |
  Where-Object { $_ -like 'branch refs/heads/*' } |
  ForEach-Object { $_.Substring('branch refs/heads/'.Length) }
if ($checkedOut -contains $B) { "分支 $B 正在被 worktree 检出" }
```

（`-like` + `Substring` 避开 `-split` 的空白陷阱；`-contains` 大小写不敏感，与 git 分支名语义一致。）

### 4.3 它其实是安全冗余，不是安全修复【实测】

```
$ git branch -d feature         # feature 被 linked worktree 检出
error: cannot delete branch 'feature' used by worktree at 'C:/Users/cgart/AppData/Local/Temp/attn-p2/wt2/linked'
exit=1

$ git branch -D feature         # 即使强删也拦得住
error: cannot delete branch 'feature' used by worktree at 'C:/Users/cgart/AppData/Local/Temp/attn-p2/wt2/linked'
exit=1

$ git worktree remove .../linked --force
$ git branch -d feature
Deleted branch feature (was deddc8b).
exit=0
```

⇒ 这条**不可能**造成数据丢失。它的价值只有一个：**别让用户在报告里看到一条「建议删」、执行时却报错的候选**（那会让用户怀疑整个 skill 的判断力）。

### 4.4 对 attention 的具体建议

1. **定位**：只做**报告层过滤**，不新增 JSON 契约字段。在生成本地删除建议清单时，把「被 worktree 检出的分支」移到「不删（原因：正在别的目录里被检出）」一栏，附上路径。
2. 若确实要进 JSON，字段名建议 `checked_out_worktrees: [{branch, path}]`，且**明确写清它不是删除判定的输入**（因为 git 已经拦住了）。
3. **实现口径**：按 4.2 的 `^branch refs/heads/` 单行匹配，**不要**解析路径、**不要** `-split`。
4. **不要**在文档里把它写成「防止误删」——它不是；写成「避免给出无法执行的建议，报告更准确」。
5. **注意**：worktree 只检出本地分支，远程分支不受影响；这条只作用于本地删除路径。

---

## 5. LICENSE `spdx_id` 检查（P2-14）

### 结论

**能做，但必须分成两条路径**：

- **有 `gh` + 有网络**：直接读 `spdx_id`，准确、零推断。这是主路径。
- **无 `gh` / 无网络 / 私有仓库无权限**：**做不到**判定。只能给一个**弱信号**（「你的 LICENSE 不是标准许可证全文的精确副本 ⇒ GitHub 很可能识别不出」），并且这个信号有实测的边界（见 5.3）。
- **绝对不要**在文档里写「追加多少字符就会失效」这类具体阈值——5.3 的数值来自我的复刻，**不是** licensee 本体运行结果，边界敏感度约 ±1%，不足以支撑硬编码。

### 5.1 GitHub 如何识别【文档原文】+ 识别算法【文档原文/复刻】

**文档原文**（https://docs.github.com/en/rest/licenses/licenses ，raw: `https://raw.githubusercontent.com/github/docs/main/content/rest/licenses/licenses.md`）：

> GitHub uses the open source Ruby Gem **Licensee** to attempt to identify the license for a project. Licensee matches the **contents of a project's `LICENSE` file** (if it exists) against a short list of known licenses. As a result, **the API does not take into account the licenses of project dependencies** or other means of documenting a project's license such as references to the license name in the documentation.
> If a license is matched, the license key and name returned conforms to the **SPDX specification**.

**识别算法**（读 `licensee/licensee` 源码，分支 `main`）：

| 事实 | 出处 |
|---|---|
| 置信度阈值 = **98**（百分比） | `lib/licensee.rb`: `CONFIDENCE_THRESHOLD = 98` |
| 匹配器链 = **Copyright → Exact → Dice** | `lib/licensee/project_files/license_file.rb`: `possible_matchers` |
| Dice 判定要求 `similarity >= 98` **且** `bigram_similarity >= 49` | `lib/licensee/matchers/dice.rb` |
| `similarity = overlap * 200 / (词集大小之和 + 归一化字符长度差 / 4)` | `lib/licensee/content_helper/similarity_methods.rb` |
| 词元正则 = `/(?:[\w\/-](?:'s\|(?<=s)')?)+/`，Ruby 的 `\w` **只认 ASCII** ⇒ **中文字符不产生词元** | `lib/licensee/content_helper.rb` |
| 归一化会剥离标题/版本/URL/注释/分隔线/HTML、统一大小写、统一英美拼写变体、规范化项目符号；`strip_copyright` 只在「整个文件就是版权行」或开头段落含 `All rights reserved.` 时才剥离 | `content_helper/normalization_methods.rb`、`content_helper/constants.rb` |
| Copyright 匹配器命中时返回伪许可证 `no-license`（置信度 100） | `lib/licensee/matchers/copyright.rb` |
| 只认固定文件名模式（`LICENSE`=1.00、`LICENSE.md`=0.95、`COPYING`=0.90、`COPYRIGHT`=0.35、`PATENTS`=0.15…） | `lib/licensee/project_files/license_file.rb`: `FILENAME_REGEXES` |

**关键含义**：识别失败的原因**不止「追加了额外内容」一种**——

1. **额外内容**（追加/前置第三方声明、README 式说明）→ 词集 overlap 下降 **且** 长度差惩罚上升 → 跌破 98。
2. **纯中文附加文字** → 不进词集（不损 overlap），但**仍通过「长度差/4」拉低分数**（见 5.3，这个效应比想象的大）。
3. **只有版权声明没有许可证正文** → Copyright 匹配器命中 `no-license` → NOASSERTION（这是**正确行为**，不是 bug）。
4. **文件名不被识别** → 叫 `LICENCE`、`license.txt.bak` 之类的会直接找不到。

### 5.2 我的复刻与两点校准【复刻】

我按上面这些源码逐条转写了一份 PowerShell 实现（唯一已知偏差：`variation_adjusted_length_delta` 里的 `spdx_alt_segments` 未知，我按 0 处理），并用**真实 GitHub 结果做两点校准**：

```
参考 = licensee/choosealicense.com 的 _licenses/mit.txt 正文（1064 字符，98 词）
CALIBRATION cli/cli LICENSE     (GitHub 说 MIT)         sim = 99.48%  bigram = 97.73%  → 判 MIT         ✅ 与 GitHub 一致
CALIBRATION nodejs/node LICENSE (GitHub 说 NOASSERTION)  sim = 0.55%                  → 判 NOASSERTION ✅ 与 GitHub 一致
```

⇒ 复刻至少在「明显是 MIT」和「明显不是」两端与真实结果一致，可以用来做**相对比较**；但**边界附近**（97–99%）的绝对数值不可信。

### 5.3 追加内容实验【复刻】

以 MIT 正文为基准，追加内容：

| 变体 | similarity | 结果 |
|---|---|---|
| 原样（只差版权行具体值） | 100.00% | MIT |
| 末尾追加**一行中文版权声明** | **97.59%** | **NOASSERTION** |
| 末尾追加一行 `All rights reserved.` | 98.08% | MIT |
| 末尾追加**一句英文**（`This project is maintained by volunteers.`） | **94.12%** | **NOASSERTION** |
| 标题后插入一行中文注释 | 98.46% | MIT |
| 末尾追加 100 个中文字 | 90.46% | NOASSERTION |
| 末尾追加 30 个英文词 | 71.18% | NOASSERTION |

追加英文填充词的断点扫描：

```
+ 1 词（+7 字符）  → 99.48%  仍 MIT
+ 2 词（+14 字符） → 98.46%  仍 MIT
+ 3 词（+21 字符） → 97.09%  ← 跌破
```

只追加中文字符时的断点扫描：

```
+ 10 个中文字 → 99.87%  仍 MIT
+ 20 个中文字 → 98.59%  仍 MIT
+ 40 个中文字 → 96.12%  ← 跌破
```

**由此得到三条可用的判断**：

1. **`git-repo-hygiene` 的「中文版权署名不影响识别」这个绝对表述不成立。** 追加一行中文版权声明（约 25 字符）在我的复刻里就已经掉到 97.59%。它的失真机制**不是**中文进不了词集（确实进不了），而是**归一化字符长度差 / 4 这一项**。
2. **`git-repo-hygiene` 的「NOASSERTION 的根因几乎总是：标准许可证正文后面追加了额外内容」也不完整。** 至少还有：只有版权声明（Copyright 匹配器 → `no-license`）、纯中文附加（长度惩罚）、文件名不被识别、`All rights reserved.` 类的可剥离变体（反而可能仍被识别）。
3. **阈值是「98%」而不是「差不多像就行」**，所以「正文后面随便加一段说明」的做法确实高风险——但**具体多少字符会死不能硬编码**（我的复刻有 ±1% 边界误差）。

### 5.4 观测证据【观测】

| 仓库 | `license.spdx_id` | LICENSE 情况 |
|---|---|---|
| `LinnnnYue/git-repo-hygiene` | `MIT` | 干净 |
| `cli/cli` | `MIT` | 1068 字节，标准 MIT |
| `Tencent/weui` | **`NOASSERTION`** | 14391 字节：**开头**是腾讯声明 + 一堆第三方依赖许可证，MIT 正文在**结尾** |
| `nodejs/node` | **`NOASSERTION`** | 154603 字节：MIT 正文 + 巨量第三方声明 |
| `dromara/hutool` | `MulanPSL-2.0` | 9549 字节，含 **1011 个中文字符** → **仍被识别**（因为该许可证模板本身就是中文的） |
| `apache/incubator-answer` 等 8 个 | 各自正确 | 标准全文，无附加 |
| `521xueweihan/HelloGitHub`、`ruanyf/weekly`、`jackfrued/Python-100-Days` | `license: null` | **完全没有 LICENSE 文件** |

**API 形态【实测】**：

```
GET /repos/{o}/{r}/license   → 200
  { "path": "LICENSE", "sha": "...", "size": 1068, "encoding": "base64", "content": "<base64>",
    "license": { "key": "mit", "name": "MIT License", "spdx_id": "MIT" } }

# 未识别时： key = "other", spdx_id = "NOASSERTION", name = "Other"
# 无 LICENSE 文件时： HTTP 404
  {"message":"Not Found","documentation_url":"https://docs.github.com/rest/licenses/licenses#get-the-license-for-a-repository","status":"404"}
  （`gh` 退出码 1；仓库对象的 `.license` 为 null）

# 另外：仓库对象本身就带这个信息，一次调用就够
gh api repos/{o}/{r} --jq '.license.spdx_id'
```

### 5.5 可离线 / 可降级的方案

**分级（建议按此实现）**：

| 级别 | 条件 | 动作 | 输出 |
|---|---|---|---|
| L1 | `gh` 可用且 `gh api repos/{o}/{r} --jq '.license.spdx_id'` 成功 | 直接读结果 | `license_spdx_id`（值），`license_check: "verified"` |
| L2 | `gh` 不可用 / 网络失败 / 非 GitHub 远端 | **不做识别**，只做「本地 LICENSE 是否像标准全文」的弱检查 | `license_check: "unverified"` + `warnings[]` |
| L3 | 仓库根没有 `LICENSE*` / `COPYING*` / `COPYRIGHT*` | 直接报「未找到许可证文件」 | `license_file_present: false` |

**L2 的弱检查（纯离线，只做保守提示）**：

1. 找文件：根目录下匹配 `LICENSE*` / `LICENCE*` / `COPYING*` / `COPYRIGHT*`（大小写不敏感）。
2. 读正文，**归一化**：统一大小写、折叠所有空白、去掉 Markdown 标记与 HTML 注释、去掉 URL、去掉分隔线。
3. 与内置的少数几个标准许可证全文（至少 MIT、Apache-2.0、BSD-3-Clause、GPL-3.0、MPL-2.0、Unlicense）做归一化后的**包含/相等**比较。
4. 判定：
   - 归一化后**完全相等**（忽略空白与版权占位）→ 基本可认定会被识别（`suspected_ok`）。
   - 归一化后**包含**标准全文但**有额外内容** → 报「正文之外还有额外内容，**GitHub 可能识别不出**」。只提示，**不**判定失败。
   - 都不是 → 报「**未能判定**」（`unverified`），**不要**说「不是标准许可证」。

**为什么不建议离线复刻 Dice**：需要许可证词集与完整归一化实现（还要处理英美拼写变体、CC 误报规则、bigram 二道门槛），且 5.2 已证明边界不可靠。**规则化的「有/没有额外内容」更稳，也更好解释给用户。**

### 5.6 对 attention 的具体建议

**落点**：`SKILL.md` Phase 3B 第 5 步（核心文档同步）+ `references/core-docs-sync.md` + `references/scan-recipes.md`（若加字段）。

1. **触发条件**：在**已有 `gh` 且远端是 GitHub** 时才走 L1；否则走 L2/L3。这与立正「`gh` 可选」的约定一致——**不能**把 `gh` 变成这一项的硬依赖。
2. **严重级别**：`NOASSERTION` 只做 **`WARNING`／提示**，**不阻塞**提交与 PR。理由：这是**平台展示问题**，不是代码问题；而且合法场景（`nodejs/node` 的巨型聚合 LICENSE）本来就存在。不要把它放进「文档同步门槛」的**失败**分支。
3. **报告措辞**（大白话）：「GitHub 没能自动认出这个项目的开源协议——常见原因是 LICENSE 文件里除了协议正文之外还混了别的内容。要不要我看一下？」**不能**说「你的许可证不对」。
4. **`unverified` 必须显式**：无 `gh` 时报告里要写「**没能查** GitHub 侧的识别结果」，不能省略、也不能写成「看起来没问题」。
5. **不要写死阈值**：任何「追加超过 N 个字符就会失效」的说法都不要进文档。要写就写成规则：「正文之外有额外内容 ⇒ 存在识别不出的风险」。
6. **可以稳定写进文档的一条事实**：licensee 只匹配 **`LICENSE` 文件内容**，**不看依赖的许可证、不看 README 里提到的协议名**（5.1 文档原文）。所以「README 写了 MIT，LICENSE 文件缺失」这种仓库会被判 `null`——这是立正可以稳定报出来的信号。

---

## 6. `gitignore_consistency_audit`（第 6 个采集脚本）是否值得做

### 结论

**能力值得有；「第 6 个采集脚本」这个形态不值得。**

理由分两半：**实现成本确实极低**（核心检测就是一条命令），但**它不属于立正的定位**，而且引入一个脚本的**真实成本不在脚本本身，而在契约同步链**。建议把它做成「**references 里的一组可复制命令 + Phase 1 快照里的一个提示**」，而不是新增 `scripts/*.sh` + `scripts/*.ps1`。

### 6.1 实现成本：比想象的还低【实测】

核心检测**一条命令**就能拿到「所有被 .gitignore 规则命中、却仍被 git 跟踪的文件」：

```bash
git ls-files -ci --exclude-standard
```

fixture 实测（`.gitignore` 含 `preview3.py`、`*.log`、`/keep.log`、`build/`；`archive/preview3.py` 与 `tracked.log` 都已跟踪）：

```
$ git ls-files -ci --exclude-standard
archive/preview3.py
tracked.log
```

这一条同时钓出 `git-repo-hygiene` 说的两类病根里的第 2 类（「规则写在 .gitignore 里但对已跟踪文件无效」），并且**顺带证明了第 1 类**（`preview3.py` 无前导斜杠 ⇒ 匹配到 `archive/` 下面）。

**一个必须知道的坑**：`git check-ignore` **默认不报已跟踪文件**：

```
$ git check-ignore tracked.log          → 无输出，exit=1   ← 会让人误以为"规则没写"
$ git check-ignore -v --no-index tracked.log
.gitignore:2:*.log	tracked.log                              ← 加 --no-index 才能看到
```

⇒ 如果按直觉用 `git check-ignore` 逐条规则试，会得到**系统性错误的结论**（把所有「对已跟踪文件失效」的规则都判成「没问题」）。正确的两条命令是 `git ls-files -ci --exclude-standard`（找受害文件）和 `git check-ignore -v --no-index <path>`（找是哪条规则命中）。

**「无前导斜杠」这条 lint 也能离线做**：纯文本分析 `.gitignore`（去掉空行与 `#` 注释，找那些既不以 `/` 开头、也不以 `**/` 开头、又不含 `/` 的模式），再对每个命中用 `git check-ignore -v --no-index` 复核实际匹配到的路径层级。成本仍然很低。

### 6.2 定位判断：不属于立正的核心

| 维度 | 立正 | 这个能力 |
|---|---|---|
| 核心承诺 | 「同步与发布就绪」（拉取、提交、文档同步、版本一致、开 PR） | 「仓库卫生／可交接性」 |
| 与立正流程的关系 | — | **完全不进任何一条现有闸门**：不影响拉取、不影响提交、不影响文档同步门槛、不影响版本一致性、不影响 PR |
| 触发时机 | 每次立正都会用到 | 只有用户主动关心才会用到 |
| 与硬禁止清单的关系 | 立正**禁止**把文件纳入 `.gitignore` | 这是检测**用户自己**做了这件事的后果——属「事后体检」，不是「流程闸门」 |
| 生态对标 | survey §3.1 已认定 `git-repo-hygiene` 与立正**互补而非重叠**（43 个能力点 0 项完全对应） | 同上 |

survey §3.1.2 自己也写了：「立正硬禁止『纳入 `.gitignore` 文件』，但这两条陷阱描述的是**用户可能自己手动做的动作**」——**这正是它不该进主流程的证据，而不是该进的理由**。

### 6.3 建议：做「能力」，不做「脚本」

**不建议新增第 6 个采集脚本的理由（成本侧，对照 AGENTS.md）**：

1. **契约三处同步**：AGENTS.md 明写「改契约要三处同步：`scan-recipes.md` + `.sh` + `.ps1` + `evals/script-assertions.json`」。一个字段就是四处，且这是历史上漂移的根因。
2. **双实现**：`.sh` / `.ps1` 两套，且必须**行为同形**（survey §7.1–7.3 已证明这条线在立正自己的历史里翻过车）。
3. **断言表**：每加一个字段就要在 `evals/script-assertions.json` 加断言（且 AGENTS.md 规定不得为变绿而放宽）。
4. **fixture 成本**：要覆盖「无前导斜杠」「对已跟踪文件无效」「同类文件一半入库一半忽略」「`--no-index` 陷阱」等至少 4 个正负例，成对写进 `evals/fixtures.ps1` / `fixtures.sh`。
5. **收益错配**：新增一个脚本是「维护成本永久 + 每次立正都跑」的成本，换来的是一次性体检能力——与 P2 的定位不匹配。

**建议的落地形态（推荐）**：

1. `references/common-pitfalls.md`（survey P2-12 已列）里加一节「`.gitignore` 规则失效」，包含：
   - 两条权威命令（`git ls-files -ci --exclude-standard`、`git check-ignore -v --no-index <path>`）；
   - `git check-ignore` 默认看不到已跟踪文件这个陷阱（**最容易误判的地方，必须写**）；
   - `.gitignore` 对已跟踪文件无效这条机制说明。
2. **Phase 1 快照**里加**一个提示性检查**（不进 JSON 契约、不新增脚本）：跑一次 `git ls-files -ci --exclude-standard`，有输出就在报告末尾提一句「仓库里有 N 个文件同时被 `.gitignore` 规则命中、但仍在版本控制里——规则对它们不起作用」。**只提示，不修**（立正不做文件移动，见 survey P4）。
3. 如果未来真要做成脚本，前提是先有 `evals` 覆盖，并明确它**不参与任何闸门判定**。

**一句话**：**这是一个好 wiki 条目，不是一个好脚本。**

---

## 7. 我认为 survey 里证据不足 / 需要修正的结论

按「我最想改的」排序。

### 7.1 【最想推翻】「patch-id 方案对 squash/rebase 都有效」（survey §4.1、§4.2、`branch-cleanup-tools.md` §3.1 CASE 3）

**survey 的说法**：
- `docs/ecosystem-survey.md` §4.2：「业界有成熟解法（patch-id 比对）」、「patch-id 是内容哈希，忽略 commit 身份，只比 diff 内容，而 squash/rebase 都保留了 diff 内容」；§8 P2-10 给出实现口径「topic 侧算整段 range 当一个 patch，main 侧算逐 commit」。
- `branch-cleanup-tools.md` §3.1 CASE 3 用「patch-id(main since mb, 1st-parent)」命中的实测输出作为 rebase 有效的证据。

**为什么证据不足**：
1. 那个口径在数学上**不可能**匹配多 commit rebase：两侧一个是「N 个提交合成 1 个 patch-id」，一个是「N 个提交各 1 个 patch-id」。只有 N==1 才会相等。
2. CASE 3 的输出只显示了**一行** main 侧 patch-id，等于自证了那次实验的 main 侧只有单个贡献提交——**场景退化成近似单提交**，没有覆盖「feature 有多个提交 + main 侧有多个提交」这个真实情况。
3. 本轮实测反例（1.2）：`topic 整段 = e1684561…`，main 侧逐 commit = `44b87cc3 / f00a20bf / ada5a8de / 3bbd1990`，**交集为空**。而把 topic 侧也改成逐 commit，`44b87cc3 / f00a20bf / ada5a8de` **三个全部命中**。
4. 官方文档自己给的示例就是**两侧逐 commit + `--no-merges` + `sort`/`join`**（1.2 引文），不是「整段 vs 逐 commit」。

**要定论需要什么**：一个 feature 有 ≥2 个提交、main 侧有 ≥2 个提交的 rebase fixture，把两侧 patch-id 集合都完整打印出来做交集。本轮已做（1.2、1.9 有完整可复现命令）。

**影响**：如果按 survey 的 P2-10 口径实现，**立正只会在 squash 场景下报出结果，rebase 场景永远报 0 条**——而 survey 恰恰把这个能力的主要卖点写成「同时抓 squash + rebase」。这是个会「看起来做完了、实际一半没工作」的坑。

### 7.2 【应修正】rulesets 的 `rules[]` 与 `/rules/{ref}`（survey §4.5、§8 P1-6）

**survey 的说法**：
> - `GET /repos/{o}/{r}/rulesets` — 返回数组
> - `GET /repos/{o}/{r}/rules/{ref}` — 列出实际作用于某 ref 的规则
> - 判断「能否删」：ruleset 的 `rules[]` 里出现 `type == "deletion"`

**三处问题**：
1. `GET /repos/{o}/{r}/rulesets`（列表）**返回的元素里没有 `rules`**（也没有 `conditions`、`bypass_actors`）——【实测】4 个 vscode ruleset 全部 `has_rules: false`。所以「在列表返回值的 `rules[]` 里找 deletion」**取不到数据**。
2. `GET /repos/{o}/{r}/rules/{ref}` **不存在**——【实测】`gh api repos/microsoft/vscode/rules/main` → HTTP 404 `{"message":"Not Found"}`。正确路径是 `/rules/branches/{branch}`。
3. 没提 `enforcement` 与 `target` 两个必要的过滤维度：
   - `enforcement` 实测有 `active` / `evaluate` / `disabled` 三个值；`evaluate`（vscode 139683）和 `disabled`（nodejs 714785）的规则**不生效**。
   - `target` 实测有 `branch` / `repository`；`nodejs/node` 17420826 的规则里有 **`repository_delete`**（禁止删除仓库）却不是 `target: branch`。

**修正后的正确写法**（建议直接替换 survey §4.5 那三条）：
> - `GET /repos/{o}/{r}/rulesets` — 返回 ruleset **摘要**数组（分页；不含 `rules` / `conditions` / `bypass_actors`）
> - `GET /repos/{o}/{r}/rules/branches/{branch}` — 返回**某分支实际生效的 active 规则**，含组织级与企业级；服务端已过滤 `evaluate` / `disabled`
> - 判断「能否删」：该数组里存在 `type == "deletion"`
> - 只读凭据（`Metadata: read`，公开仓库甚至无需认证）；`bypass_actors` 只读恒为 `null`，不可用

**要定论需要什么**：本轮已定论（2.2–2.5 有全部实测输出与文档原文）。

### 7.3 【方向对、结论错】「被 skip 的 job 会上报 Success，不会阻止合并」（survey §6.3 第 479 行）

**survey 的说法**：
> ⚠️ 一个容易被忽略的绕过点：被 skip 的 job 会上报 "Success"，不会阻止合并——即使是 required check。所以立正若建议项目配置 required status checks，必须同时禁用 workflow 的 skip 选项。

**官方文档原文**（https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks 的 "Handling skipped but required checks" 表格；raw: `https://raw.githubusercontent.com/github/docs/main/content/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks.md`）：

| Cause | Result | How to fix or check |
|---|---|---|
| A **workflow** is skipped by path filtering, branch filtering, or a commit message | Associated checks **stay in a "Pending" state and block merging** | Avoid requiring workflows that can be skipped. |
| A **job** is skipped by a conditional | The job reports **"Success"** | … |
| A **job depends on a failed job** | The dependent job is skipped and **may not block merging** | Use `always()` with `needs` … |

同页另有：
> Successful check statuses are `success`, `skipped`, and `neutral`.

以及一节「Checks from some workflow jobs are not evaluated」：由 `workflow_dispatch` 等**非白名单事件**触发的 workflow，其 checks **不满足** required status check（白名单：`push`、`pull_request`、`pull_request_review`、`pull_request_target`、`deployment`、`deployment_status`）。

另据 `…/managing-protected-branches/about-protected-branches.md`：
> Required status checks must have a `successful`, `skipped`, or `neutral` status before collaborators can make changes to a protected branch.

**问题在哪**：
- survey 把「**workflow** 被 skip」和「**job** 被 skip」混为一谈，并且把结论按相反的方向写了：**workflow 级 skip 的后果是 checks 停在 Pending、合并被卡住**（不是「不会阻止合并」）。
- 真正的「静默放行」发生在 **job 级 `if:` 条件**、以及 **`needs` 依赖失败作业**这两种情况——survey 完全没提。
- 还有第三类完全没提的绕过：**触发事件不在白名单里**（例如 `workflow_dispatch`），它的 check 根本不参与 required 判定。

**修正后的建议文本**（可替换）：
> 若建议项目开启 required status checks，需要同时检查四件事：① 被设为 required 的 workflow 不要用 `paths` / `branches` 过滤器或 `[skip ci]`（否则 checks 停在 Pending，**永远合不进去**——这是卡死风险，不是放行风险）；② required 的 job 不要挂 `if:` 条件（被条件跳过的 job 上报 Success，形同虚设）；③ 依赖其他 job 的 required job 要配 `always()`；④ workflow 的触发事件必须在 `push` / `pull_request` / `pull_request_review` / `pull_request_target` / `deployment` / `deployment_status` 之内。

**要定论需要什么**：本轮已从官方文档定论（表格已明确写「Pending state and block merging」）。这是一条**可以只用文档改掉**的结论。

### 7.4 【绝对化表述，证据不足】LICENSE 的两条「几乎总是」式结论

**survey 转述 `git-repo-hygiene` 的两条**（survey §3.1.1 第 4/10 项、§3.1.2）：
> `NOASSERTION` 的根因「**几乎总是**：标准许可证正文后面追加了额外内容」
> 「**中文版权署名不影响识别**」

**为什么证据不足**：
1. 这两条是转述**另一个 skill 的 SKILL.md**，不是一手验证，却被写成了接近事实的强断言。
2. 本轮【复刻】+【观测】给出的是一个**更弱、但可操作**的版本：
   - 「追加额外内容」确实是主因（`Tencent/weui`、`nodejs/node` 两个真实 `NOASSERTION` 仓库都符合），**但**不是「几乎总是」——还有「只有版权声明没有正文」（Copyright 匹配器直接给 `no-license`）、「文件名不被识别」、「仓库压根没有 LICENSE 文件」这几种。
   - 「中文版权署名不影响识别」在**我的复刻里不成立**：追加约 25 字符的中文版权行 → 97.59% → 跌破 98。机制是 licensee 的**归一化字符长度差 / 4** 惩罚项，而不是词元（中文确实不进词集，但长度惩罚照样生效）。
3. 我的复刻在边界附近有约 ±1% 的不确定度（`spdx_alt_segments` 未知），所以**我也不敢给出「多少字符会死」的硬阈值**——但「追加一行中文版权声明就可能失效」这个**方向**是清楚的，与「不影响」相反。

**要定论需要什么**：
- 最硬的证据是**受控实验**：建若干仓库（干净 MIT / MIT + 一行中文版权 / MIT + 一句英文 / MIT + `All rights reserved.`），推到 GitHub，读回 `spdx_id`。本轮**没有做**（我没有可推送的仓库），所以这一条只能给到「复刻 + 观测」的强度。
- 次优证据是**大规模观测**：抓几百个已知 `NOASSERTION` 的仓库，把它们的 LICENSE 与标准全文做归一化 diff，统计「多出内容」「只有版权」「文件名异常」各占多少。本轮只采了 20 个仓库，样本量不足以定「几乎总是」。
- 建议 survey 把这两条降级为【待复核】，并改写成 5.5 / 5.6 那种「规则化 + 保守提示」的表述。

### 7.5 其它证据偏弱、本轮也没能补上的（诚实列出）

| survey 处 | 结论 | 为什么不足 | 需要什么 |
|---|---|---|---|
| §7.3 | `.ps1` 的 `release_involved` 恒为 `false` 的**根因推测**（路径分隔符/根不一致） | survey 自己标了【推断】；本轮**刻意未验证**，因为 `scripts/` 正被另一个子代理修改，跑脚本会拿到不稳定结果，且该结论最终必须靠读实现源码 + 变量级打印定论 | 在 `scripts/` 冻结后：① 读 `.ps1` 里 `version_files[].file` 的构造与比较表达式；② 在同一 fixture 上给两侧比较表达式加临时打印（在**副本**上做，不改仓库）；③ 用 `evals/fixtures.ps1` 的 Cargo/多生态 fixture 复跑 |
| §6.3 | 「Rulesets 能强制的规则清单」与「不能强制的 6 项」 | 清单里【观测】成分大；本轮只验证了「如何在 API 里读到生效规则」，**没有**逐条验证每个 rule type 的实际强制语义（例如 `non_fast_forward` 在有 bypass 角色时是否真拦得住） | 对 `available-rules-for-rulesets` 文档逐条对照 + 在可写测试仓库里实际触发 |
| §5.3 | 「lockfile 是版本一致性的双源」【待复核】 | 本轮未读 release-please 策略源码，也未做实验 | 读 release-please `src/strategies/*.ts` 对应行 + 在真实 fixture 上跑一次包管理器安装，观察 lockfile 是否自动同步根 `version` |
| §7.6 B5 | 「`core_docs_relevance_scan` 用 basename 匹配会造成**大量**误报」 | 【推断】，没有量化。「大量」是多少、在什么仓库规模下，没有数 | 选 3–5 个真实多语言仓库（含 `index.js` / `main.go` / `__init__.py` / `mod.rs` 同名文件）跑一遍，统计 `docs_needing_update` 条数与其中真正误报的占比 |
| §4.4 | 「立正用 `git ls-remote` 缓存 + `grep -Fq` 直接比对真实存在性 … 比 nkt 更干净」 | 本轮**未读** `branch_cleanup_audit` 源码（避免与另一个子代理冲突），无法独立确认行号与实现 | 冻结后读 `.sh:46-47` / `.ps1` 对应处，并跑一次 `git ls-remote origin` 检查是否有 `--heads` 限定（不加会把 tag 也算进来） |
| §6.1 | 「prek 的真实仓库是 `j178/prek` … 被 29+ 项目采用」 | 本轮未复核（与 P2 无关），仅记录 | 查 `j178/prek` 的 README 与实际采用清单 |
| §4.1 | 「nkt/git-cleanup 的 patch-id 全量比对能同时抓 squash + rebase」 | 本轮**未读** nkt/git-cleanup 源码（只用了 survey 转述的行号），因此无法确认它自己是不是也用了「整段 vs 逐 commit」——如果它也是，那它就是有同样的 bug，而不是「标杆」 | 读 `cli_diff_patchid()`（survey 称 line 614–638）与 `cli_main_patchids()`（survey 称 line 564–609）原文，确认两侧是否都逐 commit |

---

## 附录 A：本轮实际跑过的实验 fixture 位置

全部在系统临时目录（**未在仓库内建任何 fixture**）：

```
%TEMP%\attn-p2\repo\        squash 场景
%TEMP%\attn-p2\rebase\      多 commit rebase + 旧 ref 残留
%TEMP%\attn-p2\edge\        空 diff / 空白 / 文件顺序 / 路径 / 行号
%TEMP%\attn-p2\edge3\       行号位移 vs 上下文变化隔离实验
%TEMP%\attn-p2\cp3\         cherry-pick 误报 + 对照分支
%TEMP%\attn-p2\fp\ fp2\     --first-parent 语义对照（1 提交 / 2 提交侧分支）
%TEMP%\attn-p2\squash-plus\ squash 后再加提交 / main 前进
%TEMP%\attn-p2\push2\       force-with-lease 删除矩阵 T1–T3
%TEMP%\attn-p2\push3\       T4–T7（正确 lease、ref 作用域、expect-absent）
%TEMP%\attn-p2\wt\  wt2\    worktree --porcelain 与删除拒绝
%TEMP%\attn-p2\gi\          .gitignore 规则失效检测
%TEMP%\attn-p2\licsim.ps1   licensee 相似度复刻脚本
%TEMP%\attn-p2\docs\        抓到的官方文档与源码原文缓存
```

## 附录 B：本轮实际访问过的外部来源

**GitHub REST / 官方文档**
- https://docs.github.com/en/rest/repos/rules （"Get rules for a branch"、"Get a repository ruleset"、"Get all repository rulesets"）
- https://raw.githubusercontent.com/github/docs/main/content/rest/licenses/licenses.md
- https://raw.githubusercontent.com/github/docs/main/content/rest/repos/rules.md
- https://raw.githubusercontent.com/github/docs/main/content/rest/branches/branch-protection.md
- https://raw.githubusercontent.com/github/docs/main/content/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets.md
- https://raw.githubusercontent.com/github/docs/main/content/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches.md
- https://raw.githubusercontent.com/github/docs/main/content/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks.md
- https://raw.githubusercontent.com/github/docs/main/data/release-notes/enterprise-server/3-18/4.yml （排查文档路径时读到，与结论无关）

**Git 文档**
- https://git-scm.com/docs/git-patch-id ／ https://raw.githubusercontent.com/git/git/master/Documentation/git-patch-id.adoc
- https://git-scm.com/docs/git-push ／ https://raw.githubusercontent.com/git/git/master/Documentation/git-push.adoc
- https://git-scm.com/docs/git-worktree ／ https://raw.githubusercontent.com/git/git/master/Documentation/git-worktree.adoc

**licensee 源码**
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee.rb
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee/content_helper.rb
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee/content_helper/normalization_methods.rb
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee/content_helper/similarity_methods.rb
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee/content_helper/constants.rb
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee/matchers/dice.rb
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee/matchers/exact.rb
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee/matchers/copyright.rb
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee/project_files/license_file.rb
- https://raw.githubusercontent.com/licensee/licensee/main/lib/licensee/license_field.rb
- https://raw.githubusercontent.com/github/choosealicense.com/gh-pages/_licenses/mit.txt
- https://raw.githubusercontent.com/github/choosealicense.com/gh-pages/_data/fields.yml （licensee 内置路径为 `vendor/choosealicense.com/_data/fields.yml`）

**真实 API 调用（`gh api` / `curl`，全部只读 GET）**
- `repos/microsoft/vscode/rulesets`、`repos/microsoft/vscode/rulesets/139683`、`repos/microsoft/vscode/rules/branches/main`
- `repos/nodejs/node/rulesets`、`repos/nodejs/node/rulesets/714785`、`repos/nodejs/node/rules/branches/main`
- 另有 `cli/cli`、`kubernetes/kubernetes`、`rust-lang/rust`、`home-assistant/core`、`grafana/grafana`、`python/cpython`、`torvalds/linux`、`psf/requests`、`pallets/flask` 等共 19 个仓库的 rulesets 采样
- `repos/{o}/{r}`（取 `.license.spdx_id`）与 `repos/{o}/{r}/license`：`LinnnnYue/git-repo-hygiene`、`cli/cli`、`nodejs/node`、`torvalds/linux`、`Tencent/weui`、`dromara/hutool`、`521xueweihan/HelloGitHub` 等 20+ 个
- `https://api.github.com/...` 的**无认证**对照请求（rulesets / rules/branches / branches/*/protection）
