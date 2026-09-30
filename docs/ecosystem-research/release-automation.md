# 版本号 + CHANGELOG 自动化工具调研对照

> 目的：为立正Skill（attention）的 `version_consistency_audit` 与"涉及 release"判定提供可参照的边界清单和坑位备忘。
> 依据全部来自工具官方 README / 源码 / 文档（附 URL），未执行任何命令/安装脚本。

---

## 0. 全局速览

| 工具 | 触发时机 | 判定方式 | 是否自动推 tag/开 Release | 配置面 | 面向 |
|---|---|---|---|---|---|
| **semantic-release** | CI 每次推分支 | commit 前缀 → release type | 是，且自动 publish | 巨（插件 + 分支 + shareable config） | 全自动 CI 发版 |
| **release-it** | 人手动 `npm run release` | 交互 prompt 选 version | 视配置（默认开） | 中（`.release-it.json` + hooks + 插件） | 人肉 + 自动结合 |
| **fabiospampinato/bump** | 人手动 `bump` | 命令参数指定 `minor/patch/major` 或 `v1.2.3` | 默认 tag+commit，Release 需手动 | 小（`bump.json`，仅 Node 项目） | 单人 Node 项目 |
| **release-please** | GitHub Action 监听推送 | commit 前缀 → semver；`Release-As: x.x.x` 覆盖 | 是，先开"Release PR"再自动 tag+GitHub Release | 中（`release-please-config.json` + `.release-please-manifest.json`） | Monorepo / Google Cloud 生态 |
| **changesets** | PR 作者手写 changeset 文件 | 手写 `.changeset/*.md` 里的 semver 类型 | 否，`version`/`publish` 由 CI 触发 | 中（`.changeset/config.json` + 模板） | Monorepo（尤其 npm） |
| **git-cliff** | 任意 CI / 本地 | `[bump]` 段 regex 规则 | 否（只写 CHANGELOG） | 大（`cliff.toml`，模板+解析器+分组） | CHANGELOG 生成器 |
| **conventional-changelog** | 任意脚本 | `conventional-recommended-bump` 用 commit | 否（只输出建议） | 中（preset + writer 模板） | CHANGELOG 生成器 |

**贯穿性发现**：所有工具的默认"涉及 release"判定都**只信任 commit message**。它们从不检查 diff 是否真的改了某个 API、也从不检查 CHANGELOG 是否已更新。这一点与立正"只反映真实 diff"的原则是正交的：前者相信人写的 commit 前缀，后者相信机器读的 diff。立正的三条触发条件（触及版本文件 / `chore(release)` 或 `feat!` / 用户明示）本质上是"commit 前缀派生的启发式"，与 release-please 的 "releasable unit" 概念一致，但覆盖面更窄（见 §4）。

---

## 1. 逐个工具卡片

### 1.1 semantic-release

- **核心机制**：CI 每次 push 到发布分支就跑一次。流水线 9 步（Verify Conditions → Get last release → Analyze commits → Verify release → Generate notes → Create Git tag → Prepare → Publish → Notify）——README "Release steps" 表。
- **bump 判定**：委托给 `@semantic-release/commit-analyzer`，用 conventional-changelog-angular preset 解析 commit。默认规则（`commit-analyzer/lib/default-release-rules.js`）：
  - `breaking: true` → `major`
  - `revert: true` → `patch`
  - `type: feat` → `minor`
  - `type: fix` / `perf` → `patch`
  - 附带 Angular/Atom/Ember/ESLint/Express/JSHint 6 种历史格式的 emoji/tag 兼容规则（见源码 §9–33 行）
  - 完整 release type 枚举：`major | premajor | minor | preminor | patch | prepatch | prerelease`（`default-release-types.js`）
- **多包/monorepo**：通过"分支即发布渠道"实现——不同 `branches` 配置对应不同发布渠道，配 `channels` 到 npm dist-tag。真正的 monorepo 支持靠 shareable config + `npm.workspaces` 或多份 semantic-release 实例；官方并未内建 monorepo manifest（与 release-please 对比明显）。
- **CHANGELOG 分组**：由 `@semantic-release/release-notes-generator` 生成，按 commit type 分组，section 名称可覆盖。默认 section 顺序 `Features / Bug Fixes / Performance Improvements / Reverts / Dependencies / Miscellaneous Chores`（后者隐藏）。条目用 markdown 无序列表 + commit hash 缩写 + scope（`*(`scope`)*`）。
- **自动生成**：**是**。默认 `npmPublish: true`，`gitDescribeTags: 'v*'`，`tagFormat: 'v${version}'`。回滚：默认无，一旦 npm publish 就不可撤销。
- **配置复杂度**：**高**。`@semantic-release/commit-analyzer` `@semantic-release/release-notes-generator` `@semantic-release/npm` `@semantic-release/github` `@semantic-release/changelog` `@semantic-release/exec` `@semantic-release/git` 七类插件，配 `branch` / `channels` / `preset` / `releaseRules` / `parserOpts` / `provider` 十余个字段。README 明确："Simple and reusable configuration via shareable configurations"——暗示默认并不简单。
- **失败回滚**：无内建。npm 已经 publish 就无法删除（可 deprecate）。**这是它的最大坑**——CI 触发 + 全自动化意味着一次错误判定会留下不可回退的公开版本。

### 1.2 release-it

- **核心机制**：**交互式 CLI**，人肉确认每步。`init → bump → release` 三阶段，每阶段可插 hooks（`before:init` / `after:bump` / `before:git:release` 等）。
- **bump 判定**：默认不解析 commit，让人选 `--release-version`。要自动推荐必须装 `@release-it/conventional-changelog` 插件（复用 conventional-changelog 的 recommended-bump）。
- **版本定位优先级**（README "Latest version" 段）：
  1. `package.json.version`
  2. 最新 Git tag（解析）
  3. `0.0.0`（兜底）
