# 常见坑：你"做了但没生效"的那类

> 与 `autonomy-and-safety.md` 的"永远禁止"互补：那是**不许做**，这里是**你以为生效了、其实没有**。
> 第 1–6 条与第 8 条附实测命令与现象；第 7 条是重复违规的处置原则（属流程规则，无实测命令）。
> 立正的巡检发现这类问题时要**说明为什么没生效**，而不是只说"已加入 .gitignore"。

## 1. `.gitignore` 的模式没写前导斜杠 → 匹配到不该匹配的层级

**实测**（仓库内 `deep/nest/vendor/lib.txt` 未被跟踪）：

| `.gitignore` 内容 | `git check-ignore --no-index -q deep/nest/vendor/lib.txt` |
|---|---|
| `vendor/` | **命中**（忽略任意层级的 vendor 目录） |
| `/vendor/` | 不命中（只忽略**仓库根**的 vendor 目录） |

- **影响**：把名字通用的目录写成 `build/`、`vendor/`、`dist/`，会连带忽略子目录里的同名目录——可能把要发布的东西忽略掉，或反过来让本该忽略的深层目录被抓进版本库。
- **建议**：只想忽略根目录时写 `/name/`；确实要全局忽略才用 `name/`。**没有前导斜杠不代表"相对当前目录"**（.gitignore 没有相对当前目录的概念）。
- **判据**：`git check-ignore --no-index -v <path>` 会打印命中的规则行。

## 2. `.gitignore` 对**已跟踪**文件无效

**实测**：文件先提交 → 再写进 `.gitignore` → 再修改，`git status` **仍报** ` M keep.txt`；`git ls-files` 仍列出它。

- **影响**：用户以为"忽略就完事了"，但文件仍会出现在每次 diff 里，也会随提交一起进入后续版本。
- **正解**：`git rm --cached <path>` 解除跟踪（**保留工作区文件**），再配合 `.gitignore` 才是真正的"停止跟踪"。批量目录同理：`git rm -r --cached <dir>`。
- **判据**：`git ls-files --error-unmatch <path>`（exit 0 = 已跟踪）。**不要**只用 `check-ignore` 判断（见下一条）。

## 3. `git check-ignore` 默认会跳过已跟踪路径（调试陷阱）

**实测**：`deep/nest/vendor/lib.txt` 被 `git add` 跟踪后——

| 命令 | 结果 |
|---|---|
| `git check-ignore -q <path>`（默认） | **不命中**（exit 1） |
| `git check-ignore --no-index -q <path>` | 命中（exit 0） |

- **原因**：默认会查索引，已跟踪路径视为"未被忽略"。于是**规则明明生效，却显示没生效**，很容易误改成更激进的规则。
- **用法**：排查**规则本身**用 `--no-index`；判断"这个文件现在会不会被提交"要**叠加跟踪状态**（`git ls-files`）。

## 4. 被忽略的文件 `git add` 会**拒绝**（而非静默跳过）

**实测**：`git add deep/nest/vendor/lib.txt` → exit **1**，报 `The following paths are ignored by one of your .gitignore files`；`git add -f` → exit 0。

- **影响**：在自动化流程里 `git add -A` 之后若期望"文件都在索引里"，被忽略的路径不会在——不要把它们当作"已加入"。
- **变体**：想保留忽略规则但强制纳入个别文件，用 `!` 例外规则或 `git add -f`；两者语义不同（前者长期有效，后者一次性）。

## 5. 判定"忽略"与"跟踪"时，请同时看两个维度

| 维度 | 判据 | 说明 |
|---|---|---|
| 是否被规则忽略 | `git check-ignore --no-index <path>` | 只看规则，不看索引 |
| 是否被跟踪 | `git ls-files --error-unmatch <path>` | 只看索引 |

