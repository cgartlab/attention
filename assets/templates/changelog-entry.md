# CHANGELOG 条目结构（模板）

本文件只给**条目长什么样**（骨架与格式）。
**分节规则**（哪类变更进哪一节、`hidden` 与 `skip`、条目溯源的采信范围）**以 `../references/changelog-sections.md` 为唯一权威**——本文件不复述，避免两处漂移。

## 骨架（Keep a Changelog 的六类小节，不得自创类别）

```
## [Unreleased]

### Added
- <新增能力，必须能追到 diff>

### Changed
- <变更，必须能追到 diff>

### Deprecated
- <仍可用但即将移除，必须能追到 diff>

### Removed
- <本次移除，必须能追到 diff>

### Fixed
- <修复，必须能追到 diff>

### Security
- <安全相关修复/加固，必须能追到 diff>
```

格式要求：
- 空的类别**省略**，不留空标题。
- 同一版本内小节顺序与上面一致（Added → Changed → Deprecated → Removed → Fixed → Security）。
- 条目一律以 `- ` 开头，一条一件事，祈使/陈述口径与文件既有风格一致。
- **破坏性变更不单列小节**（Keep a Changelog 没有单独的 Breaking 分类）：写在**适用的那个六类小节**里，并在条目开头加粗标注 `**BREAKING:**`。例如：
  ```
  ### Removed
  - **BREAKING:** 移除 `/v1/users` 端点；调用方改用 `/v2/users`。
  ```
  （具体写进哪一节，按 `../references/changelog-sections.md` 的分节表判定。）
- 条目可选附溯源标记：`—— ref: src/percent.js:formatPercent()` 或 `—— commit: a1b2c3d`。

## 版本发布时
- 把 `## [Unreleased]` 改名为 `## [x.y.z] - YYYY-MM-DD`（版本号必须与所有版本承载文件一致，清单见 `../references/version-file-inventory.md`；日期取**真实**日期，不编造），并**新建一个空的 `[Unreleased]`**。
- monorepo 每个包一个 CHANGELOG（放在该包目录下）。
- 上述两条的完整规则见 `../references/changelog-sections.md` §四。

## 红线
- 每条条目必须能追到本次 diff；追不到就标 `［待补充：…］` 占位符，**不填充**（采信范围见 `../references/changelog-sections.md` §三，通用溯源规则见 `../references/core-docs-sync.md`）。
- 不编造贡献者、不编造 issue 号。
- 语义化版本取值（feat→minor、fix→patch、BREAKING→major）与 bump 决策见 `../references/release-versioning.md`。