- **多包/monorepo**：核心只支持 npm workspaces 的最小场景；真正的多包支持靠 `@release-it-plugins/workspaces` 或外接 changesets 插件。
- **CHANGELOG**：默认用 `git log` 生成临时 changelog（展示给人选 version 时用），要落到 `CHANGELOG.md` 需装插件（`@release-it/conventional-changelog` / `@release-it/keep-a-changelog` / `@unjs/changelogen` / git-cliff 插件）。**默认不写文件**，这一点比 semantic-release 克制得多。
- **自动生成**：Git commit+tag+push 默认开；GitHub/GitLab Release 需显式 `github.release: true` / `gitlab.release: true`。
- **配置复杂度**：中。`.release-it.json` 顶层字段（`git` / `github` / `gitlab` / `npm` / `hooks` / `version` / `plugins`）。`--no-increment` 标志支持"更新已存在的 tag"，用于补救"tag 推送失败但 npm 已发"的场景。
- **失败回滚**：**部分手动**。README "Update or re-run existing releases" 明确列出：`--no-increment --no-npm` 用于"npm 成功但 tag 推送失败"的重试。**这是它的特色**——把"失败重试"当作一等公民建模。

### 1.3 fabiospampinato/bump

- **核心机制**：五个命令 `version / changelog / commit / tag / release`，可组合可拆开。"Opinionated but configurable" 的具体含义是**默认所有字符串都可模板化**（`[version]` `[message]` `[hash7]` `[author_name]` 等 token）。
- **bump 判定**：**不解析 commit 前缀**。`bump --minor` / `--patch` / `--major` 由人指定，或 `--version v1.2.3` 手动指定。这是"反自动化"的极致。
- **版本定位**：**只支持 `package.json`**（README 明说"requires a top-level package.json"）。没有 pyproject/Cargo/go.mod 支持。
- **CHANGELOG**：模板是纯 commit message 列表（`- [message]`），**不分组**。默认 `review: true` 让作者在 commit 前打开 CHANGELOG 手动审阅——**默认强制人工审阅**是它对"反幻觉"的独特立场。
- **自动生成**：`version` `changelog` `commit` `tag` 默认全开；`release` **默认关**（README "Enabled commands" 明确说"release is disabled by default, I recommend you to check if everything is correct"）。
- **配置复杂度**：**小**。`bump.json` 一段 JSON，11 个顶层键。没有 preset 系统，没有插件。
- **失败回滚**：无。

### 1.4 release-please（重点）

- **核心机制**：**GitHub Action 驱动，走"Release PR"模式**。默认分支上出现"releasable unit"后，它**不直接发版**，而是开一个 PR 列出 CHANGELOG 修改 + 版本文件修改 + tag 计划；人 merge 后才打 tag 和建 GitHub Release。这本质是把"发版"从自动动作变成"人确认的 PR"。
- **bump 判定**：Conventional Commit 前缀：
  - `fix:` → patch
  - `feat:` → minor
  - `feat!:` / `fix!:` / 任意 `!` 或 `BREAKING CHANGE:` → major
  - **releasable unit**（README FAQ 段）= commit 前缀是 `feat|fix|deps` 之一。**`chore` 和 `build` 不算**——这是关键：一次 PR 里如果只有 `chore:` commit，release-please 就**不建 PR**。
  - 语言特定：Java/Python 里 `docs` 也算（因为 `docs` 触发文档版本发布）。
- **版本覆盖**：`Release-As: x.x.x` 写在 **commit body**（非标题）里，即使用空 commit：`git commit --allow-empty -m "chore: release 2.0.0" -m "Release-As: 2.0.0"`。manifest 配置里也可以 `release-as: "1.2.3"` 全局覆盖。
- **多包/monorepo**：**这是它的核心场景**。两种模式：
  - **单策略**（CLI）：一个仓库 = 一个包。
  - **Manifest 模式**：`release-please-config.json` 定义 `packages: { "path/to/pkg": {release-type, package-name, changelog-path, exclude-paths, ...} }`，`.release-please-manifest.json` 记录每个 path 当前已发版本。一次运行会为**所有变更的包**开一个**聚合 PR**。
  - **依赖图插件**：`node-workspace` `cargo-workspace` `maven-workspace` 三种——构建包间依赖图，若 A 的 major 破坏 B 的 semver 范围，**自动给 B 打 patch bump** 并联动更新 B 的 CHANGELOG。这是 changesets 的核心能力之一。
  - **linked-versions** 插件：把多个 component 锁到同一版本（用于 monorepo 里"必须同版发布"的组件，比如 SDK 主库与子模块）。
- **CHANGELOG 分组**：每种语言策略在 `CHANGELOG_SECTIONS` 数组里定义，例如 Node 默认：`Features / Bug Fixes / Performance Improvements / Dependencies / Reverts / Documentation`（style/chore/refactor/test/build/ci 默认 `hidden: true`——即仍会解析但不出现在 CHANGELOG 里，见 `python.ts` §31–44）。**`hidden: true` 是"识别但隐藏"的三级开关**，比 release-it 的"要装插件才写"更细。
- **自动生成**：合 PR 后自动打 tag、建 GitHub Release。`draft: true` 可让 Release 保持草稿态。`skip-github-release: true` 只 tag 不建 Release。
- **配置复杂度**：**中-高**，但**分层清晰**：顶层默认 + per-package 覆盖 + plugins 数组。核心文件只有两个（config + manifest），schema 有 JSON schema 校验。
- **失败回滚**：Release PR 未 merge 前，随时可关掉 PR；已 merge 则 tag 已产生，需手动 `git push --delete` 撤销。`last-release-sha` 配置项允许在"错误地合并了错误 PR"后手动指定"从哪次提交重新收集 commit"。

### 1.5 changesets