四个组合都可能出现，**结论完全不同**：
- 忽略 + 未跟踪 → 正常（不会被提交）
- 忽略 + **已跟踪** → 规则没起作用（需 `git rm --cached`）
- 未忽略 + 未跟踪 → 会出现在 `git status` 的 untracked 里
- 未忽略 + 已跟踪 → 正常跟踪
## 6. 删除远程分支不带 lease → 静默丢掉别人的提交

**实测**（本地裸仓库 + 两个 clone 复现）：审计时 `topic` 指向 `A`；在"等你确认"的窗口里另一个人往 `topic` 推了 `B`；此时执行不带 lease 的 `git push origin --delete topic` —— **删除成功，但 `B` 永久丢失**（远程分支连同其中的提交一起没了）。

- **正解**：`git push origin --force-with-lease=<branch>:<sha> --delete <branch>`，`<sha>` 用**审计时记录**的 tip。sha 不匹配时报 `! [rejected] (delete) -> <branch> (stale info)` 并退出 1 —— 这正是我们要的"发现变了就停"。
- **三个陷阱**：
  1. lease 的 refname 必须与分支**完全同名**；写错名字等于没有 lease，删除**照样成功**（实测）。
  2. 用**显式 sha**，不要用裸 `--force-with-lease`（git 文档点名后者 experimental，且会与本地的后台 fetch 打架）。
  3. 删除一个**已不存在**的远程分支是**幂等成功**，不要报成失败。
- **落点**：`branch_cleanup_audit` 为每个远程候选输出 `tip_sha`；删除时照抄这个 sha。

## 7. 同类问题第三次出现 → 散文约束不够，该上机制

**判据**：同一条规则被违反 **3 次**（3 个分支、3 份文档、3 个版本文件、3 次提交）——说明它靠"说"已经管不住了。

- **为什么是 3**：第一次是意外，第二次是巧合，第三次是**结构性缺口**。继续写更多散文只会让规则更长而不更有效。本仓库自己吃过这个亏：`AGENTS.md` 写明"改脚本要成对"，`docs/QUALITY-AUDIT.md` 的 D1–D11 里仍有成对漂移。
- **该做什么**：把这条规则变成**机器可判**的形式，而不是再写一遍：

  | 重复问题的形态 | 换成什么机制 |
  |---|---|
  | 版本文件总是不一致 | 提交前钩子跑 `version_consistency_audit`，不一致就拦 |
  | 文档总是滞后于代码 | CI 跑 `core_docs_relevance_scan` + 人工确认清单 |
  | 提交信息不守规约 | `commitlint`（`commit-msg` 钩子） |
  | 分支命名混乱 | pre-push 钩子校验分支名 |

- **立正的职责边界**：**只建议，不擅自装钩子**。装钩子会改用户的开发流程，属"本地变更需计划批准"，且可能与他们既有的 pre-commit 框架（husky / pre-commit / lefthook）冲突。写进报告的建议里，由用户决定。
- **报告话术**：说"同一类问题这次出现了 N 处，光靠约定可能不够——建议加一条自动检查，要我帮你配吗？"，而不是把同一条建议重复 N 遍。

## 8. 同一份生成产物把几十个仓库同时变脏 → 修在全局 exclude，不是逐仓库 `.gitignore`

**判据**：批量扫一批仓库的 `git status --porcelain`，绝大多数报的是**同一个**未跟踪路径（例如 `?? .gitea/`）。这不是 30 个问题，是 1 个问题——先把句柄归类，再决定在哪一层修。

```bash
# 先归类：同一条路径命中了多少仓库？
for d in /d/github-repos/*/; do (cd "$d" && git rev-parse --git-dir >/dev/null 2>&1 && printf '%s ' "$(basename $d)" && git status --porcelain | head -5); done
```

**为什么不能逐仓库改 `.gitignore`**：这类目录是**机器本地状态**（生成脚本的产物：CI 工作流镜像副本、编辑器导出目录等），不属于仓库语义内容。写进仓库的 `.gitignore` 等于把一台机器的本地约定强加给所有 clone，而且 N 个仓库 = N 次提交，噪音大、必然遗漏。

