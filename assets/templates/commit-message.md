# 提交信息规约

## 规约选择
- 仓库已用 conventional commits → 沿用 `type(scope): subject`。
- 仓库有自己的风格（读 `git log --pretty=format:%s -n 20`） → 沿用其风格。
- 都不明显 → 默认 conventional commits。

## Conventional Commits 格式
```
<type>(<scope>): <subject>

<body 可选>

<footer 可选，如 BREAKING CHANGE、Closes #123>
```

## type 取值
- feat：新功能（对应 minor）
- fix：缺陷修复（对应 patch）
- docs：仅文档
- style：格式（不影响代码逻辑）
- refactor：重构（非 feat/fix）
- perf：性能优化
- test：补测试
- chore：构建/工具/依赖
- build/ci：构建系统或 CI

## 示例
**示例 1**（普通修复）
```
fix(auth): 修正 JWT 刷新时漏校验过期
```

**示例 2**（带正文与破坏性变更）
```
feat(api)!: 将 /v1/users 响应字段从 snake_case 改为 camelCase

BREAKING CHANGE: 字段命名变更，调用方需同步。
```

## 红线
- subject 用祈使句、首字母小写（或沿用仓库习惯）、不加句号。
- 不编造 issue 号；引用真实存在的 `Closes #N`。
- 一个提交一个意图；混合改动先拆分再分别提交。