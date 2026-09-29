# 发行版本一致性（提交前门槛，仅当涉及 release）

## 何时进入
见 `judgment-criteria.md` 的"涉及 release"。不涉及则跳过本步。

## 各生态版本承载文件
- Node：`package.json` 的 `version`（可能多包：`packages/*/package.json`）。
- Rust：`Cargo.toml` 的 `[package].version`（workspace 用 `[workspace.package].version` + 成员 inherit）。
- Python：`pyproject.toml` 的 `[project].version` / `__init__.py` 的 `__version__` / `setup.py`。
- Go：不存版本文件，用 git tag（`vX.Y.Z`）；一致性指 tag 与模块语义对齐。
- JVM：`pom.xml` 的 `<version>` / `gradle.properties` 的 `version=`。
- .NET：`*.csproj` 的 `<Version>` 或 `<PackageVersion>`。
- Ruby：`*.gemspec` 的 `version` / `lib/**/version.rb`。
- 跨语言/多模块：全部版本文件都要一致。

## 一致性规则
1. 跑 `version_consistency_audit.ps1`，拿全部版本串。
2. 若不一致：
   - 提议统一版本号（语义化版本：feat→minor、fix→patch、BREAKING→major；取最高或用户意图）。
   - 用 `ask_user_question` 确认版本号，不擅自定。
   - 一致 bump 所有版本文件。
3. CHANGELOG：按 `../assets/templates/changelog-entry.md` 补一条，只写 diff 支撑的变化。
4. tag：记录"建议打 `vX.Y.Z` tag"的计划；推 tag 是远程不可逆，按 `autonomy-and-safety.md` 最终确认。

## 红线
- 不编造版本号；版本号只来自真实版本文件或用户确认。
- 不擅自跳大版本；语义判断不确定时问用户。
- Go 仓库无版本文件时，不创建假的版本文件，只处理 tag 计划。