**正解**：写进全局排除文件，一处覆盖全部仓库。

```bash
git config --get core.excludesfile        # 常见 ~/.gitignore_global；返回空说明没配，才需要新建
cp "$HOME/.gitignore_global" "$HOME/.gitignore_global.bak-$(date +%Y%m%d)"
# 追加规则后再验证
git check-ignore -v .gitea/                # 命中即生效
git status --porcelain                     # 该仓库不再报这一条
```

改完重跑全仓扫描，用"脏仓库数从 N 降到 M"作为验收——不是看单仓干净了就收工。

- **例外**：确认该目录确实属于仓库内容时（`git ls-files <dir>` 在**任何**仓库返回非空），说明有人有意提交过它，那就在那个仓库单独处理，不要用全局规则把已跟踪内容一并"隐藏"（已跟踪文件本来也不受 ignore 影响，见第 2 条）。全局规则只该吃掉"从未被提交、也不该被提交"的生成物。

## 9. 外部 CLI 依赖只按裸命令名解析 → 明明装好了却报 not found

- **失误形态**：脚本写 `execFile('some-cli', args)`，而官方安装器把二进制放进 `~/.some-cli/bin/` 且**不修改 `PATH`** → 机器上装好了、手打命令能跑，从脚本调用却 `ENOENT`，报出来像是"没安装"。
- **规则**：按 `环境变量覆盖` → `PATH` → `安装器默认目录` 三级解析，逐个试、遇 `ENOENT`/`EACCES` 才换下一个；最终失败时**把试过的路径全部列进错误信息**，否则下一个人只会重复猜。
- **配套**：`EACCES` 同样当"该候选不可用"继续试，不要直接判"未安装"；把覆盖用的环境变量名写进文档（它同时也是用户绕过探测的手段）。

## 10. 工具输出被脱敏 → 把好文件当坏的改

- **现象**：读 `git diff` / `grep` / 文件内容时，授权头与密钥形状的字符串会被运行时替换成 `***`、`{{SECRET_xxx}}` 一类占位；于是 `Authorization: Bearer ${key}` 显示成 `Authorization: *** ${key}`，看起来像语法错误或已被破坏。
- **规则**：**先核实字节再动手**。用不改写内容的取证方式——`sed -n '<n>p' <file> | base64 -w0`（或 `od -c`）——确认原文，再决定改不改。凭脱敏后的显示去"修"文件，会把正常代码改坏。
- **反向同理**：报告与回复里引用密钥类字符串时要自己脱敏，取证命令的原始输出不要贴进面向用户的正文。

## 11. 验证门禁把外部限制判成失败 → 假红，真故障被淹没

- **反复出现**：逐个后端/依赖实跑时，未认证限流（GitHub 约 10 次/分钟）、缺 key、依赖未安装都会返回 0 条结果 → 门禁变红；红几次之后看门的人开始无视红色，真故障就藏进去了。
- **规则**：结果分三档——**真故障（红，计入失败退出码）**、**外部限制（黄，不计入退出码）**、通过。可容忍判据按错误文本匹配（`rate-limited` / `missing key` / `not configured` / `not found`），黄色输出要写明"为什么不算失败"。
- **配套**：同一份门禁脚本由 CI 直接调用（`run: bash scripts/gate.sh`），本地与 CI 只有一份实现，才不会漂移成两套判据。

## 12. 换行符让格式门禁假红 → 几十个文件"需要重排"几乎一定不是格式问题

