# 版本文件详表（跨生态）

> **用途**：判断"还有哪个文件要跟着版本号一起改"时的**核对清单**。
> 由 `release-versioning.md`（一致性规则）与 `environment-and-prereqs.md` §5（项目画像）引用；那两处**不再自带清单**——同一份清单写两处必然漂移，这里是唯一事实源。
> 字段名与 `null`/`[]` 语义仍以 `scan-recipes.md` 的 JSON 契约为准；脚本实际识别的文件见 `version_consistency_audit`。

**没有工具能自动覆盖所有语言。** 下表是人工/模型核对用的清单，不是"跑一下脚本就完事"的保证；脚本能识别的子集只覆盖常见路径，表里没有的生态要模型自己按 `git ls-files` 找。

## Node / JavaScript / TypeScript

| 生态 | 文件 | 字段位置 | 是否必备 | 备注 |
|---|---|---|---|---|
| Node | `package.json` | 顶层 `version` | **必备** | 唯一的权威版本源。不得取 `dependencies.*.version` 等嵌套同名键 |
| Node | `package-lock.json` / `npm-shrinkwrap.json` | 根 `version` **与** `packages[""].version` | 有则必核对 | lockfile **不是**包管理器算出来的，只是缓存声明；两处都要改，否则与 `package.json` 漂移 |
| Node | `pnpm-lock.yaml` / `yarn.lock` | 通常由包管理器自管 | 一般不手改 | 不承载权威版本；手改易被下一次 install 覆盖。只在 CI 校验 lockfile 同步时才需要动 |

## Python

| 生态 | 文件 | 字段位置 | 是否必备 | 备注 |
|---|---|---|---|---|
| Python | `pyproject.toml` | `[project].version` 或 `[tool.poetry].version` | 现代项目必备 | Poetry 项目用后者；两处同时存在时以项目实际构建后端为准，别各改一半 |
| Python | `setup.py` | `version=` | 老项目 | 与 `pyproject.toml` 并存时**两处都要对齐**（很多仓库处于迁移中途） |
| Python | `setup.cfg` | `[metadata] version` | 老项目 | 同上，历史遗留三件套之一 |
| Python | `<pkg>/__init__.py`、`src/<pkg>/__init__.py` | `__version__` | 常见 | 运行时读到的版本常来自这里；与打包元数据不一致会导致"装了 A 版却报 B 版" |
| Python | `version.py` | `__version__` / `VERSION` | 可选 | 同上 |

## Rust / Go

| 生态 | 文件 | 字段位置 | 是否必备 | 备注 |
|---|---|---|---|---|
| Rust | `Cargo.toml` | `[package].version` | **必备**（普通项目） | workspace 项目**同时**含 `[workspace.package].version` 与各成员 `[package].version`（成员常写 `version.workspace = true` 继承）——只改一处就造出"半对齐" |
| Rust | `Cargo.lock` | `[[package]]` 中 `name` == 根包名者的 `version` | 有则必核对 | 同 Node lockfile：缓存声明，需与应用版本一起改 |
| Go | `go.mod` | **无 version 字段** | — | **tag 是唯一版本源**（`vX.Y.Z`）。一致性指 tag 与模块语义对齐，不是去改文件 |
| Go | `VERSION` / `version.go` | 自定义 | 可选 | 有就一起核对；没有**不要**创建 |

## JVM（Maven / Gradle）

| 生态 | 文件 | 字段位置 | 是否必备 | 备注 |
|---|---|---|---|---|
| JVM | `pom.xml` | `<version>` | Maven 必备 | 多模块项目**含 `<parent><version>`**——父子版本一起改，否则 `mvn` 直接解析失败 |
| JVM | `gradle.properties` | `version=` | 常见 | Gradle 项目把版本外置到这里，`build.gradle` 里引用它 |
| JVM | `build.gradle(.kts)` | `version =` | 视项目 | 与 `gradle.properties` 并存时以实际生效者为准；两处都写会有一处是死代码 |

## .NET / Ruby