- **核心机制**：**作者驱动，不依赖 commit message**。开发者在 PR 里手写 `.changeset/*.md`（frontmatter 指定包名 + semver 类型 `major|minor|patch`，正文是要写进 CHANGELOG 的用户可见变化）。
- **bump 判定**：**完全靠人手写 semver 类型**。`changeset version` 消费所有 changeset 文件，把同包多个 changeset 折叠为"最高 semver 类型"（`decisions.md` "How changesets are combined"）。
- **多包/monorepo**：**这是它的定位**。`.changeset/config.json` 里配 `fixed` 和 `linked` 数组，`fixed` 强制多包同版本（如 typescript 类型生态），`linked` 是"版本联动但不同值"。构建 package 依赖图，**下游依赖包被打 patch bump**（`decisions.md` "How dependencies are bumped"：依赖变更"all updating of dependencies is done as a patch bump"）。
- **CHANGELOG**：模板化 `.changeset/config.json` `changelog` 字段，可指定 changelog 生成器模块（默认 `@changesets/cli/changelog`）。每个包一个 CHANGELOG.md，条目格式：`## x.y.z\n### Minor Changes\n- <changeset 正文>`。
- **自动生成**：**否**。`changeset version` 更新版本 + CHANGELOG，`changeset publish` 才发布。CI 里通常配 GitHub Action `changesets/action`，它开一个"Version Packages" PR。
- **配置复杂度**：**小**。`config.json` 十几个字段（`fixed`/`linked`/`changelog`/`ignore`/`access`/`baseBranch`/`commit`/`tag`/`version`/`updateInternalDependencies`）。
- **失败回滚**：因为**决策权在人的手写文本里**，回滚 = revert 那个 changeset 文件的 PR。天然可回退。
- **反幻觉机制**：**它是本调研中最"克制"的工具**——`decisions.md` 明确说："We use semver for specifying the change... we do not specify any change types beyond `major`, `minor`, or `patch`." **changeset 正文必须由人写**，工具不会从 commit 里推导"用户影响"。这直接印证了立正的哲学。

### 1.6 git-cliff（重点）

- **核心机制**：Rust 单二进制，读 `git log`，按 `cliff.toml` 生成 CHANGELOG，不 bump 版本、不打 tag、不发布。可选 `[bump]` 段只做"版本号推荐"（`git-cliff --bumped-version`）。
- **bump 判定**：`[bump]` 段：
  - `features_always_bump_minor`（默认 true）：`feat` 触发 minor（若 false，`0.x` 时降为 patch）
  - `breaking_always_bump_major`（默认 true）：`BREAKING CHANGE` 触发 major（若 false，`0.x` 时降为 minor）
  - `custom_major_increment_regex` / `custom_minor_increment_regex`：自定义前缀正则触发 major/minor
  - `no_increment_regex`：默认 `chore|ci|docs` 之类不参与 bump
  - `bump_type`：强制 major/minor/patch（等价 `--bump-type`）
- **CHANGELOG 分组**：`[changelog]` 段 + Tera 模板。**默认模板把 commit 按 prefix 分组为带 emoji 的 section**：`🚀 Features / 🐛 Bug Fixes / 📚 Documentation / ⚡ Performance / 🚜 Refactor / 🎨 Styling / 🧪 Testing / ⚙️ Miscellaneous Tasks / 🛡️ Security / ▶️ Revert / 💼 Other`（config/cliff.toml）。**`chore(release): prepare for` 和 `chore(deps.*)` 和 `chore(pr)` 默认 `skip: true`**——避免把发布流水线的自动化 commit 混进 CHANGELOG，这是个非常关键的克制点。
- **`unreleased` 段**：模板里 `{% if version %}## [{{version}}] - date{% else %}## [unreleased]{% endif %}`——有 tag 就用 tag，否则归入 Unreleased。**它天然支持 Keep a Changelog 的 Unreleased 段**。
- **配置复杂度**：**大**。`cliff.toml` 三大战区：`[changelog]`（模板+后处理+output+trim）、`[git]`（conventional_commits/filter/parse/sort/topo）、`[remote]`（GitHub/GitLab/SVN 集成）、`[bump]`（版本推荐）。支持环境变量覆盖 `GIT_CLIFF__SECTION__FIELD`。
- **反幻觉**：`filter_unconventional = true`（默认）会**排除不符合 conventional commits 规范的 commit**——这实际上承认了"很多 commit 无法可靠映射到用户影响"。

### 1.7 conventional-changelog

- **核心机制**：一个"包族"，不是单一 CLI。核心包 `conventional-changelog`（CLI）、`conventional-changelog-angular`（preset）、`conventional-recommended-bump`（只输出建议的 bump 类型）、`conventional-commits-parser` / `-filter` / `-writer`（解析管线）。
- **bump 判定**：`conventional-recommended-bump` 用 commit 前缀映射到 patch/minor/major（同 commit-analyzer 的规则，因为共享 preset）。
- **CHANGELOG 分组**：由 writer 模板定义，默认按 conventional commits 规范分组。**这是行业标准的"参考实现"**——绝大多数工具的 changelog 分组都参考它。
- **自动生成**：只生成 CHANGELOG，不做任何发布动作。
- **配置复杂度**：中。preset（决定解析规则）+ writer template（决定输出）。
- **反幻觉**：**它承认 commit message 的脆弱性**。conventional-changelog 生态配套了 commitlint 和 commitizen，本质是**要求作者在提交前写合规 commit**，否则后续 pipeline 无从谈起。

---

## 2. 版本承载文件清单对照

**这是 `version_consistency_audit` 的边界**。来源为 release-please 各策略源码（`src/strategies/*.ts`）、release-it 插件、以及各生态官方约定。