- **现象**：`core.autocrlf=true` 的 Windows 工作区是 CRLF，仓库里存的是 LF。`ruff format --check src/` 在本地报 "N files would be reformatted"，而 CI（Linux、LF 检出）全绿。照着报告跑 `ruff format`，会把这些本来干净的文件重写成 LF——接下来 `git status` 报 7 个 ` M`，`git diff --numstat` 却只有 1 个文件有内容差异，形成一串"改了但 diff 为空"的幽灵脏态。
- **判据**：同一条命令在 LF 副本上重跑之后再决定改不改：

  ```bash
  scratch="$LOCALAPPDATA/hermes/cache/scratch/fmt"   # 任意 scratch 目录
  for f in $(git ls-files 'src/*.py'); do mkdir -p "$scratch/$(dirname $f)"; tr -d '\r' < "$f" > "$scratch/$f"; done
  cp pyproject.toml "$scratch/" && (cd "$scratch" && python -m ruff format --check src/ --config pyproject.toml)
  ```

- **两个陷阱**：
  1. `git archive` **也按 `core.autocrlf` 转换**，拿它"导出干净副本"照样是 CRLF，假红不会消失；文件级可靠取法是 `git show HEAD:<path> | tr -d '\r'` 或直接 `tr -d '\r'` 工作区文件。
  2. `git status` 在 stat 缓存未刷新时会把内容相同的文件报成 ` M`；以 `git diff --numstat`、`git hash-object <path>` 与 `git rev-parse HEAD:<path>` 是否相等为准。
- **规则**：门禁红之前先问"这个门禁是在哪个平台上绿的"。真格式问题通常一两个文件；**同一目录下大半文件同时"需要重排"，先怀疑换行，不要动手重写**。

## 13. 门禁是手写脚本但没声明入口 → `test_commands` 为空，被读成"没有验证"

- **现象**：仓库确实有可运行的闸门（`node scripts/verify-*.mjs`、`bash scripts/gate.sh`），但巡检输出的 `next_steps_analysis.test_commands` 是 `[]` —— 采集器只认标准入口（`package.json` 的 `scripts`、`Makefile` 目标、`pyproject` 的测试配置），手写脚本不在其中。
- **为什么危险**：这是"把没查成写成没有"的具体形态。报告里一旦出现"无测试命令"，后续"验证通过才合并"就失去载体，合并门 L1 也会被误判成通过。
- **正解（择一，并在报告里写明用的是哪种）**：
  1. 把闸门挂到标准入口：一个只含 `scripts` 的 `package.json`（如 `"test": "node scripts/verify-skill.mjs"`，零依赖、不加构建步骤），或 `Makefile` 的 `test:` 目标；
  2. 不动仓库结构时，直接在报告里给出真实命令与其退出码含义，并注明"采集器扫不到，因为它不是标准入口"——不要让空白字段替你说话。
- **判据**：`test_commands` 非空且逐个实跑 exit 0；为空但仓库确有闸门 → 按第 1 条修。

## 14. 检查 / 修复收口时报“成功”，但命令本身是空转 → 假的绿

三类实测形态（都表现为“报告说好了，实际没发生”）：

| 形态 | 实测表现 | 为什么骗过你 |
|---|---|---|
| 探测 / 健康检查 URL 已失效 | 端点返回 HTTP 404（某 API 从 `/api/formulae/.git` 迁到 `/api/formula.json`），探针把“通道不可用”当结论，`--repair` 还据此触发多余修复 | 健康检查测的是 **URL 存活**，不是通道本身；404 是探针坏了，不是网络坏了 |
| 修复命令调了工具**不存在的子命令** | 形如 `tool config set KEY VAL`，可该工具根本没有 `config set` 子命令；调用被 `try/except: pass` 吞掉，`applied` 列表照写“已设置” | 只剩退出码 / 异常被吞，日志却有成功文案——典型的“做了但没生效” |
| 外部流程自述“已修复” | 别的 agent / 流程扔进来的审查报告声称“已修复 step 4”“已改 URL”，但工作树里源文件**根本没动** | 报告是**声明**，不是**证据** |

