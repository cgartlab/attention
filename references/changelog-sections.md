# CHANGELOG 分节与可见性规则

> 用途：决定"某类变更要不要进 CHANGELOG、进哪一节"。行业做法来自 release-please 的 `CHANGELOG_SECTIONS`、git-cliff 默认模板的 `skip: true`、以及 Keep a Changelog 的分类约定（调研详见 `docs/ecosystem-research/release-automation.md`）。
> 本文件是这条规则的**唯一权威**：`core-docs-sync.md` 与 SKILL.md 只做路由。

## 一、分节表（commit type → Keep a Changelog 节）

| commit type | 进哪一节 | 是否出现在 CHANGELOG | 依据 |
|---|---|---|---|
| `feat` | `### Added` | 是 | Keep a Changelog 的 Added 对应用户可见新能力 |
| `fix` | `### Fixed` | 是 | 同上 |
| `perf` | `### Changed` | 是 | 性能变化用户可感，但不算新增能力 |
| `refactor` | `### Changed`（仅当对外行为变化时） | **默认隐藏** | release-please 默认隐藏 refactor；纯内部重构不该出现在用户 CHANGELOG |
| `revert` | `### Removed`（被回退的能力）或 `### Fixed`（被回退的修复） | 是 | 回退是用户可见的行为变化 |
| `docs` | `### Changed`（仅当影响使用者文档时） | **默认隐藏** | 除非文档本身就是交付物（如 SDK 文档站） |
| `chore` / `ci` / `build` / `test` / `style` | — | **隐藏** | 与使用者无关；git-cliff 亦默认跳过发布流水线类 chore |
| 依赖升级（`chore(deps)` / `deps:`） | `### Changed` | 视影响而定 | 影响运行时的依赖升级应出现；纯 devDependency 隐藏 |
| 破坏性变更（`!` 或 `BREAKING CHANGE:` footer） | **按变更性质写入对应节**（删除能力→`Removed`；行为/契约变化→`Changed`；安全相关→`Security`），并加 **`**BREAKING:**`** 前缀 | 是 | Keep a Changelog 无独立 Breaking 分类；Conventional Commits 的 `!` 只标性质，不指定节 |

**六个合法节**（Keep a Changelog 标准分类，不得自创）：`Added` / `Changed` / `Deprecated` / `Removed` / `Fixed` / `Security`。

## 二、`hidden` 与 `skip` 是两件不同的事

| 语义 | 含义 | 本 skill 的落地 |
|---|---|---|
| **hidden**（识别但不出现） | 该类变更**知道**它发生了，但**不写进 CHANGELOG** | 上表"默认隐藏"的类型：仍要在收尾报告的"技术细节"里列出，只是不进 CHANGELOG |
| **skip**（不参与版本 bump） | 该类变更**不影响版本号**，也不进 CHANGELOG | `chore`/`ci`/`build`/`test`/`style`/纯 `docs`；它们不构成 `release_signals` 里"需要 bump"的理由 |

同一个 commit 可以同时是 hidden 与 skip（如 `chore: bump CI image`），也可以是"出现但 skip"（如 `docs:` 影响使用者文档时会出现，但通常不 bump）。

## 三、反编造：条目必须可溯源

每条写进 CHANGELOG 的条目必须满足其一：

1. 直接来自 diff 中新增/修改的**公开接口面**（导出的函数/命令/参数/端点/配置项）；
2. 直接来自 diff 中新增/修改的**用户可见字符串**（README 段落、错误消息、日志）；
3. 直接来自 diff 中的**依赖或配置变化**；
4. 以上皆不满足 → 写 `［待补充：…］` 占位符，**不填充**。

**不采信** commit message / PR 标题 / issue 链接作为 CHANGELOG 内容来源——那些是"作者声明"，不是 diff 事实。它们是 `release_signals` 的输入（用来判断"是否要发版"），不是 CHANGELOG 的文案来源。这是本 skill 与所有"从 commit 生成 CHANGELOG"工具的根本区别。

**区分"内容来源"与"溯源指针"**：内容只能来自 diff（上表四条）；若要留指针，可附 commit 短哈希，但**不得**把 commit message 的措辞当成 CHANGELOG 文案。

条目可选附溯源标记：`—— ref: src/a.js:add()` 或 `—— commit: a1b2c3d`。

## 四、`[Unreleased]` 与 monorepo

- **未发版的变更进 `## [Unreleased]`**（Keep a Changelog 要求）。发版时把它改名为 `## [x.y.z] - YYYY-MM-DD`（日期取**真实**日期），并新建空的 `[Unreleased]`。
- **monorepo：一个包一个 CHANGELOG**（各主流工具一致：release-please、changesets 都是 per-package），放在该包目录下。**不要**做"集中式单一 CHANGELOG + `## [pkg-a]` 子节"——读者要翻长文件才找到自己包的信息。`version_consistency_audit` 的 `monorepo_mode`/`packages` 就是为这条服务的。