| 语言/生态 | 版本文件（路径） | 版本字段位置 | 是否必备 | 备注 |
|---|---|---|---|---|
| **Node.js / npm** | `package.json` | 顶层 `version` | ✅ | 单包必备 |
| | `package-lock.json` | 根 `version` + `packages[""].version` | ⚠️ | release-please 也管 `npm-shrinkwrap.json` |
| | `pnpm-lock.yaml` / `yarn.lock` | `importers[""].specifiers` | ⚠️ | 通常由包管理器自管，不 hand-edit |
| **Python** | `pyproject.toml` | `[project].version`（PEP 621）或 `[tool.poetry].version` | ✅ 二选一 | |
| | `setup.py` | `version=` 参数 | ⚠️ | 老式；poetry/setuptools-scm 项目常省略 |
| | `setup.cfg` | `[metadata] version` | ⚠️ | |
| | `<pkg>/__init__.py` | `__version__ = "..."` | ⚠️ | release-please 会尝试 `pkg/__init__.py` 和 `src/pkg/__init__.py` 两条路径 |
| | `version.py` | `version = "..."` / `__version__` | ⚠️ | 老式；release-please 用 `findFilesByFilenameAndRef` 全局搜 |
| | `src/<pkg>/__init__.py` | 同 `__init__.py` | ⚠️ | src-layout 变体 |
| **Rust** | `Cargo.toml`（workspace 根 + 每个 crate） | `[package].version` | ✅ | workspace 项目所有 member 一起 bump |
| | `Cargo.lock` | `[[package]] version` | ⚠️ | release-please 用 `CargoLock` updater |
| **Go** | `VERSION` 或 `version.go` | 任意文本/`const Version =` | ⚠️ | go.mod **不含**版本号；release-please 的 `go` 策略用 `versionFile` 参数 |
| | `go.mod` | 无 version 字段 | ❌ | 只用 `module path` 标识，tag 是唯一版本源 |
| **Java (Maven)** | `pom.xml`（所有） | `<version>`（顶层或 `<parent><version>`） | ✅ | release-please 会 `findFilesByFilenameAndRef` 扫所有 pom.xml |
| | `pom.xml`（子模块） | `<parent><version>` | ⚠️ | 父 POM 变了子模块要跟着变 |
| **Java (Gradle)** | `build.gradle` / `build.gradle.kts` | `version = 'x.y.z'` / `version = "x.y.z"` | ⚠️ | release-please 没 gradle 策略，用 Generic 或自定义 |
| | `gradle.properties` | `version=x.y.z` | ⚠️ | 常见单点管理方式 |
| **PHP** | `composer.json` | `version` 或 `"name": "pkg/x"` + `autoload`（release-please 用 `RootComposerUpdatePackages` 改 version） | ✅ | |
| | `VERSION` | 纯文本版本号 | ⚠️ | release-please 的 PHP 策略同时更新 |
| **Ruby** | `lib/<pkg>/version.rb` | `VERSION = "x.y.z"` | ✅ | release-please 默认路径：`lib/${component.replace('-', '/')}/version.rb` |
| | `Gemfile.lock` | `GEM specs: <pkg> x.y.z` | ⚠️ | release-please 用 `GemfileLock` updater |
| **Dart / Flutter** | `pubspec.yaml` | 顶层 `version:` | ✅ | |
| **Elixir** | `mix.exs` | `def project(...) do ... version: "x.y.z"` | ✅ | |
| **Terraform** | `README.md` | 文本内嵌 `x.y.z` | ⚠️ | release-please 用 Generic updater 正则替换 |
| **Bazel** | `MODULE.bazel` | `module(name=..., version=...)` | ✅ | release-please 的 bazel 策略 |
| **OCaml** | `*.opam` / `*.esylock.json` | `version: "x.y.z"` | ✅ | |
| **R** | `DESCRIPTION` | `Version: x.y.z` | ✅ | NEWS.md 而非 CHANGELOG.md |
| **Swift** | `Package.swift` | `.package(name:version:)` 或 `// swift-tools-version:` | ⚠️ | 无 release-please 策略，需 Generic |
| | `Info.plist` (Xcode) | `<key>CFBundleShortVersionString</key><string>x.y.z</string>` | ✅ iOS | 通常与 podspec 联动 |
| | `*.podspec` | `spec.version = "x.y.z"` | ✅ CocoaPods | |
| **Kotlin/Android** | `build.gradle(.kts)` | `version = "x.y.z"` | ⚠️ | 与 Java 混用 |
| **Salesforce (SFDX)** | `sfdx-project.json` | `namespace` / `packageDirectories[].versionName` | ⚠️ | release-please 有专门策略 |
| **.NET / C#** | `*.csproj` | `<Version>x.y.z</Version>` 或 `<PackageVersion>` | ✅ | 见 `@jcamp-code/release-it-dotnet` 插件 |
| | `Directory.Build.props` | `<Version>` 集中管理 | ⚠️ | 常见于多项目解决方案 |
| | `global.json` | `sdk.version` / `dotnet.sdk.version` | ❌ | 不是"产品版本" |
| **Docker / K8s** | `Chart.yaml` (Helm) | 顶层 `version:` | ✅ | release-please 有 helm 策略 |
| **通用（跨语言兜底）** | `VERSION` 或 `version.txt` | 纯文本版本号 | ⚠️ | release-please 的 `simple` 策略 |

**观察**：
1. **没有工具能"自动"覆盖所有语言**。release-please 的 18 种策略是最广的，但仍然漏了 Swift/Android/.NET/Gradle（Gradle 通过 Generic 可以打，但要 `extra-files` 手工列出）。
2. **lockfile 是双刃剑**：release-please 处理 `package-lock.json` / `npm-shrinkwrap.json` / `Cargo.lock` / `Gemfile.lock`，因为这些文件的版本号**不是**由包管理器自己算的（它们只是缓存声明）。所以一致性审计**必须**包含 lockfile 的版本字段。
3. **"版本文件"定义要宽**：包括 README 里的版本号、Terraform 模块 README、`x-release-please-version` 注释标记的文件。立正若只扫"已知版本文件"，会漏掉这些"注释锚点"。

---

## 3. CHANGELOG 规范对照

### 3.1 Keep a Changelog vs Conventional Commits

| 维度 | Keep a Changelog | Conventional Commits |
|---|---|---|
| 关注点 | **人读的 CHANGELOG 格式** | **机器读的 commit 格式** |
| 分类 | `Added / Changed / Deprecated / Removed / Fixed / Security`（用户视角） | `feat / fix / docs / style / refactor / perf / test / build / ci / chore / revert`（作者视角） |
| 版本号 | 独立 section（`## [1.0.0] - 2024-01-01`）+ `[Unreleased]` | 版本号来自 semver 计算，非 commit 自身 |
| `[Unreleased]` | **要求**存在，是待发布变更的暂存区 | 无关 |
| Breaking change | 显式 `### BREAKING CHANGES:` 段 | `!` 后缀或 `BREAKING CHANGE:` footer |