- **规则**：把“成功”当作待验证的断言，而不是事实。
  - 探测 / 健康检查 URL：写进代码前**当场 live-verify**（手动请求确认 200/30x），别照搬旧文档；旧 URL 变 404 时，问题在探针不在通道。
  - 修复 / 写配置命令：先确认子命令真实存在（`<tool> <subcommand> --help` 退出 0），并对“异常被吞后仍报成功”保持警惕——`except ...: pass` 旁边的成功文案是红灯，不是绿灯。
  - 外部产物的自述状态：拿仓库真实 `git diff` / 文件内容核对，claim 与 diff 不符就按“未做”处理，不要照单全收或直接提交。
- **判据**：改完不是看“命令跑完了没报错”，而是看**被改的那处真的变了**（`git diff` 有内容、`curl -I` 是 200、配置文件内容真变了）。

## 15. 包导入失败 / 测试收集失败 → 先怀疑解释器漂移，不是代码坏了

**实测形态**：`pytest` 报 `ModuleNotFoundError: No module named '<pkg>'`，看起来像包源码坏了；实际是 `pip` 把包装进了解释器 A，而 `python` 解析到解释器 B（例如一个被激活的 venv），两者不是同一个；同一会话里 `python` 甚至可能**换指向**（不同调用落到不同 venv / 系统解释器）。

- **规则**：`No module named <pkg>` / `No module named pytest` 先当**环境问题**，不是代码缺陷。
  - 用**显式解释器路径**跑（`"C:/.../python.exe" -m pytest`），别用裸 `python`。
  - 确认装在哪：`python -c "import sys; print(sys.executable)"` 与 `pip --version` 的 interpreter 是否一致。
  - 开发装一次：`pip install -e .` 后，用**同一个**解释器跑测试。
- **为什么危险**：把环境问题写成“测试失败 / 代码破损”，会让立正的 verify 步骤假红，进而要么误报阻塞、要么在错误结论上继续改代码。

## 16. CI job 几秒内零步骤失败 → 先查计费/额度，别当代码问题

**现象**：PR 的 CI 一个 job 在 2 秒内失败，`steps: []`（零步骤），依赖它的 job 全部 `skipping`；而本地同一套 lint / test 全绿。

**判据**（任一即可确认是外部阻塞，不是代码）：`gh run view <run-id>` 的 ANNOTATIONS 出现 `recent account payments have failed or your spending limit needs to be increased`；或 `gh api repos/{owner}/{repo}/actions/jobs/<job-id>` 的 `steps` 为空、`started_at`/`completed_at` 只差几秒。

- **为什么骗人**：只看 `gh pr checks` 的 `fail` 会当成代码红，进而去改本来绿的代码；也会把“runner 没起”误报成“测试没过”。
- **runner 起不来时，如何证明代码 CI-ready**：用**同一个显式解释器**实跑 CI 的每条 check 命令（照 workflow 原文：`ruff check` / `ruff format --check` / `mypy` / `pytest`）；对**行尾敏感**的门禁（如 version-sync 里 `grep '^version:' | sed`，CRLF 会留 `\r` 导致假失败），用 `git show HEAD:<file> | tr -d '\r'` 模拟 Linux LF 检出后再比对（同 #12）。
- **解除阻塞**：私有仓库转 public（标准 runner 免费，转前先扫敏感信息），或去 GitHub Billing 补支付方式 / 提额度。**这是用户的决定，不要擅自改仓库可见性。**
- **报告口径**：CI 是 `BLOCKED`（外部原因），不是 `FAILED`（代码问题）；不要把“runner 没起”写成“测试失败”。

## 17. 数字类陈述各自生长 → 断言/检查数在多份文档里同时腐烂

**现象**：评测基准从 81 条断言长到 83、checks 从 553 跑到 557，而 `README`、`AGENTS.md`、开发计划文档、验证文档四份各自写着旧数字。只改一处，另外三处继续说谎，而且**没人会去核对**——数字看起来最像事实。

- **规则**：做完改动立刻 grep 全仓同步，一次改完：

  ```bash
  grep -rnE '[0-9]+ 条断言|[0-9]+ checks|[0-9]+ 个 fixture' --include=*.md .
  ```