| 生态 | 文件 | 字段位置 | 是否必备 | 备注 |
|---|---|---|---|---|
| .NET | `*.csproj` | `<Version>` / `<PackageVersion>`（亦有 `<VersionPrefix>`/`<VersionSuffix>`） | 项目级必备 | 多项目 solution 每个 `.csproj` 都要看 |
| .NET | `Directory.Build.props` | 同上，集中定义 | 常见 | 集中式项目在此改一处即全生效——**优先级高于 `.csproj`**，别只改单项目 |
| .NET | `global.json` | `sdk.version` | — | ❌ **不是产品版本**（是 SDK 工具链版本）。不要把它纳入版本一致性核对 |
| Ruby | `lib/<pkg>/version.rb` | `VERSION =` | gem 必备 | gem 的版本源 |
| Ruby | `*.gemspec` | `spec.version =` | 必备 | 通常引用 `version.rb` 的常量；若硬编码则两处都要改 |
| Ruby | `Gemfile.lock` | 依赖树 | 有则必核对 | 同 lockfile 规则 |

## 其他生态

| 生态 | 文件 | 字段位置 | 是否必备 | 备注 |
|---|---|---|---|---|
| PHP | `composer.json` | `version`（很多项目省略，靠 VCS tag） | 视项目 | 省略时以 tag 为准，**不要**为了"一致性"新加 `version` |
| Dart/Flutter | `pubspec.yaml` | `version:`（可带 `+build`） | 必备 | `+build` 是构建号，不要当成版本号的一部分去比对 |
| Elixir | `mix.exs` | `@version` / `version:` | 必备 | |
| Bazel | `MODULE.bazel` | `version =`（module 声明） | 可选 | |
| R | `DESCRIPTION` | `Version:` | **必备** | 配套 `NEWS.md` 记变更（R 生态的 CHANGELOG 惯例） |
| OCaml | `*.opam` | `version:` | 必备 | |
| Swift / CocoaPods | `Package.swift`、`*.podspec` | `version:` / `s.version` | 必备 | CocoaPods 常另配 `*.podspec.json` |
| Helm | `Chart.yaml` | `version` **与** `appVersion` | 必备 | 两者语义不同（chart 版本 vs 应用版本）；只 bump 一个是最常见的漂移 |
| C/C++ | `CMakeLists.txt` | `project(... VERSION x.y.z)` | 常见 | 也可能拆到 `version.h` / `VERSION` 文件 |
| 通用兜底 | `VERSION`、`version.txt` | 纯文本版本串 | 可选 | 存在即纳入核对 |

## Agent Skill / 插件仓库

| 生态 | 文件 | 字段位置 | 备注 |
|---|---|---|---|
| agent-skill | `SKILL.md` | YAML frontmatter 的 `metadata.version`（无则顶层 `version`） | **Skill 仓库的真实版本号就在这里**；不纳入清单会让 `version_files=[]`、`consistent=null`，等于巡不到自己的版本（实测本仓库即如此） |
| claude-plugin | `.claude-plugin/plugin.json` | 顶层 `version` | 插件市场分发用 |
| — | `VERSION` / `version.txt` | 纯文本 | 见"其他生态"的通用兜底 |
## 结论要点（判定时的三条硬提醒）

1. **没有工具能自动覆盖所有语言**——上表是核对清单；脚本只认常见路径，剩下靠模型按 `git ls-files` 自己找。找不到版本文件时如实说"没有版本文件"（`consistent=null`），**不要创建**假的版本文件。
2. **lockfile 的版本字段必须一起核对**：`package-lock.json`、`Cargo.lock`、`Gemfile.lock`、`pnpm-lock.yaml` 等里的版本**不是包管理器现算的**，只是缓存声明——它不会自动跟随 `package.json`/`Cargo.toml`，会静默漂移。
3. **"版本文件"的定义要宽**：除了上述清单文件，还包括**README 内嵌的版本号**与**注释锚点**——例如 release-please 的 `x-release-please-version` 标记、Terraform module README 里的版本徽章/示例。改版本时一并核对，漏掉它们就是"文件都齐了但文档在说谎"。