**冲突点**：
1. **分类不同源**：`feat:` 对应 Keep a Changelog 的 `Added` 大部分时候成立，但 `feat(perf):` 是 `Performance`，`refactor:` 是 `Changed` 还是"隐藏"？不同工具有不同默认。git-cliff 默认给 refactor 单独一栏；release-please 默认隐藏 refactor；semantic-release 不显示 refactor。
2. **`chore:` 是否该出现**：git-cliff 有单独 `Miscellaneous Tasks` 段；release-please 默认隐藏；changeset 只关心"用户可见变化"，作者直接跳过 chore。
3. **`docs:` 处理**：release-please 的 Python/Java 策略把 `docs` 提升为 releasable unit（因为文档版本也发），Node 策略则把它归到 `Documentation` section。
4. **`[Unreleased]` 段**：Keep a Changelog 强要求。release-please 不用这个（因为它的 CHANGELOG 是"合 PR 后一次性更新"，中间态是 PR body 而非 CHANGELOG.md）。changesets 也不用（因为它是"消费 changeset 文件时一次性写"）。**只有 git-cliff 天然支持**：模板里 `{% if version %}## [tag] - date{% else %}## [unreleased]{% endif %}`——立正若在提交前跑一次 changelog 生成，git-cliff 是最合适的参考。

### 3.2 Unreleased 段处理模式

| 工具 | Unreleased 段 | 处理方式 |
|---|---|---|
| git-cliff | ✅ 模板显式区分 | 有 tag → 归入 tag；无 tag → 归入 unreleased |
| conventional-changelog | ⚠️ 可选 | preset 提供但未强制 |
| semantic-release | ❌ | 无中间态，直接生成新版本段 |
| release-please | ❌ | PR body 是中间态，CHANGELOG 只有 tag 后的段 |
| changesets | ❌ | 中间态是 `.changeset/*.md` 文件，不是 CHANGELOG 段 |
| release-it | ⚠️ 依赖插件 | 用 `@release-it/keep-a-changelog` 可支持 |
| bump | ❌ | CHANGELOG 只列 commit，无版本段 |

**立正的启示**：立正的 CHANGELOG 有 `[Unreleased]` 段且要求人维护，这与 git-cliff 的模型最接近。立正不需要生成"tag 版"，只需保证 `[Unreleased]` 段反映当前 diff——这正是 git-cliff 模板 `body` 变量在无 version 时的行为。

### 3.3 Monorepo 分节

| 工具 | 分节策略 |
|---|---|
| release-please | 每个 package 一个 CHANGELOG.md（`path/to/pkg/CHANGELOG.md`），聚合 PR 里所有包各出一段 |
| changesets | 每个 package 一个 CHANGELOG.md；`changelog` 配置可定制模板 |
| git-cliff | 不支持 monorepo，只出单一 CHANGELOG |
| conventional-changelog | 不支持 monorepo |
| release-please manifest 模式 | 支持 `changelog-path` 覆盖（如 Python 项目常放 `docs/CHANGES.rst`） |

**观察**：所有 monorepo 工具都坚持"一个包一个 CHANGELOG"。集中式单一 CHANGELOG（含 `## [pkg-a]` `## [pkg-b]` 子节）反而少见——因为它让"某个包的读者"必须翻长文件。立正若遇到 monorepo，应默认走"一个包一个 CHANGELOG"，不要试图做集中式。

---

## 4. "涉及 release" 判定对照

**立正的三条规则**：
1. 变更集触及版本文件
2. 含 `chore(release)` 或 `feat!` commit
3. 用户明示 release

**各工具的实际判定**（从宽到严）：

| 工具 | 判定规则 | 与立正的差异 |
|---|---|---|
| **semantic-release** | CI 每次 push 都跑；若 `Analyze commits` 得到任一 release type（patch+）就发 | 比立正**宽松得多**——任何 `fix:` 都触发；但只信任 commit 前缀，不查版本文件 |
| **release-it** | 人触发时才跑 | 等价立正规则 3（用户明示） |
| **bump** | 人触发时才跑 | 同 release-it |
| **release-please** | commit 前缀是 `feat\|fix\|deps` 之一 → releasable unit；`chore`/`build`/`docs` 不算（Java/Python 例外） | 比立正**更严**——`feat:` 也算；但**不看版本文件**、**不看用户明示**（有 `Release-As` 覆盖但需 commit body） |
| **changesets** | 存在未消费的 `.changeset/*.md` 文件 | 完全基于"作者主动声明"，**不看 commit 前缀** |
| **git-cliff** | 有 commit 且 `no_increment_regex` 不匹配 | 比立正宽——只要 `feat`/`fix`/`perf`/`refactor` 都算，除非显式配置排除 |
| **conventional-changelog** | 输出"建议"版本 bump，由人决定是否发 | 判定与发版解耦 |

### 4.1 立正的漏判风险

**规则 1（触及版本文件）漏判**：
- 触及**只有 lockfile** 的变更（例如 `package-lock.json` 单独变了）——若 audit 只扫 `package.json`，漏判。
- 触及 `pyproject.toml` 的 `[tool.poetry]` 段的**非 version 字段**（如 `[tool.poetry.dependencies]` 变了）——**不该触发 release**，但若 audit 用"文件路径"判定会误触发。
- 触及**注释锚点**版本（release-please 的 `x-release-please-version` 标记、Gradle 的 `gradle.properties`）——若 audit 不识别这些，漏判。
- 触及 `README.md` 里的版本号（Terraform 模块常用）——极少见但存在。

**规则 2（commit 前缀）漏判**：
- `fix: ...` commit（bug fix 通常需要发版）——立正**不识别**。这是一个明显的漏洞。release-please、semantic-release、git-cliff 全部把 `fix:` 当作 patch bump 的触发。
- `feat(scope):` 的**小写 fix 变体**（如 `fixes:` `bugfix:` `bug-fix:`）——立正只认精确 `feat!`。
- **BREAKING CHANGE footer**（不带 `!`）：Conventional Commits 规范允许 `fix: foo\n\nBREAKING CHANGE: bar`。立正不检查 footer。
- `deps:` 前缀——release-please 特别把 `deps:` 视为 releasable（依赖升级影响运行时），立正不识别。
- `chore(deps): bump dep from x to y`（Dependabot 生成）——release-please 排除，但语义上依赖变更可能触发 semver patch。立正规则 2 只认 `chore(release)`，会漏掉这类。

**规则 3（用户明示）**：完全靠人，无法自动化，但**是最后的兜底**——release-please 的 `Release-As: x.x.x` 覆盖机制、semantic-release 的 `npm version` 强制、release-it 的 `--release-version` 都是等价物。立正缺一个"用户明示版本号"的通道——目前只能靠用户明说"我要发 1.2.3"。