- **更好的做法**：这类数字**只在一处权威**（评测基准文件或验证文档的“当前结果”表），其余文档写“见 XXX”而不复述具体数字。
- **同一类还包括“版本号要改几处”**：文档写死“三处/五处”，而 CI 门禁后来多加了一个版本文件（`pyproject.toml`、SKILL.md frontmatter 之类）——门禁因此红，而照着文档改的人永远少改一处。判据：把门禁脚本 / `docs-check` 的检查项逐条列出来，与文档里的“N 处”对照；数字要由门禁清单生成，不凭记忆写。
- **不要回改历史记录**：CHANGELOG 旧版本条目、历史验收表里的数字是**当时的真实值**，改了反而毁掉可追溯性；只改“描述当前状态”的那些句子。

## 18. PR 有合并冲突 → `pull_request` workflow 根本不跑，“no checks reported”不是 workflow 写错

**现象**：push 到 PR 分支后，`gh pr checks <n>` 报 `no checks reported on the '<branch>' branch`，`gh run list --branch <branch>` 只剩几天前的旧红；而 workflow 语法没问题、本地命令全绿。

**机制**：`pull_request` 类 workflow 跑在 GitHub 造出的 merge ref 上；PR 与默认分支冲突时造不出 merge ref，**一次 run 都不会产生**。于是“没检查”被误读成“workflow 坏了 / 没配好”，去改本来正确的 workflow 文件。

**判据**：`gh pr view <n> --json mergeable,mergeStateStatus` → `CONFLICTING` / `DIRTY` 即为此症。

- **规则**：先解冲突（`git fetch origin && git merge origin/<default>`，冲突处取真实意图再 push），**push 之后才会有第一次真实 run**。
- **解完冲突还要再 push 一次**：历史失败的 run 不会被自动重跑，旧的 5 秒红会继续挂在 PR 上，看起来像没修好；要重跑的是**新一次事件**，不是旧 run。
- **workflow 只在 tag / release / 手动触发时才有 run**（`release: published`、纯 `workflow_dispatch`）：不要为了“看到检查”造一个空提交，用 `gh workflow run <wf> --ref <branch> [-f dry_run=true]` 在分支上实跑；带 dry-run 开关的发布类 workflow 正好用它验证打包与凭据而不发布。
- **汇报口径**：**没有 run ≠ 通过**，与 #16 的 `BLOCKED` 同级——报告里写“PR 无检查（原因：冲突 / 仅 release 触发）”，不要写“CI 已过”。

## 19. 只更新流程文档、不更新仓库自己的任务清单 → 下一个读者读到“没有这件事”

**现象**：能力/阶段已经实现并写进流程文档，但仓库自带的开发计划（`docs/DEVELOPMENT-PLAN.md`、`ROADMAP.md`、`TASKS.md` 一类）仍停在上一阶段：进度区不列它、待办里没有它、验收条件也没写。下一次立正（或别的 agent）读计划文档时看到的就是“这件事不存在”。

- **规则**：把“仓库自带的计划/任务清单”当核心文档集的一员。新增阶段或能力后同步三件事：
  1. **进度区**加一行，状态用可判标记（✅ 完成 / 🔶 部分 / ⬜ 未开始），不写“进行中”；
  2. **新增阶段小节**写齐四项：已完成 / 未开始（含用户裁定） / 阻塞（附证据与解除路径，不能只写“没做”） / 可判定验收条件与仍未覆盖；
  3. **旧数字与阶段编号**一并更正（如“现为 X 条断言”）。
- **判据**：`grep -n '^#\|^## ' docs/DEVELOPMENT-PLAN.md` 的阶段小节应与流程文档里的 Phase 一一对应；对不上就是漏更。
- **为什么算硬规则**：用户会把“更新任务列表”与“收尾”当成同一件事要求——他要的是下次能靠文档接上，而不是靠对话记忆。