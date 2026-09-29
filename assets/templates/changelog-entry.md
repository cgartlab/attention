# CHANGELOG 条目结构

按 Keep a Changelog 风格，只写 diff 真实支撑的变化。

```
## [Unreleased]

### Added
- <新增能力，必须有 diff 对应>

### Changed
- <变更，必须有 diff 对应>

### Fixed
- <修复，必须有 diff 对应>

### Removed
- <移除，必须有 diff 对应>

### Breaking
- <破坏性变更，必须有 diff 与 BREAKING CHANGE 对应>
```

## 版本发布时
- 把 `[Unreleased]` 升级为 `[vX.Y.Z] - YYYY-MM-DD`，版本号与所有版本文件一致。
- 日期取真实日期，不编造。

## 红线
- 每条都能在 diff 里找到出处；找不到不写。
- 不编造贡献者、不编造 issue 号。
- 语义化版本：feat→minor、fix→patch、BREAKING→major；不确定问用户。