### 4.2 立正的误判风险

- **规则 1 误判**：触及 `package.json` 的**非版本字段**（如新增 dependency、修改 scripts）——按规则 1 会误触发 release。这非常常见，Dependabot PR 里全是这种。**release-please 没有这个坑**，因为它只看 commit 前缀。
- **规则 2 误判**：`feat!: internal refactor`——技术上 breaking 但用户看不到，仍触发 release。这是 conventional commits 的通病，无解，需要作者自律。
- **规则 2 误判**：`chore(release): something` 但**并没有真的 bump**（例如只是重构 release 脚本）——立正会误触发。

### 4.3 建议增强的判定

立正应该**保留自己的"以 diff 为准"哲学**，但把触发条件**从"或"改成"多层门"**：

- **主判据（触发 audit）**：任何一版规则触发即运行 `version_consistency_audit`（保留宽松入口）。
- **副判据（决定 audit 结论）**：audit 内部再判断"是否真的需要 bump"：
  - 若只改 `package.json.dependencies` 且版本号未变 → **不需要 release**，跳过版本 bump。
  - 若 commit 前缀是 `fix:` 或含 BREAKING CHANGE → **需要 release**（补进规则 2）。
  - 若只改 CHANGELOG.md / README.md 里的版本号引用 → **可能是"事后同步"**，audit 应检查版本文件是否已 bump。

---

## 5. 可直接吸收的做法清单

按"改动小 → 改动大"排列，每条写清 做什么 / 怎么做 / 理由 / 放哪个环节。

### 5.1 立正应该立即抄的（低成本高收益）

**做法 1：`fix:` 也算"涉及 release"信号**
- 做什么：规则 2 扩展为 `chore(release)|feat!|fix:.*|BREAKING CHANGE:`。
- 怎么做：在 SKILL.md 的"涉及 release 判定"段追加；`scripts/version_consistency_audit.sh/.ps1` 里对应正则同步。
- 理由：release-please 把 `fix:` 列为 releasable unit 的第一位，semantic-release / git-cliff / conventional-changelog 也都认。**当前立正只认 `feat!` 是明显漏判**——90% 的 patch 版本发布都是 `fix:` 触发。
- 放哪个环节：SKILL.md §"涉及 release" 判定，以及 `version_consistency_audit` 脚本的 commit 前缀扫描正则。

**做法 2：BREAKING CHANGE footer 扫描**
- 做什么：除扫 commit 标题外，扫 commit body 前 20 行，找 `BREAKING CHANGE:` 或 `BREAKING-CHANGE:` footer（Conventional Commits v1.0.0 规范）。
- 怎么做：`git log --format='%B' --max-count=100` 后 grep footer。
- 理由：很多仓库用 `fix:` + footer 表达 breaking（比 `fix!:` 更可读）。
- 放哪个环节：`version_consistency_audit` 脚本。

**做法 3：`[Unreleased]` 段格式与 git-cliff 模板对齐**
- 做什么：明确 CHANGELOG 的 `[Unreleased]` 段格式（section 名列表 + 条目格式），对齐 Keep a Changelog。
- 怎么做：在 `core_docs_relevance_scan` 的文档同步逻辑里，加入"若检测到 diff 涉及功能变更，追加 `### Added/Changed/Fixed/Security` 条目到 `## [Unreleased]`"的模板。
- 理由：git-cliff 默认模板是业界最保守的模板，section 名对齐 Keep a Changelog 的官方分类，emoji 分组是可选装饰。立正目前只有"标［待补充：…］"，没有明确的 section 模板。
- 放哪个环节：`core_docs_relevance_scan` 的 CHANGELOG 更新模板。

**做法 4：lockfile 版本字段扫描**
- 做什么：`version_consistency_audit` 除扫 `package.json.version` 外，扫 `package-lock.json` 根 `version` + `packages[""].version`、`Cargo.lock` `[[package]].version`、`Gemfile.lock` 的 `specs` 段、`pnpm-lock.yaml` 的 `importers[""].specifiers`。
- 怎么做：脚本里加 `--lockfile` 子命令，按文件类型分支解析。
- 理由：release-please 的策略代码显示它同时更新主 manifest 和 lockfile，因为它们是"版本一致性的双源"。立正目前可能只查主 manifest，导致"package.json 已 bump 但 lockfile 未同步"的漏网。
- 放哪个环节：`version_consistency_audit` 脚本。

**做法 5：多语言版本文件清单内置**
- 做什么：把 §2 的表格固化成 `references/version-file-inventory.md`，`version_consistency_audit` 按"检测到哪些生态"选择扫描子集。
- 怎么做：新加参考文档 + 脚本里加 `--detect-ecosystem` 逻辑（按目录/文件存在性判定：`package.json` → Node，`pyproject.toml`/`setup.py` → Python，`Cargo.toml` → Rust，`go.mod` → Go，`pom.xml` → Maven，`composer.json` → PHP，`Gemfile` → Ruby，`pubspec.yaml` → Dart，`mix.exs` → Elixir，`*.csproj` → .NET，`Package.swift` → Swift，`*.podspec` → CocoaPods，`Chart.yaml` → Helm，`MODULE.bazel` → Bazel，`DESCRIPTION` → R）。
- 理由：立正定位"任意 Git 项目"，但版本一致性扫描不能假设 Node。release-please 用"策略"抽象做这个，立正应用"生态检测"抽象做。
- 放哪个环节：新参考文档 + `version_consistency_audit` 脚本前置检测。

### 5.2 值得学习的中等成本改进

**做法 6：`[待补充：…]` 与 git-cliff 的 `skip: true` 语义对齐**
- 做什么：明确"［待补充：X］"是"这个位置我识别到需要内容但无法从 diff 可靠推导"，等价于 git-cliff 的 `skip: true`（识别但不填充）。
- 怎么做：文档里写清：`[待补充：X]` 是**占位符**，不是"我要填但填不出"的失败标记；用户看到时应自行补充，不应删除。
- 理由：git-cliff 的 `skip: true` 是"明确放弃"的语义；release-please 的 `hidden: true` 是"识别但隐藏"的语义。立正的 `[待补充：X]` 应该是第三种：**"识别且暴露"——让作者看到缺口**。这个语义要在文档里讲清楚，否则用户可能删掉占位符而不补内容。
- 放哪个环节：SKILL.md "不编造" 段 + `core_docs_relevance_scan` 输出契约。

