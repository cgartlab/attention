# 发行版本一致性（提交前门槛）

## 何时进入
由 `judgment-criteria.md` 的**多层门**决定，本文件不复述门本身：
- 脚本给出**信号层**（`release_signals[]`，宽口径：触及版本文件 / `chore(release)` / `feat!`·`fix!` / `BREAKING CHANGE:` footer / `feat:` / `fix:` / 用户明示发版）。
- **门槛层（是否真的 bump）是模型职责**，必须写明理由（哪条 diff/提交支撑）。判"不需要 bump"→ 跳过本步，但理由要进报告。

## 版本承载文件（跨生态）
**详表见 `references/version-file-inventory.md`**——生态 / 文件 / 字段位置 / 是否必备 / 备注，一张表全列。**本文件不复述清单**（同一份清单写两处必然漂移）。

该表覆盖：Node、Python、Rust、Go、JVM（Maven/Gradle）、.NET、Ruby、PHP、Dart、Elixir、Bazel、R、OCaml、Swift/CocoaPods、Helm、C/C++（CMake），以及各语言的 lockfile 与通用兜底文件（`VERSION`/`version.txt`）。

只有三条容易漏的要点**必须**在这里说清：

1. **lockfile 的版本字段必须一起核对**（`package-lock.json`/`npm-shrinkwrap.json` 的根 `version` 与 `packages[""].version`、`Cargo.lock`、`Gemfile.lock`、`pnpm-lock.yaml`）。它不是包管理器算出来的产物，只是一份**缓存声明**——你不改它，它就和 `package.json` 一起漂移，而没人会注意到。
2. **有特征文件 ≠ 有产品版本**：`.NET` 的 `global.json` 是 SDK 版本、`go.mod` 根本没有版本字段。别把工具链版本当成产品版本去"对齐"。
3. **"版本文件"定义要宽**：也包含 README 里内嵌的版本号与注释锚点（如 `x-release-please-version`、Terraform README 的版本徽章）——改版本时一并核对。

没有任何工具能自动覆盖所有语言，所以上面的表是**核对清单**，不是"跑一下就好"的自动化保证。

## 一致性规则
1. 跑 `version_consistency_audit`，拿 `version_files[]`、`distinct_versions[]`、`consistent`、`monorepo_mode`、`packages[]`。
2. **`consistent` 语义**：`distinct_versions` 数 ≤ 1 → `true`；> 1 → `false`；**版本文件数为 0 → `null`**。
   - ⚠️ **`consistent=null` 时不得声称"版本已一致"**，也不得凭空造一个版本文件。正确说法是"本项目没有版本文件，版本一致性无从判定"（Go 模块靠 tag 的项目属此类），随后把版本门槛落到 **tag 计划**上。
3. `monorepo_mode=true` 时，`packages[]` 里每个成员的版本文件都要核对——含 workspace 级声明（如 `[workspace.package].version`）与成员继承关系；只改一处会造出"半对齐"。
4. 若不一致（`consistent=false`）：
   - 提议统一版本号（语义化版本：feat→minor、fix→patch、BREAKING→major；取最高值或用户意图）。
   - 用 `ask_user_question` 确认版本号，不擅自定。
   - **维护者指定的版本号与语义推导冲突时，按维护者裁定执行**（他有版本节奏的上下文），但两件事不能省：CHANGELOG 保留**真实分节**（`feat` 内容仍写 `### Added`，不得为迁就版本号改写成 `### Fixed`）；交付时一句话点名偏差与纠正成本（版本字段 + CHANGELOG 标题 + 重打本地 tag 三处）。不得把"按维护者指定 bump"含糊成"版本已按语义对齐"。
   - 一致 bump **所有**版本承载文件，含 lockfile 里的声明。
5. CHANGELOG：按 `changelog-sections.md` 判定分节与可见性、按 `../assets/templates/changelog-entry.md` 落格式，只写 diff 支撑的变化。**每条必须可溯源**（通用规则见 `core-docs-sync.md` 的"溯源要求"）。
6. tag：记录"建议打 `vX.Y.Z` tag"的计划。
   - **本地 `git tag` 属本地变更**，在计划门槛批准范围内执行。
   - **`git push <remote> <tag>` 属远程不可逆**，按 `autonomy-and-safety.md` 在执行点单独最终确认。两者不可混为一谈。

## 门槛通过条件
见 `judgment-criteria.md` 的"门槛通过条件"。一句话：要么已判定"需要 bump"并完成一致 bump + 可溯源 CHANGELOG + tag 计划，要么已判定"不需要 bump"并写明理由。**`consistent=null` 只算"无从判定"，不算通过。**

## 红线
- 不编造版本号；版本号只来自真实版本文件或用户确认。
- 不擅自跳大版本；语义判断不确定时问用户。
- 不把 `consistent=null` 讲成"版本已一致"。
- Go 仓库无版本文件时，**不创建假的版本文件**，只处理 tag 计划。
- 不改与本次变更无关的版本文件（顺手的"统一"是未批准的范围扩张）。
