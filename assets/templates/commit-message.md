# 提交信息规约

## 规约选择
- 仓库已用 conventional commits → 沿用 `type(scope): subject`。
- 仓库有自己的风格（读 `git log --pretty=format:%s -n 20`） → 沿用其风格。
- 都不明显 → 默认 conventional commits。

## Conventional Commits 格式
```
<type>(<scope>)<!>: <subject>

<body：讲 WHY>

<footer：BREAKING CHANGE、Closes #123 等>
```

### `!` 的语法位置（写错会静默失效）
- **正确**：`type(scope)!: subject` —— `!` 紧跟在 **scope 的右括号之后、冒号之前**。
  - `feat(api)!: 移除 /v1 兼容层`
  - 没有 scope 时：`feat!: 移除 /v1 兼容层`（`!` 紧跟 type，仍在冒号前）
- **错误**（不会触发破坏性变更识别）：`feat!(api): ...`、`feat(api): !...`、`feat(api)! ...`（漏冒号）、`!feat(api): ...`
- `!` 只标"有破坏性变更"，**仍必须在 body/footer 里写清破坏点**；两者不是替代关系。

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
- **revert**：回滚此前的提交。格式：`revert: <被回滚提交的 subject>`，body 里写 `This reverts commit <SHA>.`，并说明**为什么要回滚**（同样属于 WHY）。

## body 写 WHY，不写 WHAT
- **diff 已经说明 WHAT**（改了哪些文件、哪些行），body 再复述一遍是噪音。
- body 要回答的是 diff 看不出来的：**为什么这么改**——原来的做法哪里不行、为什么选这个方案、放弃了什么替代方案、有什么副作用需要评审者知道。
- 反例（WHAT，无价值）：`body: 把 formatPercent 里的判断改成 num === 0`
- 正例（WHY）：`body: 除零时旧逻辑返回 Infinity，前端把它渲染成 "∞%"，用户以为是真值。改成显式返回 "0%" 并在调用点保持旧签名，避免动到下游三个调用方。`

## 示例
**示例 1**（普通修复）
```
fix(auth): 修正 JWT 刷新时漏校验过期

刷新路径只在首次校验 exp，后续请求跳过检查，导致过期令牌可用 5 分钟。
统一收敛到 verifyToken 一处判断，避免两套逻辑再次分叉。
```

**示例 2**（带正文与破坏性变更）
```
feat(api)!: 将 /v1/users 响应字段从 snake_case 改为 camelCase

BREAKING CHANGE: 响应字段命名变更，调用方需同步。
与 SDK 1.x 的字段生成规则对齐，否则每加一个字段都要手写映射。
迭代三个月后映射表已积累 40 条特例，维护成本超过一次性破坏的成本。
```

## 提交前质量自检清单（逐条打勾）
- [ ] **type 合法**：在上面那份 type 清单里（或仓库实际使用的集合里）。
- [ ] **subject ≤ 72 字符**，祈使句、首字母小写（或沿用仓库习惯）、**结尾不加句号**。
- [ ] **body 讲 WHY**，不是复述 diff（自问：删掉 body 后，评审者还能理解为什么这么改吗？）。
- [ ] **`!` 位置正确**：`type(scope)!: subject`——在 scope 右括号后、冒号前；有 `!` 就有 `BREAKING CHANGE:` footer 或 body 里的破坏点说明。
- [ ] **可溯源**：body 里出现的 issue/PR 号、commit SHA、文件名都真实存在（`git log` / `gh` 查得到），不编号码。
- [ ] **一个提交一个意图**：混了两种改动就拆开分别提交。
- [ ] **没有混进无关文件**：`git status` 里被 `.gitignore` 排除过的、临时生成的文件不得进提交。

## 红线
- subject 用祈使句、首字母小写（或沿用仓库习惯）、不加句号。
- 不编造 issue 号；引用真实存在的 `Closes #N`。
- 一个提交一个意图；混合改动先拆分再分别提交。