**做法 7：CHANGELOG 分组三级开关**
- 做什么：仿 release-please 的 `CHANGELOG_SECTIONS`（`type` + `section` + `hidden: true/false`），在立正的 CHANGELOG 更新逻辑里支持"该类型是否出现在 CHANGELOG"三级配置。
- 怎么做：在 `references/scan-recipes.md` 里定义 CHANGELOG section 表；`core_docs_relevance_scan` 读表决定输出哪些 section。
- 理由：立正目前可能把"所有 diff 都写进 CHANGELOG"，这对 `chore:` / `ci:` / `docs:` / `refactor:` 是过度。release-please 默认隐藏 chore/refactor/test/build/ci，是有理有据的行业共识。
- 放哪个环节：`core_docs_relevance_scan` 的 CHANGELOG 生成模板。

**做法 8：`Release-As` 显式覆盖通道**
- 做什么：允许用户通过"下一次提交信息"或"环境变量"显式指定目标版本号，覆盖自动计算。
- 怎么做：SKILL.md 加"若用户明示 `version: X.Y.Z` 或 `target-version: X.Y.Z`，audit 直接采纳，跳过 semver 推导"。
- 理由：release-please 的 `Release-As: x.x.x` 在 commit body 里做覆盖，是"人肉覆盖自动化"的标准做法。立正目前只能靠"用户明示 release"这种模糊表达，缺一个明确的版本号通道。
- 放哪个环节：SKILL.md + `version_consistency_audit` 脚本的 `--target-version` 参数。

**做法 9：`last-release-sha` 类比——从哪次提交开始收集**
- 做什么：`version_consistency_audit` 的 commit 扫描范围应该明确"从上一个 tag / 上次成功 release / 手动指定 SHA"。
- 怎么做：脚本参数化 `--since-tag <tag>` 或 `--since-sha <sha>`；默认行为：`git describe --tags --abbrev=0`。
- 理由：release-please 的 `bootstrap-sha` / `last-release-sha` 解决"我 merge 了错误的 release PR，怎么重新开始"。立正不需要"错误 PR 恢复"，但需要"从上次 release tag 开始"的语义，避免把历史 commit 都算进当前 release。
- 放哪个环节：`version_consistency_audit` 脚本的 commit 收集逻辑。

### 5.3 可选的进阶改进

**做法 10：monorepo 检测与分节**
- 做什么：`core_docs_relevance_scan` 检测到多 package.json / 多 pyproject.toml / pnpm-workspace.yaml / lerna.json / nx.json / Cargo workspace 时，切到"monorepo 模式"：为每个包生成独立的 CHANGELOG 更新建议。
- 怎么做：脚本加 `--detect-monorepo`，扫工作区配置文件，输出 per-package 的 audit 结果。
- 理由：立正定位"任意 Git 项目"，monorepo 是重要子集。但**不建议立正复制 release-please 的 manifest 模式**（过于工程化）；建议采用"检测 + 分节建议"的轻量版。
- 放哪个环节：`version_consistency_audit` + `core_docs_relevance_scan` 的 monorepo 分支。

**做法 11：`hidden` vs `skip` 语义分离**
- 做什么：区分"这个 commit 类型不出现在 CHANGELOG（hidden）"和"这个 commit 类型不参与版本 bump（skip）"。
- 怎么做：脚本里两条独立正则。
- 理由：release-please 把 `docs` 视为"CHANGELOG 里出现但不触发 patch bump"（Python 例外）；git-cliff 把 `chore(release): prepare` 视为"既不出现在 CHANGELOG 也不参与 bump"。**两种语义在不同工具有不同组合**。立正当前只有一种"标［待补充］"，太粗。
- 放哪个环节：`version_consistency_audit` 内部判定。

**做法 12：CHANGELOG "反编造"守则**
- 做什么：在 `core_docs_relevance_scan` 里明确"CHANGELOG 条目必须能追到具体 diff 片段（文件路径 + 行号或 commit SHA）"，无法追溯的一律用 `[待补充：…]`。
- 怎么做：生成 CHANGELOG 条目时附带 `ref: <file>:<line>` 或 `commit: <sha>` 溯源。
- 理由：这是立正哲学与其他工具的**根本差异**——其他工具都信任 commit message，立正信任 diff。这个"可追溯性"应写进契约。
- 放哪个环节：`core_docs_relevance_scan` 的输出契约 + `references/scan-recipes.md`。

---

## 6. 反幻觉视角：各工具在哪编造、哪克制

### 6.1 各工具编造点

**semantic-release**
- 从 commit message **直接映射到"用户影响"**（`feat:` → "Added functionality"）。若作者写 `feat: xxx` 但 diff 实际是内部重构，CHANGELOG 会写"新功能"——**这是最大编造点**。
- BREAKING CHANGE 判定只看 commit 里是否有 `!` 或 footer，不看 diff 是否真的破坏 API。
- 生成 GitHub Release 时可能带 commit hash 链接和作者名——这些是**真实元数据**，不是编造，但如果 commit 被 squash 或 rebase，链接指向可能失效。

**release-it**
- 默认用 `git log` 生成临时 changelog 供人看——**不编造用户影响，也不落到 CHANGELOG.md**。这是"克制"的默认。
- 一旦装 `@release-it/conventional-changelog` 插件，就继承 conventional-changelog 的所有编造点（见 §6.1 末条）。

**bump**
- CHANGELOG 条目是 `- [message]`——**纯 commit message 列表**，不做任何分类推断。这是"最不编造"的工具之一。它把"编造与否"的决策权完全交给作者（`review: true` 强制人工审阅）。

**release-please**
- 从 commit 前缀映射到 CHANGELOG section（`feat:` → Features）——**编造"用户影响"的语义层**。若 commit 是 `feat: internal refactor`，CHANGELOG 会归到 Features 段，读者误解为新增功能。
- 依赖图插件（`node-workspace`）会**自动给下游依赖包 patch bump 并生成 CHANGELOG 条目**——这些条目的"用户影响"是插件推断的，非作者声明。
- `sentence-case` 插件会**改 commit message 大小写**——技术上不是编造但**修改了作者原意**。

**changesets**
- **最克制**。作者手写 changeset 文件，工具不做任何推断。**代价**：作者必须自觉写 changeset。
- 唯一"推断"是依赖图 bump 时的 patch 联动——但那个 patch bump 的 CHANGELOG 条目也是"依赖版本更新"这种通用文案，不带具体用户影响声明。

**git-cliff**
- `filter_unconventional = true` 默认**排除不合规 commit**——这是"承认无法可靠映射"的克制机制。
- `chore(release): prepare for` `chore(deps.*)` `chore(pr)` 默认 `skip: true`——避免把发布流水线的自动化 commit 混进 CHANGELOG。这是"识别但不出现"的克制。
- 但一旦配置 `require_conventional = false`，它就会给所有 commit 分组，包括 `chore: something`——这时会编造"这是一个 misc 变更"这种弱推断。

**conventional-changelog**
- 它的 preset（`conventional-changelog-angular`）定义了"什么 commit 前缀对应什么 CHANGELOG section"，**编造强度取决于 preset 选择的粒度**。
- `conventional-recommended-bump` 输出的 "bump to minor" 是**建议**，不是强制——**这是重要的克制机制**：它把决策权交回给人。

### 6.2 各工具的"克制"机制

按"克制强度"从强到弱排序：

1. **changesets**：作者手写，工具零推断。
2. **bump**：commit message 原文，无分组，强制 review。
3. **git-cliff**：`filter_unconventional` + `skip: true` + `no_increment_regex`，三层过滤。
4. **conventional-changelog**：`recommended-bump` 只建议不强制。
5. **release-please**：Release PR 模式，人 merge 才生效（**这是最强的"人确认"克制**，尽管它内部的 commit→section 映射仍有编造）。
6. **release-it**：交互 prompt，人每步确认。
7. **semantic-release**：全自动，无克制。**这是"信任 commit message"哲学的极端**。

### 6.3 立正的独特定位

立正坚持"只反映真实 diff、不新增事实"——这比 changesets 更极端：
- changesets 是"作者手写用户影响描述"（人写，工具存）；
- 立正是"工具从 diff 反向推导用户影响"（工具看 diff，作者审阅）。

立正的 `core_docs_relevance_scan` 相当于一个**基于 diff 的、克制的、可追溯的 changelog 生成器**——这在所有主流工具里**没有直接对应物**。closest 的类比是 git-cliff 的 `filter_unconventional = true` + `[待补充：X]` 占位符组合。

**立正应该明确写进 SKILL.md 的"反编造守则"**：

> 立正的 CHANGELOG 条目**必须**满足以下之一：
> 1. 直接来自 diff 中新增/修改的**公开 API 表面**（导出的函数、暴露的 CLI 参数、暴露的 HTTP 端点）；
> 2. 直接来自 diff 中新增/修改的**用户可见字符串**（README 段落、错误消息、日志输出）；
> 3. 直接来自 diff 中新增/修改的**配置项或依赖**（`package.json.dependencies`、`pyproject.toml.dependencies`）；
> 4. 以上皆不满足 → 写 `[待补充：X]` 占位符，不填充。
>
> **不采信** commit message、PR 标题、issue 链接等"作者声明"作为 CHANGELOG 内容——这些由作者在提交前审阅时自行补入。

---

## 附录 A：本调研未覆盖但值得后续调研

- **Lerna / Nx**（monorepo 编排层，与 changesets 组合）
- **Dune / Nix**（`version` 字段在 shell/Nix 文件里）
- **C/C++ CMake**：`CMakeLists.txt` 的 `project(<name> VERSION x.y.z)`
- **Android Gradle**：`buildSrc/src/main/java/Dependencies.kt` 里集中管理
- **Bun**：`bun.lockb`（二进制锁文件，需特殊处理）
- **Cargo workspace `workspace.package.version`** 继承字段
- **npm `publishConfig.tag`** 与 distribution channel

## 附录 B：参考链接

- [semantic-release](https://github.com/semantic-release/semantic-release) · [README](https://github.com/semantic-release/semantic-release/blob/main/README.md)
- [semantic-release commit-analyzer default-release-rules.js](https://github.com/semantic-release/commit-analyzer/blob/main/lib/default-release-rules.js)
- [semantic-release default-release-types.js](https://github.com/semantic-release/commit-analyzer/blob/main/lib/default-release-types.js)
- [release-it](https://github.com/release-it/release-it) · [README](https://github.com/release-it/release-it/blob/main/README.md) · [config/release-it.json](https://github.com/release-it/release-it/blob/main/config/release-it.json)
- [fabiospampinato/bump](https://github.com/fabiospampinato/bump) · [README](https://github.com/fabiospampinato/bump/blob/main/readme.md)
- [googleapis/release-please](https://github.com/googleapis/release-please) · [strategies directory](https://github.com/googleapis/release-please/tree/main/src/strategies) · [manifest-releaser.md](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md) · [customizing.md](https://github.com/googleapis/release-please/blob/main/docs/customizing.md)
- [release-please node.ts](https://github.com/googleapis/release-please/blob/main/src/strategies/node.ts)
- [release-please python.ts](https://github.com/googleapis/release-please/blob/main/src/strategies/python.ts)
- [release-please rust.ts](https://github.com/googleapis/release-please/blob/main/src/strategies/rust.ts)
- [release-please maven.ts](https://github.com/googleapis/release-please/blob/main/src/strategies/maven.ts)
- [release-please ruby.ts](https://github.com/googleapis/release-please/blob/main/src/strategies/ruby.ts)
- [changesets/changesets](https://github.com/changesets/changesets) · [docs/decisions.md](https://github.com/changesets/changesets/blob/main/docs/decisions.md)
- [git-cliff](https://github.com/orhun/git-cliff) · [default cliff.toml](https://github.com/orhun/git-cliff/blob/main/config/cliff.toml) · [bump docs](https://git-cliff.org/docs/configuration/bump)
- [conventional-changelog](https://github.com/conventional-changelog/conventional-changelog)
- [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
- [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
