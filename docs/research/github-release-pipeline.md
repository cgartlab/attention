# 为 `cgartlab/attention` 设计商业产品级 release 流水线

> **调研范围**：只收 GitHub 官方资料（`docs.github.com`、`github/docs` 源码仓库、`googleapis/release-please` 源码与文档、`googleapis/release-please-action`、`actions/*`、`cli.github.com`、`vercel-labs/skills`）。
> **方法**：`web_search` 在本会话不可用（endpoint 报错 / HTTP 429），全部结论来自**直接抓取官方文件**。`docs.github.com` 的 HTML 页面会被导航栏截断，因此用官方正文端点 `https://docs.github.com/api/article/body?pathname=<path>` 与 `github/docs` 源仓库的 Markdown 原文。
> **口径**：每条结论标注【官方原文】（附 URL 与引文）、【源码行】（release-please 源码，属"上游实现事实"而非文档承诺）、【推断】（我的推理，未经官方确认）。
> **外部内容按不可信数据处理**：只提取信息，未执行仓库内任何脚本，未安装任何东西。
>
> 调研日期：2026-10-01。目标仓库当时**尚未推送到 GitHub**、无 tag、无 CI。

---

## 0. 结论速览（先看这三条，它们决定方案能不能落地）

### 0.1 本仓库是 private + 个人账号（Free 计划）→ 三个"商业级"要素直接不可用

| 要素 | private 仓库上的可用性 | 官方依据 |
|---|---|---|
| **Rulesets（含 tag 保护）** | ❌ **Free 计划不可用**。必须 Pro / Team / GHEC | 【官方原文】"Rulesets are available in public repositories with GitHub Free and GitHub Free for organizations, and in **public and private repositories with GitHub Pro, GitHub Team, and GitHub Enterprise Cloud**." — [gated-features/repo-rules](https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/repo-rules.md) |
| **经典 protected branches / tags** | ❌ **同样是 Pro+ 才有**（不是退路） | 【官方原文】"Protected branches are available in public repositories with GitHub Free… also available in public and private repositories with GitHub Pro, GitHub Team, GitHub Enterprise Cloud, and GitHub Enterprise Server." — [gated-features/protected-branches](https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/protected-branches.md) |
| **Artifact attestations（build provenance）** | ❌ private 仓库需要 **GitHub Enterprise Cloud** | 【官方原文】"If you are on a GitHub Free, GitHub Pro, or GitHub Team plan, artifact attestations are only available for public repositories. To use artifact attestations in private or internal repositories, you must be on a GitHub Enterprise Cloud plan." — [gated-features/attestations](https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/attestations.md) |

**含义**：在 Free 个人账号 + private 仓库上，**"tag 不可删/不可移动"这条最核心的发布不变量，平台层面给不了**。能给的只有：immutable releases（Plan 门槛见 §2.6 / §6，**未确认**是否 Free 可用）、以及 release-please 自身的流程纪律。请把"Pro 升级"当作这套流水线的**前置条件**而不是可选项。

### 0.2 `SKILL.md` 的 `metadata.version` **可以**被 release-please 直接改（已验证到源码级）

- `extra-files` 里的路径若不以 `.json/.yaml/.yml/.toml/.xml` 结尾（`SKILL.md` 就是这样），会落到 `else` 分支，使用**纯文本的 `Generic` updater**——它按**行**做正则替换，不解析 YAML。
- 【源码行】[`src/strategies/base.ts`](https://raw.githubusercontent.com/googleapis/release-please/main/src/strategies/base.ts) `extraFileUpdates()` 的分支链：`.json` → `.yaml/.yml` → `.toml` → `.xml` → `else { new Generic(...) }`。
- 【源码行】[`src/updaters/generic.ts`](https://raw.githubusercontent.com/googleapis/release-please/main/src/updaters/generic.ts)：`INLINE_UPDATE_REGEX = /x-release-please-(?<scope>major|minor|patch|version-date|version|date)/`，命中则该行第一个 semver 被替换。
- **所以注解写成 YAML 行尾注释即可**，因为它根本不按 YAML 解析——这同时回答了"对 YAML frontmatter 是否适用"：**适用，但走的不是 YAML 通道，是文本通道**。

### 0.3 最大的坑：仓库现有 `[Unreleased]` 段会与 release-please **长期共存**，不会自动合并

【源码行】[`src/updaters/changelog.ts`](https://raw.githubusercontent.com/googleapis/release-please/main/src/updaters/changelog.ts)：

```ts
const DEFAULT_VERSION_HEADER_REGEX = '\n###? v?[0-9[]';
```

`## [Unreleased]` **正好命中**这个正则（`\n` + `##` + 空格 + `[`）。插入位置是**第一个命中处之前**。结果是新版本段被插到 `## [Unreleased]` **上方**，`[Unreleased]` 连同那 42 条条目**原样保留在下面**，永不排空、永不合并。

详见 §5.1。

---

## 1. 推荐方案

### 1.1 一段话

**用 release-please 的 manifest 模式做版本与 CHANGELOG 的唯一自动化来源，release-type 选 `simple`（因为本仓库没有 `package.json`、也不需要 `version.txt`），把 `SKILL.md` 通过 `extra-files` + 行尾注解接进版本更新链路；CI 用 2 个 OS × 2 套 shell 的矩阵跑 `evals/` 与 `smoke_test`，把"双实现 parity"这条本仓库最核心的质量不变量真正守住；发版 workflow 在 release-please 打出 tag 之后、用 `git archive` 把 skill 目录打成 zip 并用 `gh release upload` 挂到 Release 上。** 人工一次性设置：打开 "Allow GitHub Actions to create and approve pull requests"、升级到 Pro（否则 tag 保护无从谈起）、启用 private vulnerability reporting。

**两处必须提前拍板的冲突**：
1. `AGENTS.md` 现在写"版本保持 0.1.0，变更记入 `[Unreleased]`，不随每次改动切版本号"——这与 release-please 的模型（每个 `feat`/`fix` → 出一个 release PR → 切版本 + 写 CHANGELOG）**直接冲突**。采用本方案 = 修改这条策略。按 `AGENTS.md` 的"加规则要配对减规则"，这条修改要在提交信息里说明。
2. `scripts/release_preflight.*` 的 `CHANGELOG [Unreleased] 就绪` 检查（要求 `[Unreleased]` 至少 1 条）在 release-please 接管后会**变成假失败**。详见 §5.2。

### 1.2 文件 → 作用

| 文件 | 路径 | 作用 | 官方依据 / 状态 |
|---|---|---|---|
| release 配置 | `release-please-config.json` | 声明 release-type、tag 形态、`extra-files`（把 `SKILL.md` 接进版本链路） | [manifest-releaser](https://raw.githubusercontent.com/googleapis/release-please/main/docs/manifest-releaser.md)、[schemas/config.json](https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json) |
| 版本状态 | `.release-please-manifest.json` | release-please 的**真实当前版本**来源；内容 `{".": "0.1.0"}` | 同上 |
| CI 门禁 | `.github/workflows/ci.yml` | PR + push 到 main 时，2 OS × 2 shell 跑 `smoke_test` 与 `run_evals`，并做版本一致性 gate | [GITHUB_TOKEN 权限](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token)、[workflow 语法](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) |
| 发版 | `.github/workflows/release.yml` | push 到 main 触发 release-please；有新 release 时打包 zip 并挂到 Release | [release-please-action README](https://raw.githubusercontent.com/googleapis/release-please-action/main/README.md) |
| 版本载体 | `SKILL.md` | 在 `version:` 行尾加 `# x-release-please-version`（**唯一需要改的现有文件**） | 【源码行】`generic.ts` |
| CHANGELOG | `CHANGELOG.md` | 由 release-please 写入新版本段（**不接管 `[Unreleased]` 的搬迁**，见 §5.1） | 【源码行】`changelog.ts` |
| 安全策略 | `SECURITY.md` | **已存在**，内容已正确指向 private vulnerability reporting | 仓库现状 |
| 贡献指引 | `CONTRIBUTING.md` | **已存在** | 仓库现状 |
| 代码所有者 | `.github/CODEOWNERS` | **建议加**（个人仓库收益有限，见 §4.5） | [About code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) |
| 依赖更新 | `.github/dependabot.yml` | **只对 `github-actions` 生态有意义**（本仓库无 npm/pip/Go 依赖） | [Dependabot 官方文档](https://docs.github.com/en/code-security/dependabot) |
| Issue/PR 模板 | `.github/ISSUE_TEMPLATE/*`、`.github/PULL_REQUEST_TEMPLATE.md` | 建议加 PR 模板（把 `CONTRIBUTING.md` 的检查清单变成勾选框） | [community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file) |
| 支持/行为准则 | `SUPPORT.md`、`CODE_OF_CONDUCT.md` | **对本仓库属形式主义**，见 §4.5 | 同上 |

### 1.3 为什么是 `simple` 而不是 `node` / `go`

| release-type | 要求的版本文件 | 对本仓库是否合适 |
|---|---|---|
| `node` | `package.json` | ❌ 本仓库没有，也不想为一个 shell/markdown skill 造一个 |
| `simple` | `version.txt` | ✅ **推荐**。`Simple` 用 `versionFile ?? 'version.txt'`；缺失时**不会报错**（见下） |
| `go` | 无（`versionFile ?? ''`，为空则**不生成版本文件更新**） | ⚠️ 技术上最干净（零警告），但语义上"Go 仓库"对一个 Agent Skill 是误导，不建议 |
| `terraform-module` | README.md 里的版本 | ❌ 会去改 README，与本仓库"版本号唯一载体是 SKILL.md"冲突 |

**关键源码事实（决定 `simple` 能否在没有 `version.txt` 时工作）**：

【源码行】[`src/strategies/simple.ts`](https://raw.githubusercontent.com/googleapis/release-please/main/src/strategies/simple.ts) 会无条件 push 一个 `version.txt` 更新，且 `createIfMissing: false`。

【源码行】[`src/github.ts`](https://raw.githubusercontent.com/googleapis/release-please/main/src/github.ts) `buildChangeSet()` 处理了这个情况：

```ts
} catch (err) {
  if (!(err instanceof FileNotFoundError)) throw err;
  // if the file is missing and create = false, just continue
  // to the next update, otherwise create the file.
  if (!update.createIfMissing) {
    this.logger.warn(`file ${update.path} did not exist`);
    continue;
  }
}
```

→ **`version.txt` 不存在时，release-please 只打一条 warning 然后跳过，不失败。** 所以 `simple` 可以不创建 `version.txt`。代价是每次运行日志里多一条 `file version.txt did not exist`。

> ⚠️ **绝对不要**把 `version-file` 指向 `SKILL.md`。`simple` 对这个字段用的是 `DefaultUpdater`，而【源码行】[`src/updaters/default.ts`](https://raw.githubusercontent.com/googleapis/release-please/main/src/updaters/default.ts) 的 `updateContent()` 是 `return this.version + '\n'`——**它会用版本号字符串整个覆盖文件**，`SKILL.md` 会被清成一行 `0.2.0`。

---

## 2. 可直接抄的配置

### 2.1 `SKILL.md` 要加什么注解（逐行说明）

**只改一行。** 现在是：

```yaml
metadata:
  version: "0.1.0"
  date: "2026-09-29"
  reference: "https://github.com/cgartlab/attention"
```

改成：

```yaml
metadata:
  version: "0.1.0" # x-release-please-version
  date: "2026-09-29"
  reference: "https://github.com/cgartlab/attention"
```

逐条规则（全部来自【源码行】`src/updaters/generic.ts`）：

1. **注解必须和版本号在同一行。** 源码注释原文："`x-release-please-version` if this string is found on the line, then replace a semver-looking string on that line with the next version"。跨行的版本号不会被改。
2. **只替换该行第一个 semver。** `VERSION_REGEX = /(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(-(?<preRelease>[\w.]+))?(\+(?<build>[-\w.]+))?/`，且用的是 `String.replace(regex, ...)`（无 `g` 标志）→ 首次匹配。`version: "0.1.0"` 这一行第一个 semver 就是 `0.1.0`，安全。
3. **`#` 的位置任意**，只要在同一行；官方文档说注解"usually in comments"（[customizing.md](https://raw.githubusercontent.com/googleapis/release-please/main/docs/customizing.md)）。放在值前面（`# x-release-please-version` 在行首）也能触发，但可读性差，不推荐。
4. **不要给 `date:` 行加 `x-release-please-version`**——它只含 `2026-09-29`，虽然不匹配 semver 正则会原样不动，但会触发一次无用匹配。
5. **`x-release-please-date` 能用但文档没写**（见 §2.6 未确认项）：源码 `INLINE_UPDATE_REGEX` 里有 `version-date|date`，但官方 [customizing.md](https://raw.githubusercontent.com/googleapis/release-please/main/docs/customizing.md) 的 inline 注解清单只列了 `version` / `major` / `minor` / `patch`。**文档与源码不一致，属于未承诺行为，建议不要依赖。**
6. **不要用块注解**（`x-release-please-start-version` … `x-release-please-end`）：块模式会把**块内每一行**的 semver 都替换掉，而 frontmatter 里还有 `2026-09-29` 这种日期（不匹配 semver，侥幸安全）以及未来可能出现的任何 `1.2.3` 形态文本。行内注解最小、最可预测。
7. **对 Agent Skills 规范无副作用**：注解是 YAML 注释，不改变 `metadata.version` 的值与类型，任何标准 YAML 解析器都会忽略它。

> **我实测不了的部分**：本会话无法运行 release-please（不许安装东西、不许跑仓库脚本）。以上全部由源码读出的行为推出，**上线前应在一张临时分支上用 `release-please release-pr --dry-run` 验证一次**——官方推荐这么做，见 [troubleshooting.md](https://raw.githubusercontent.com/googleapis/release-please/main/docs/troubleshooting.md)（"The CLI provides a `--dry-run` mode which will tell you what it would do without actually doing it"）。

### 2.2 `release-please-config.json`

> ⚠️ release-please 的配置是**严格 JSON**，官方明确说 "comments for illustration purposes only, **not supported in actual configs**"（[manifest-releaser.md](https://raw.githubusercontent.com/googleapis/release-please/main/docs/manifest-releaser.md)）。下面**没有注释**，解释都在本节文字里。

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "simple",
  "include-component-in-tag": false,
  "include-v-in-tag": true,
  "bump-minor-pre-major": true,
  "bump-patch-for-minor-pre-major": true,
  "changelog-path": "CHANGELOG.md",
  "packages": {
    ".": {
      "package-name": "attention",
      "extra-files": [
        {
          "type": "generic",
          "path": "SKILL.md"
        }
      ]
    }
  }
}
```

字段逐条：

| 字段 | 值 | 为什么 |
|---|---|---|
| `$schema` | release-please 官方 schema URL | 【官方原文】schema 根允许 `"$schema": true`（[schemas/config.json](https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json)）。让编辑器能做校验。 |
| `release-type` | `"simple"` | 见 §1.3 |
| `include-component-in-tag` | `false` | 默认 `true`。官方 troubleshooting 明确说：如果你的 tag 形态是 `v<version>`，要设 `include-component-in-tag: false`，否则 release-please 会去找 `<component>-v<version>` 并报 "Expected 1 releases, only found 0"。—— [manifest-releaser.md](https://raw.githubusercontent.com/googleapis/release-please/main/docs/manifest-releaser.md) |
| `include-v-in-tag` | `true` | 默认就是 `true`，显式写出来是为了让"tag 是 `v0.2.0`"这件事在配置里可见，与 §3 的 `v*` tag 保护对应。 |
| `bump-minor-pre-major` | `true` | 官方："Breaking changes only bump semver minor if version < 1.0.0"。1.0 之前不允许 `feat!` 把版本推到 1.0.0。 |
| `bump-patch-for-minor-pre-major` | `true` | 官方："Feature changes only bump semver patch if version < 1.0.0"。技能尚不完善，`feat:` 只跳 patch 更符合仓库现状。**这一条是可争议的**：如果你希望每次新能力都留下 minor 足迹，设为 `false`。 |
| `changelog-path` | `"CHANGELOG.md"` | 默认值就是它；显式写出来防漂移。 |
| `packages["."]` | 根路径 | `.` 是"仓库根"的特例（官方 manifest 文档："`.` is a special case for handling to root of the repository"）。 |
| `packages["."]["package-name"]` | `"attention"` | 官方：`package-name` "Ignored by packages whose release-type implements source code package name lookup (e.g. 'node'). **Required for all other packages**"。`simple` 不做名字查找，所以要给。它会影响 release PR 的分支名（`release-please--branches--main--components--attention`）。 |
| `extra-files[0].type` | `"generic"` | 显式声明走文本注解 updater。官方 customizing 文档："If you want to force the Generic updater, you must use type `\"generic\"`"。 |
| `extra-files[0].path` | `"SKILL.md"` | 相对仓库根。 |

**等价但更脆的写法**（不推荐，仅说明）：`"extra-files": ["SKILL.md"]`。字符串形式会走到 §0.2 描述的 `else` 分支，**行为完全相同**（因为 `.md` 不匹配任何特化后缀）。用对象形式是为了让"这里是通用注解 updater"这件事显式、可读、抗未来改动。

**❌ 千万不要这样写**：

```json
{ "extra-files": [{ "type": "yaml", "path": "SKILL.md", "jsonpath": "$.metadata.version" }] }
```

两个理由，都是官方/源码级的：
1. 【源码行】[`src/updaters/generic-yaml.ts`](https://raw.githubusercontent.com/googleapis/release-please/main/src/updaters/generic-yaml.ts) 用的是 `yaml.loadAll(content)`——它会**把整个 `SKILL.md` 当 YAML 解析**，frontmatter 之后的大段 Markdown 正文会让解析失败，函数 `return content`（原样返回，**静默不更新**，只打一条 warn）。
2. 同一个文件里作者的注释原文："Note that used parser does reformat the document and **removes all comments**, and converts everything to pure YAML (even JSON source). **If you want to retain formatting, use generic updater with comment hints.**" —— 这正是我们要用 generic 的原因。

### 2.3 `.release-please-manifest.json`

```json
{
  ".": "0.1.0"
}
```

- 【官方原文】"At a minimum, a manifest file must exist at the tip of the `--target-branch`. It can be empty when release-please is run for the first time but it must exist." —— [manifest-releaser.md](https://raw.githubusercontent.com/googleapis/release-please/main/docs/manifest-releaser.md)
- 【官方原文】"The simplest way to tell release-please the current version for a package it has never released before is to manually add an entry into `.release-please-manifest.json`." —— 同上
- **为什么必须是 `0.1.0` 而不是留空**：留空时 `initialReleaseVersion()` 返回 `1.0.0`（【源码行】`base.ts`），会把 `SKILL.md` 从 0.1.0 直接跳到 1.0.0。
- **这个文件是版本状态的唯一权威**。release-please **不读** `SKILL.md` 来获知当前版本——它读 manifest、读已发布 release、读 tag。`SKILL.md` 是**只写的镜像**。所以：manifest 与 `SKILL.md` 不一致时，release-please 会以 manifest 为准去写 `SKILL.md`。

### 2.4 `bootstrap-sha`：一次性设置（必须做，否则第一个 release PR 会包含全部历史）

因为仓库**没有任何 tag、没有任何 release**，release-please 找不到"上一个版本"的锚点，会把**整个提交历史**都当成未发布内容塞进第一个 release PR。

**做法**（二选一）：

**A. 用 `bootstrap-sha`（推荐）**——在 `release-please-config.json` 顶层加一个 key：

```json
"bootstrap-sha": "<40 位完整 SHA>"
```

【官方原文】"You can add a top level `\"bootstrap-sha\": <full sha value>` key/value entry to the config which will cause release-please to stop there for collecting changelog commits (so **choose one commit earlier than the first commit you want to include**). Note: once a release-please generated PR has been merged, this config value will be ignored for all subsequent runs and can be removed." —— [manifest-releaser.md](https://raw.githubusercontent.com/googleapis/release-please/main/docs/manifest-releaser.md)

取哪一笔：

```bash
# 找到 0.1.0 那一版对应的最后一笔提交（CHANGELOG 里 [0.1.0] - 2026-09-29 的那批）
git log --oneline --reverse --format='%H %ad %s' --date=short
# 从中挑"你想让它成为第一个 release PR 起点的前一笔"的完整 SHA
```

**B. 不设 `bootstrap-sha`，接受第一个 release PR 的 CHANGELOG 很长**——然后手工编辑那个 PR。不推荐，但可行。

> `bootstrap-sha` 必须是**完整** SHA（官方："full sha required"），短 SHA 不行。

### 2.5 `.github/workflows/ci.yml`

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    name: ${{ matrix.os }} / ${{ matrix.shell }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-latest
            shell: bash
          - os: ubuntu-latest
            shell: pwsh
          - os: windows-latest
            shell: bash
          - os: windows-latest
            shell: pwsh

    steps:
      - uses: actions/checkout@v4

      - name: 版本一致性 gate
        if: matrix.shell == 'pwsh'
        shell: pwsh
        run: |
          $v = pwsh -NoProfile -File scripts/version_consistency_audit.ps1 --repo . | ConvertFrom-Json
          Write-Host "version_files = $($v.version_files -join ', ')"
          Write-Host "distinct_versions = $($v.distinct_versions -join ', ')"
          if ($v.consistent -ne $true) {
            throw "版本文件不一致（consistent=$($v.consistent)）：版本必须只由 SKILL.md 的 metadata.version 承载"
          }

      - name: 冒烟（bash）
        if: matrix.shell == 'bash'
        shell: bash
        run: bash scripts/smoke_test.sh --repo .

      - name: 冒烟（pwsh）
        if: matrix.shell == 'pwsh'
        shell: pwsh
        run: pwsh -NoProfile -File scripts/smoke_test.ps1 --repo .

      - name: 全量回归（bash）
        if: matrix.shell == 'bash'
        shell: bash
        run: bash evals/run_evals.sh --fixtures-dir "$RUNNER_TEMP/attention-evals-bash"

      - name: 全量回归（pwsh）
        if: matrix.shell == 'pwsh'
        shell: pwsh
        run: pwsh -NoProfile -File evals/run_evals.ps1 -FixturesDir "$env:RUNNER_TEMP/attention-evals-pwsh"
```

关键点与依据：

| 元素 | 为什么这么写 | 依据 |
|---|---|---|
| `permissions: contents: read` | 工作流级先把默认权限收到最小，需要写权限的 job 再单独提。官方："assign permissions to jobs"、最小权限原则 | [GITHUB_TOKEN 权限](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token) |
| `on: pull_request` | **fork 安全**：`pull_request` 事件下 `GITHUB_TOKEN` 只读、secrets 不下发。注意本仓库是 private，外部无法 fork，风险面本来就小 | [Triggering a workflow](https://docs.github.com/en/actions/using-workflows/triggering-a-workflow) |
| `concurrency` + `cancel-in-progress: true` | 同一 ref 上连续 push 时取消旧运行，省额度 | [workflow 语法 · concurrency](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency) |
| `strategy.matrix.os` + `fail-fast: false` | 一个 OS 红不要掩盖另一个 OS 的结果；本仓库的**双实现 parity 是核心不变量**，必须两个 OS 都跑 | [workflow 语法 · matrix](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idstrategymatrix) |
| `if: matrix.shell == '...'` | 同一 job 内用条件分派，避免 4 个 job 的重复 checkout | — |
| `$RUNNER_TEMP` / `$env:RUNNER_TEMP` 下再分 `-bash` / `-pwsh` 子目录 | 对应 `AGENTS.md` 的"并发注意"：两个 runner 同时跑会互相删 fixture。分目录后即使在同一台机器上也不会互踩 | `AGENTS.md` |
| **不在这里跑 `release_preflight`** | 见 §5.2：preflight 的 `[Unreleased]` 检查与 release-please 模型冲突。这里只取它的"版本一致性"这一条，直接调 `version_consistency_audit` 更精确 | — |

**`version_consistency_audit` 的字段名是从源码确认的**：`is_git, version_files, inherited_version_files, distinct_versions, consistent`（`scripts/version_consistency_audit.ps1:261` 的 `--help` 文本）。注意 `consistent` 在**没有版本文件时是 `null`**（源码 `version_consistency_audit.ps1:457-459`：`$consistent = $null; Add-Warn 'no-version-files'`）。上面的 gate 用 `-ne $true` 而不是 `-eq $false`，正是为了把 `null` 也拦下来——这与 `release_preflight.ps1` 的口径一致（它在 `consistent -eq $null` 时也判失败，见 `release_preflight.ps1:88`）。

### 2.6 `.github/workflows/release.yml`

```yaml
name: release

on:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  release-please:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
    outputs:
      release_created: ${{ steps.release.outputs.release_created }}
      tag_name: ${{ steps.release.outputs.tag_name }}
      version: ${{ steps.release.outputs.version }}
    steps:
      - name: Release Please
        id: release
        uses: googleapis/release-please-action@v4
        with:
          token: ${{ secrets.RELEASE_PLEASE_TOKEN }}
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json

  package:
    needs: release-please
    if: ${{ needs.release-please.outputs.release_created == 'true' }}
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ needs.release-please.outputs.tag_name }}
          persist-credentials: false

      - name: Gate — tag 上的版本必须与 SKILL.md 一致
        shell: pwsh
        run: |
          $v = pwsh -NoProfile -File scripts/version_consistency_audit.ps1 --repo . | ConvertFrom-Json
          if ($v.consistent -ne $true) {
            throw "tag 已打出但版本不一致（consistent=$($v.consistent)）：$($v.version_files -join ', ')"
          }

      - name: 打包 skill 载荷
        shell: bash
        run: |
          set -euo pipefail
          VERSION="${{ needs.release-please.outputs.version }}"
          git archive --format=zip \
            -o "attention-skill-${VERSION}.zip" \
            HEAD SKILL.md README.md LICENSE CHANGELOG.md references assets scripts
          sha256sum "attention-skill-${VERSION}.zip" > "attention-skill-${VERSION}.zip.sha256"
          ls -l attention-skill-*

      - name: 挂到 Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release upload "${{ needs.release-please.outputs.tag_name }}" \
            attention-skill-*.zip attention-skill-*.zip.sha256
```

依据：

| 元素 | 依据 |
|---|---|
| `permissions: contents: write` / `pull-requests: write` / `issues: write` | 【官方原文】release-please-action README 的 "Workflow Permissions" 节，三行权限块逐字复制："This workflow will need the following permissions in your workflow file: `contents: write` / `issues: write` / `pull-requests: write`" — [release-please-action README](https://raw.githubusercontent.com/googleapis/release-please-action/main/README.md) |
| `token: ${{ secrets.RELEASE_PLEASE_TOKEN }}` | 【官方原文】"If using GitHub Actions, you will need to specify a `token` for your workflows to run on Release Please's releases and PRs." + "You will want to configure a GitHub Actions secret with a Personal Access Token if you want GitHub Actions CI checks to run on Release Please PRs." — 同上。**这是"用 GITHUB_TOKEN 够不够"的答案：能跑，但 release-please 用 `GITHUB_TOKEN` 造的 PR/tag **不会触发**后续 workflow**（"events triggered by the `GITHUB_TOKEN` will not create a new workflow run"），于是你的 CI 永远不在 release PR 上跑。为了让 CI 门禁对 release PR 生效，必须用 PAT 或 GitHub App token。 |
| `gh release upload` | 【官方原文】release-please-action README 的 "Attaching files to the GitHub release" 节用的就是这个命令，并且是在**同一个 workflow 内**用 `if: steps.release.outputs.release_created` 守卫。**这正是为什么不能用 `on: release: types: [published]` 另起一个 workflow**——`GITHUB_TOKEN` 造的 release 事件不会触发新 workflow。 |
| `git archive --format=zip` | 只用 git 自带能力，只打包已跟踪文件，天然排除 `evals/results/`、本地临时目录与 `.gitignore` 里的东西。无需额外 action。 |
| `ref: ${{ needs.release-please.outputs.tag_name }}` | 从 tag 位置检出，保证 zip 内容与 tag 严格对应。 |
| `persist-credentials: false` | 不在 `.git/config` 里留下 `GITHUB_TOKEN`（官方刻意设计的选项，避免后续步骤意外用到它）。 |
| `sha256sum` 附一份校验文件 | 无编译产物时，这是最朴素的可追溯性凭据。**注意：这不是签名，也不是 attestation。** |

#### 变体：如果之后启用了 immutable releases

**官方最佳实践要求换顺序**，否则 `gh release upload` 会因为"发布后资产不可改"而失败。

【官方原文】"We recommend you use the following workflow for publishing an immutable release. 1. Create the release as a draft. 1. Attach all associated assets to the draft release. 1. Publish the draft release." — [Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)

对应的两处改动：

1. `release-please-config.json` 顶层加：
   ```json
   "draft": true,
   "force-tag-creation": true
   ```
   【官方原文】`force-tag-creation`："This is particularly useful when `draft` is enabled. By default, GitHub does not create a Git tag for draft releases until they are published. This 'lazy tag creation' behavior causes release-please to fail to find the previous release when running subsequent `release-pr` commands, potentially generating incorrect changelogs that include the entire commit history." — [schemas/config.json](https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json)
2. `package` job 末尾加一步发布：
   ```yaml
      - name: 发布草稿（资产已齐备，此刻起不可变）
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh release edit "${{ needs.release-please.outputs.tag_name }}" --draft=false
   ```
   > `gh release edit --draft=false` 这个具体写法我**没有在官方手册里逐字确认**（`gh release edit` 存在且有 `--draft` 布尔旗标是确定的），**列入 §6 未确认项，需实测**。

#### 明确标注为「未确认 / 需实测」的字段

| 项 | 状态 |
|---|---|
| `gh release edit <tag> --draft=false` 的确切写法与是否支持从草稿发布 | **未确认，需实测** |
| `pull-requests: write` + `issues: write` 是否**都**必需（README 说需要；但 `issues` 权限通常只为给 PR 打 `autorelease: pending` 标签） | **未确认**，按官方 README 全写上最安全 |
| `googleapis/release-please-action@v4` 在 private 仓库上的任何额外限制 | **未在官方文档中找到任何 private 专属说明**。找不到 ≠ 不支持；恰恰相反，文档从未区分可见性，**推断可用**，但请以小仓库实测为准 |
| `release-please-config.json` 里的 `"draft"` / `"force-tag-creation"` 与 `extra-files` 同时使用时的交互 | 字段各自都有官方定义，但**组合行为未确认** |

---

## 3. 人工一次性设置清单（GitHub 侧开关）

| # | 设置 | 路径 | 为什么 | 官方链接 |
|---|---|---|---|---|
| 1 | **升级到 GitHub Pro** | 个人 Settings → Billing | Free 计划下 private 仓库**没有** rulesets，也**没有**经典分支/标签保护（§0.1）。这是整套"商业级"的前置条件 | [repo-rules gating](https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/repo-rules.md)、[protected-branches gating](https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/protected-branches.md) |
| 2 | **Allow GitHub Actions to create and approve pull requests** | repo → Settings → Actions → General → Workflow permissions | 【官方原文】"By default, when you create a new repository in your personal account, **workflows are not allowed to create or approve pull requests**." release-please 必须能开 PR | [Manage GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository) |
| 3 | **默认 `GITHUB_TOKEN` 权限设为 Read repository contents** | 同上，"Workflow permissions" | 【官方原文】"By default, when you create a new repository in your personal account, `GITHUB_TOKEN` only has read access for the `contents` and `packages` scopes."——默认已经是收紧的，**确认一下别被改成 Read and write** | 同上 |
| 4 | **创建 PAT 存成 `RELEASE_PLEASE_TOKEN`** | Settings → Developer settings → Personal access tokens（fine-grained 或 classic） | 让 CI 能在 release PR 上跑（§2.6）。**我未能从官方文档确认所需的最小 scope 清单**，列入 §6 | [release-please-action README](https://raw.githubusercontent.com/googleapis/release-please-action/main/README.md) |
| 5 | **启用 private vulnerability reporting** | repo → Settings → Security → 找到 "Private vulnerability reporting" 打开 | `SECURITY.md` 已经把用户引到这里（"仓库 → Security → Report a vulnerability"）。**不打开的话文档是空指针** | [Configuring private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository) |
| 6 | **tag ruleset：`v*`** | repo → Settings → Rules → Rulesets → New ruleset → **Tag** | Target tags 填 `v*`；勾选 **Restrict deletions**（默认已勾）、**Block force pushes**（默认已勾）、**Restrict updates**（= 禁止移动已发布的 tag）。Enforcement 选 **Active** | [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)、[Available rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets) |
| 7 | **main 分支 ruleset**：`Require a pull request before merging` | repo → Settings → Rules → Rulesets → New ruleset → Branch，target `~DEFAULT_BRANCH` | 让 release PR 也必须走评审 | 同上 |
| 8 | **`Require status checks to pass`**，把 `ci` 的矩阵 job 加为必需检查 | 同上，ruleset 的 required status checks | 让 §2.5 的门禁真正拦得住合并 | 同上 |
| 9 | （可选）**Immutable releases** | repo → Settings → 滚到 "Releases" → 勾 **Enable release immutability** | 【官方原文】"Be aware that immutability will only apply to future releases." | [Preventing changes to your releases](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes) |
| 10 | （可选）**Workflow 里允许的 actions 白名单** | repo → Settings → Actions → General → Actions permissions | 收紧到只允许 `actions/*` 与 `googleapis/release-please-action` | [Manage GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository) |
| 11 | **artifact/log retention** | repo → Settings → Actions → General | private 仓库可设 1–400 天（public 只到 90 天）。本仓库产物小，默认 90 天够用 | [Configuring the retention period](https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization) |

### 3.1 用 API 建 tag ruleset 的确切请求体

**官方 REST 参考给出的字段与枚举**（[REST API endpoints for rules](https://docs.github.com/en/rest/repos/rules)，正文经 `https://docs.github.com/api/article/body?pathname=/en/rest/repos/rules` 取得）：

- `target`：默认 `branch`，"Can be one of: `branch`, `tag`, `push`"
- `enforcement`（**required**）："Can be one of: `disabled`, `active`, `evaluate`"；且 "evaluate is only available with GitHub Enterprise"
- `conditions.ref_name.include` / `exclude`：数组，`fnmatch` 语法（官方另有说明），"Also accepts `~DEFAULT_BRANCH` … or `~ALL`"
- `rules[].type` 的相关枚举：`creation`（"Only allow users with bypass permission to create matching refs"）、`update`（"Only allow users with bypass permission to update matching refs"）、`deletion`（"Only allow users with bypass permissions to delete matching refs"）、`non_fast_forward`（"Prevent users with push access from force pushing to refs"）
- 成功返回 **201 Created**

> ⚠️ **两个易错点（我实测不了，但文档措辞很明确）**：
> 1. `conditions.ref_name.include` 的示例用的是**完整 ref**（`refs/heads/main`），而 UI 里填的是 `v*`。**`v*` 到底要不要写成 `refs/tags/v*`，官方正文没有给出 tag 的示例**——列入 §6，**建议先在 UI 里建一次、再用 `GET /repos/{owner}/{repo}/rulesets/{ruleset_id}` 读出真实结构**，这是最稳的确认方式。
> 2. `update` 规则带一个 **required** 参数 `parameters.update_allows_fetch_and_merge`（boolean），而官方示例里其它规则大多不需要参数。**漏掉这个 required 字段会导致 422。** 对本仓库（禁止移动 tag）应设 `false`。

```json
{
  "name": "protect-release-tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/tags/v*"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "update",
      "parameters": { "update_allows_fetch_and_merge": false }
    }
  ]
}
```

```bash
gh api --method POST /repos/cgartlab/attention/rulesets --input ruleset.json
```

> `include` 用 `refs/tags/v*` 还是 `v*`：**未确认**。建完后立刻 `gh api /repos/cgartlab/attention/rulesets` 核对回读结果。

### 3.2 已发布的 Release tag 能不能被移动？

【官方原文】immutable releases 的定义就是"**Git tags cannot be moved**：Once an immutable release is published, its associated Git tag is locked to a specific commit, cannot be changed, and cannot be deleted while the release exists. If you delete the immutable release, you can delete the tag, but **you cannot reuse the same tag name**." —— [Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)

**反过来说（【推断】）**：**不开 immutable releases 时，GitHub 默认不阻止你移动或删除已发布 Release 的 tag**——Git 层面 tag 只是一个可移动的 ref，唯一的平台级阻力来自 ruleset 的 `update` / `deletion` / `non_fast_forward` 规则。我在官方文档里**没有找到**任何"已发布 Release 的 tag 默认受保护"的表述。这一条列入 §6，标为**推断**。

其他 immutable releases 事实（【官方原文】，同页）：
- 保护范围：tag 锁定到具体 commit、不能改、在 release 存在期间不能删；**所有附加资产不能修改或删除**。
- **不**锁定：标题、release notes、"是否 prerelease"、"是否 latest" 仍可编辑。
- 自动产出 **release attestation**（"a cryptographically verifiable record of a release containing the release tag, commit SHA, and release assets"）。
- 附带防"仓库借尸还魂"攻击：删库重建同名仓库后，**不能复用**原仓库 immutable release 用过的 tag。
- 页面标识：release 标题下方出现 🔒 **Immutable**。
- **Plan 可用性：未确认。** 该文档页 frontmatter 是 `versions: feature: immutable-releases`（feature flag 门控），**没有** `product:` 门控行；`data/reusables/gated-features/immutable-releases.md` **返回 404**。→ 可能对所有计划开放，但**我无法确认 Free + private 能用**。**最可靠的确认方式**：去 repo → Settings → 看有没有 "Releases / Enable release immutability" 这一段；没有就是不可用。列入 §6。

---

## 4. private 仓库上做不了 / 不该做的事

### 4.1 ❌ Artifact attestations（`actions/attest-build-provenance` / `actions/attest`）——private 需 GHEC

- **结论**：Free/Pro/Team 的 private 仓库**不能用**。需要 GitHub Enterprise Cloud。
- 【官方原文】见 §0.1 表格。
- **补充（重要，容易误读）**：官方**另有**一句话描述 private 仓库的签名后端——"**Private repositories** that generate artifact attestations use GitHub's Sigstore instance. GitHub's Sigstore instance uses the same codebase as the Sigstore Public Good Instance, but it **does not have a transparency log** and only federates with GitHub Actions."（[Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)）。这句说的是**"当你在 GHEC private 仓库上用的时候"的内部机制**，**不是**"private 仓库可以用"。两句要一起读，否则会得出相反结论。
- **另一个坑**：`actions/attest-build-provenance` 从 v4 起**只是 `actions/attest` 的 wrapper**。官方 README 原文："As of version 4, `actions/attest-build-provenance` is simply a wrapper on top of `actions/attest`… new implementations should use `actions/attest` instead." 官方文档现在给的也是 `actions/attest@v4`。**如果你以后能用，请用 `actions/attest`。**
- 权限三处官方说法**互相不一致**（都列出来，别只抄一处）：
  - 官方 how-to：`id-token: write` + `contents: read` + `attestations: write`
  - `actions/attest` README：`id-token: write` + `attestations: write` + `artifact-metadata: write`
  - `attest-build-provenance` v3.2.0 README：同上三者，但 `artifact-metadata` 是**可选**的（"If this permission is not included, the action will continue without creating the record."）
  - **没有任何官方来源要求 `contents: write`。**
- **替代做法**：见 §4.6。

### 4.2 ⚠️ 签名 tag（signed tag）——没有官方推荐做法

- **能显示/验证**：GitHub 支持 GPG / SSH / S/MIME 签名。【官方原文】"If a commit or tag has a GPG, SSH, or S/MIME signature that is cryptographically verifiable, GitHub marks the commit or tag 'Verified' or 'Partially verified.'" tag 的徽章在 repo → **Releases** → **Tags** 里。【官方链接】[About commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
- **Vigilant mode**：可选开关，开启后你**所有**提交与 tag 都会被打上 Verified / Partially verified / Unverified 三态之一。路径：Settings → SSH and GPG keys → "Vigilant mode" → "Flag unsigned commits as unverified"。[官方链接](https://docs.github.com/en/authentication/managing-commit-signature-verification/displaying-verification-statuses-for-all-of-your-commits)
- **"Vulnerable" 徽章：查无此物（UNCONFIRMED）**。官方只记录 Verified / Partially verified / Unverified 三态。如果你见过 "vulnerable"，很可能是把 "Unverified" 记混了。
- **在 Actions 里签 tag：`没有官方推荐做法`。** 明确指出：
  - 官方只讲**本地**签名：`git tag -s MYTAG`（[Signing tags](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-tags)）
  - 官方 `actions/checkout` README 只演示了 git 身份配置（`git config user.name "github-actions[bot]"` / `git config user.email "41898282+github-actions[bot]@users.noreply.github.com"`）后 `git push`，**完全没提签名**
  - `actions` 组织里**没有**官方签名 action；`gh` **没有** tag 签名命令
  - → **任何 `git tag -s` + GPG 私钥 secret 的 workflow 都是社区实践，不是 GitHub 推荐做法。** 本方案**不包含**它。
- **替代做法**：见 §4.6。

### 4.3 ✅ `npx skills add cgartlab/attention` —— **private 仓库反而可用**

这是本次调研里最反直觉的一条。

【官方原文】`vercel-labs/skills` README 有一整节 **"Private Repositories"**：

> "Use the same command for public and private repositories. The CLI uses the authentication already configured for the repository URL."
>
> "For GitHub HTTPS and shorthand sources, `skills` first uses normal Git credentials. If that fails and GitHub CLI is authenticated, it tries `gh repo clone`, followed by SSH. It does not execute `gh auth token` or copy the stored GitHub CLI credential into the Node.js process."
>
> "`GITHUB_TOKEN` or `GH_TOKEN` can be set explicitly for GitHub API access, including **private repository downloads** and update checks."

—— [vercel-labs/skills README](https://raw.githubusercontent.com/vercel-labs/skills/main/README.md)

**所以**：`npx skills add cgartlab/attention` 在 private 仓库上**可用**——前提是**消费方**（跑这条命令的人）已经配置好了 git credential helper、`gh auth login` 或 SSH key，并且**对该私有仓库有读权限**。

**README 该怎么写才诚实**（可直接抄的措辞）：

```markdown
## 安装

> 本仓库当前为 **private**。安装前请确保你已通过 `gh auth login`、SSH key
> 或 git credential helper 之一获得本仓库的读权限。

npx skills add cgartlab/attention
```

**同时要注意**：`skills` CLI 的遥测说明明确区分了可见性——"GitHub repository and skill identifiers are sent only for repositories that GitHub **positively confirms are public**."（同 README）。private 仓库不会被上报，这对隐私是好事。

### 4.4 ❌ skills.sh 徽章在 private 仓库上无效

- **结论**：**private 仓库不会被 skills.sh 收录**，徽章会是死的 / 空白的。
- **依据等级**：**【推断】**。skills.sh 是一个公开目录站（[skills.sh](https://skills.sh)），其收录依赖对公开仓库的抓取；private 仓库无法被匿名抓取。我在 `vercel-labs/skills` README 里找到了"遥测只上报已确认 public 的仓库"这条**间接**证据，但**没有**找到官方明确写"private 仓库不会被 skills.sh 索引"的句子。
- **诚实建议**：
  1. **把徽章从 README 拿掉**，或者
  2. 改成明确标注状态的形式，例如"本技能为私有仓库，暂未发布到 skills.sh 目录"，或者
  3. 先用 §4.4 的措辞保留安装命令，但**不要**保留一个指向 skills.sh 且必然 404 的徽章图片。
- 现状提醒：`CHANGELOG.md` 的 `[Unreleased]` 里写着"README 增加 `npx skills add cgartlab/attention` 安装路径与 **skills.sh / Agent Skills 兼容徽章**"。**在 private 前提下，skills.sh 徽章这条需要复核。**

### 4.5 ⚠️ 社区标准文件：哪些真有价值，哪些是形式主义

**先说一个 private 仓库的通用事实**：【官方原文】"GitHub will use and display default files for any repository owned by the account, **regardless of the destination repository's visibility**"——默认社区健康文件对 private 仓库也生效。但**社区健康档案检查表（community profile checklist）本身只对 public 仓库展示**（官方页面标题即 "About community profiles for **public repositories**"）。→ **private 仓库做这些文件，不会被任何"评分"看见**，只对真正读代码的协作者有用。这应该改变你的取舍标准。

【官方原文】支持的默认社区健康文件类型：`CODE_OF_CONDUCT.md`、`CONTRIBUTING.md`、Discussion category forms、`FUNDING.yml`、Issue/PR 模板与 `config.yml`、`SECURITY.md`、`SUPPORT.md`（[Creating a default community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)）。**注意：LICENSE 不能作为默认文件**——"You cannot create a default license file."

| 文件 | 必要性判断 | 理由 |
|---|---|---|
| `SECURITY.md` | ✅ **已有，做得好** | 已正确指向 private vulnerability reporting 并给出了安全边界（"只读采集"、"本地无网络探测"、"永远不做"清单）。**比我原本会建议的写得更好**——它把"什么算漏洞"定义清楚了。**唯一缺口**：需要去 Settings 真的把 private vulnerability reporting 打开（§3 #5）。 |
| `CONTRIBUTING.md` | ✅ **已有，做得好** | 已包含"提交前必须绿的两件事"、conventional commits、成对改脚本、契约四处同步、PR 检查清单。 |
| `.github/PULL_REQUEST_TEMPLATE.md` | ✅ **建议加** | 把 `CONTRIBUTING.md` 的 PR 检查清单变成可勾选项。这是本仓库**唯一**真正能降摩擦的模板，因为它的清单很具体（红→绿数字、断言只增不减、parity 绿）。 |
| `.github/CODEOWNERS` | ⚠️ **可选，收益低** | 【官方原文】"The people you choose as code owners must have write permissions for the repository." 个人仓库里 code owner 就是你自己；**只有**当分支 ruleset 勾了 `Require review from Code Owners` 时才有实质作用，而单人评审会把你自己卡住（你不能批准自己的 PR）。**建议：不加，或者在 ruleset 里不要开 code owner review。** 官方同时提醒：要真正保护 CODEOWNERS 自身，最安全的是放在 `.github/` 并把它自己也列为 owner（`/.github/CODEOWNERS @owner`）。 |
| `SUPPORT.md` | ❌ **形式主义** | 内容只会是"提 issue"。个人项目没有支持渠道分层要讲。 |
| `CODE_OF_CONDUCT.md` | ❌ **形式主义** | 单人/小规模 private 仓库不需要社区行为准则。**除非**你计划未来公开并接受外部贡献。 |
| `.github/ISSUE_TEMPLATE/*` | ⚠️ **可选** | private 仓库的 issue 主要给你自己用。如果加，一个 `bug_report.yml` 足够，且**不要**给模板设 label——【官方原文】"If an issue template sets a label, that label must be created in your `.github` repository **and any repositories where the template will be used**."（label 不存在会导致模板报错） |
| `.github/dependabot.yml` | ⚠️ **只写 `github-actions` 一个生态** | 本仓库没有 `package.json` / `requirements.txt` / `go.mod` / `Cargo.toml`——**版本更新的生态一个都不适用**。唯一有意义的是 `github-actions`，用来把 `actions/checkout@v4`、`googleapis/release-please-action@v4` 这类 pin 住并自动升版。 |
| `FUNDING.yml` | ❌ **不适用** | 无赞助需求。 |
| `.github/workflows/codeql.yml` 等安全扫描 | ❌ **对本仓库收益为负** | 仓库主体是 Markdown 与 shell 脚本；code scanning 支持的语言里没有这两者。**但注意**：Dependabot 的**运行**在标准 runner 上是免费的（【官方原文】"The use of standard GitHub-hosted runners is free: In public repositories / For GitHub Pages / **For Dependabot**" —— [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)），所以加 `dependabot.yml` 不花 Actions 额度。 |

`.github/dependabot.yml` 最小可用内容：

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "chore"
```

> ⚠️ **未确认**：本仓库的提交规约要求 conventional commits，而 Dependabot 的 `commit-message.prefix` 具体是否产出合规消息（`chore(deps): ...` 形态）、以及它是否与 release-please 的 `deps` releasable unit 配合良好，**我没有在官方文档里逐字确认**。列入 §6。

### 4.6 那"商业级可追溯性"在 private + Free 上还剩什么？

按**实际可用**排序（从强到弱）：

| 手段 | 可用性 | 说明 |
|---|---|---|
| **ruleset 保护 `v*`** | ⚠️ 需 Pro | 这是最强的一条。目标：`deletion` + `non_fast_forward` + `update` 三条规则全开（§3.1）。**没有它，已发布的 tag 理论上可被移动** |
| **Immutable releases** | ❓ 未确认（可能 Free 可用） | 若可用，它**同时**给你"tag 锁定 + 资产锁定 + release attestation"。**性价比最高**，请第一时间去 Settings 确认有没有这个开关 |
| **release attestation**（immutable releases 自带） | ❓ 随上一行 | 用 `gh release verify` / `gh release verify-asset` 验证 |
| **zip + sha256 校验文件挂在 Release 上** | ✅ 现在就能做 | §2.6。不是签名，但给了"内容未变"的可比对标尺 |
| **PAT 而非 `GITHUB_TOKEN` 驱动 release** | ✅ 现在就能做 | 让 release PR 上的 CI 真正跑起来（§2.6） |
| **`bootstrap-sha` + 完整 `evals/` 门禁** | ✅ 现在就能做 | 本仓库真正的质量凭据其实是那 553 checks |
| **artifact attestations** | ❌ 需 GHEC | 见 §4.1 |
| **GPG 签名 tag** | ⚠️ 无官方做法 | 社区实践，且要引入 GPG 私钥 secret，**不建议**在 private 个人仓库上承担这个复杂度 |

---

## 5. 风险与坑

### 5.1 ⚠️⚠️ release-please 与现有 `[Unreleased]` 段：**不会合并，会长期共存**

**机制（源码级）**：【源码行】[`src/updaters/changelog.ts`](https://raw.githubusercontent.com/googleapis/release-please/main/src/updaters/changelog.ts)

```ts
const DEFAULT_VERSION_HEADER_REGEX = '\n###? v?[0-9[]';
...
const lastEntryIndex = content.search(this.versionHeaderRegex);
if (lastEntryIndex === -1) { ... } else {
  const before = content.slice(0, lastEntryIndex);
  const after = content.slice(lastEntryIndex);
  return `${before}\n${this.changelogEntry}\n${after}`.trim() + '\n';
}
```

`## [Unreleased]` 完全命中 `\n##` + 空格 + `[`。`before` 是"到 `## [Unreleased]` 前一个换行为止"的正文，于是新版本段被插在 **`[Unreleased]` 上方**。

**实际后果**（按本仓库 `CHANGELOG.md` 现状推演）：

```
# Changelog
<前言与版本策略说明>

## [0.2.0](...) (2026-10-xx)     ← release-please 插入的新段
### Features
- ...

## [Unreleased]                  ← 原样保留，永不排空
### Added
- （那 42 条，永远留在这里，且与新版本段内容重复）
...

## [0.1.0] - 2026-09-29
```

**三个具体风险**：
1. **42 条 `[Unreleased]` 条目永远不会被"发布"**——它们既不会被搬进新版本段，也不会被清空。而 release-please 会**另外**从 commit 生成同批内容。**同一件事在 CHANGELOG 里出现两次。**
2. **`[Unreleased]` 位置倒挂**：新版本段在其上方，破坏了 Keep a Changelog 的"Unreleased 在顶部"惯例，且随时间推移，`[Unreleased]` 会永久钉在中间。
3. **`unreleased` 与 `[0.1.0]` 的相对顺序也不对**（新段 → Unreleased → 0.1.0），任何按顺序解析 CHANGELOG 的工具都会困惑。

**处理建议（三选一，必须选）**：

| 方案 | 做法 | 代价 |
|---|---|---|
| **A. 先清场再上线（推荐）** | 上线 release-please **之前**，把 `[Unreleased]` 的 42 条**手工归并**进 `## [0.1.0] - 2026-09-29`（或新开一个 `## [0.1.1] - <日期>`），然后**删掉 `## [Unreleased]` 整段** | 一次性体力活；但那 42 条本来也"应该"是 0.1.x 的一部分 |
| **B. 保留 `[Unreleased]` 但约定它只放"未分类条目"** | 接受它永远在最下面；每次发版后手工清空 | 依赖纪律，且与 release-please 的自动生成重复 |
| **C. 让 release-please 不碰 CHANGELOG** | 设 `"skip-changelog": true` | **等于放弃 release-please 一半的价值**，只拿版本号自动化。不推荐 |

**注意**：`bootstrap-sha` **不能**解决这个问题。它限制的是"收集哪些 commit"，而插入位置由上面的正则决定——两件事互不相干。

### 5.2 ⚠️ `scripts/release_preflight.*` 的 `[Unreleased]` 检查会变成假失败

`release_preflight.ps1:102`：

```powershell
Add-Check 'CHANGELOG [Unreleased] 就绪' ($hasUn -and $count -gt 0) $(...)
```

它**要求 `CHANGELOG.md` 里存在 `[Unreleased]` 段且至少有 1 条条目**。

- 若你采用 §5.1 的**方案 A**（删掉 `[Unreleased]`）→ `-not $hasUn` → **这条永远失败**，`release_preflight` 恒退出 1。
- 若你采用**方案 B**（保留但发版后清空）→ 清空后这条也失败。

**所以**：这套 release-please 方案与 `release_preflight` **在设计假设上不兼容**——preflight 假设"CHANGELOG 由人维护 `[Unreleased]`"，release-please 假设"CHANGELOG 由 commit 生成"。

**可行出路（需要改仓库，超出本次"只新建一个文件"的授权，交你决定）**：
1. 给 `release_preflight` 加一个 `--release-please` 模式，跳过 `[Unreleased]` 检查改为校验 manifest 与 `SKILL.md` 一致；或
2. CI 不跑完整 preflight，只跑 `version_consistency_audit`（§2.5 就是这么设计的）；把 preflight 降级为**人类本地**在开 PR 前跑的工具；或
3. 放弃 release-please，继续"人工维护 `[Unreleased]` + 人工切版本 + `release_preflight` 把关"。

**我倾向 2 或 1**：`release_preflight` 的价值在"工作区干净 + 版本一致 + 测试绿"，而那 42 条 `[Unreleased]` 的检查是 release-please 世界里最不该 gate 的一条。

### 5.3 ⚠️ tag 保护与 release-please 的交互

| 交互 | 会不会出问题 | 说明 |
|---|---|---|
| release-please 推 tag vs ruleset `creation` | ⚠️ 要小心 | 若 ruleset 勾了 **Restrict creations**（"only users with bypass permissions can create branches or tags whose name matches"），则**只有 bypass 名单里的 actor 才能建 tag**。release-please 用的是你的 PAT（以**你的用户身份**），所以只要你不在 bypass 名单外就没问题。**但如果你用 `GITHUB_TOKEN`，actor 是 `github-actions[bot]`——它不在任何 bypass 名单里，建 tag 会被拒。** 建议：**不要**开 `creation` 规则，只开 `deletion` + `non_fast_forward` + `update`。 |
| release-please 推 tag vs ruleset `update` | ✅ 不冲突 | release-please 每个版本推**新** tag（`v0.2.0` 是新 ref），不"更新"已有 tag。`update` 规则只在你想移动 `v0.1.0` 时生效。 |
| release-please 的 release PR 分支 vs 分支 ruleset | ⚠️ 可能被卡 | 若 main 的 ruleset 要求 PR + 必需状态检查，release-please 的分支 `release-please--branches--main--components--attention` 会正常走 PR。**但它的 PR 是 release-please 的 token 发的**，所以要么用 PAT（能触发 CI），要么该 PR 永远拿不到状态检查 → **永远合不了**。这是**必须用 PAT** 的第二个理由。 |
| immutable releases + release-please 非 draft 发布 | ❌ **会坏** | release-please 默认**直接发布**（`draft: false`），Release 一发布即不可变，之后 `gh release upload` 加资产会被拒。→ 必须走 §2.6 的变体（`draft: true` + `force-tag-creation: true` + 手动 publish）。 |
| immutable releases + "删 release 再重发同一 tag" | ❌ 永久不可行 | 【官方原文】"If you delete the immutable release, you can delete the tag, but **you cannot reuse the same tag name**." 发错版本号 = 该 tag 名永久报废。**这是引入 immutable releases 最大的操作风险**，请先确认你的发版流程不会需要"重发同名版本"。 |
| `[Unreleased]` 段的存在 vs tag 保护 | ✅ 无关 | 两件事互不影响 |

### 5.4 ⚠️ CC-BY-NC-SA-4.0 对"商业产品级"表述的影响（**这条必须谨慎**）

本仓库 `LICENSE` 是 **CC-BY-NC-SA-4.0**，`SKILL.md` frontmatter 的 `license:` 字段也是它。三个条款各自有后果：

1. **NC（NonCommercial，非商业性使用）**——**"商业产品级"这个词不能用来描述这个许可证下的分发**。你把流程做得再"商业级"，**许可本身禁止商业使用**。措辞上必须把两件事分开：
   - ✅ 可以说："本仓库的 **release 工程实践**参照商业产品的标准（版本可追溯、tag 不可变、CI 门禁、变更记录规范化）。"
   - ❌ 不能说："本仓库是商业产品级项目" / "可用于商业产品"——这会与 NC 条款冲突，且给对方造成误导。
2. **SA（ShareAlike，相同方式共享）**——**衍生作品必须用同样的许可证**。这对**发布流水线**有实际影响：如果 `references/` 或 `assets/` 里嵌了别人的内容，整包的再许可会被 SA 传染。本仓库目前是自有内容，问题不大；但**一旦引入第三方内容就要重新审视整个 LICENSE**。
3. **CC 许可证不适合软件**——这是 Creative Commons 官方自己的立场（[Creative Commons 关于"CC 是否适用于软件"的 FAQ](https://creativecommons.org/faq/#can-i-apply-a-creative-commons-license-to-software)），因为 CC 许可证不讲源码/目标码之分、也不处理专利。本仓库同时分发**可执行 shell 脚本**（`scripts/*.sh|ps1`、`evals/*`），而这些脚本恰恰是 CC 覆盖得最别扭的部分。
   - **诚实建议**：这是一个**独立于 release 流水线**的许可证问题，值得单独决策。可选做法：整体改用 `MIT` / `Apache-2.0`，或**双许可**（文档 CC-BY-NC-SA-4.0 + 代码 MIT）。**但改许可证是重大变更，我没有权限也不应该替你决定**——这里只是把它标出来。
4. **对流水线的直接后果**：§2.6 打的 zip 里**必须包含 `LICENSE`**（我的 `git archive` 命令已包含）。CC-BY-NC-SA 要求分发时保留许可证全文与署名，漏掉 LICENSE 的 zip 是不合规的。
5. **`package-name: "attention"` 与许可证无关**，但如果将来发布到任何**包管理器**（npm 等），NC 条款会让它无法进入许多企业镜像源——这是选 CC 时就已承担的代价，不是流水线能补救的。

### 5.5 其他次级风险

| 风险 | 说明 |
|---|---|
| **release-please 可能长期不产出 release PR** | 【官方原文】"A releasable unit is a commit to the branch with one of the following prefixes: 'feat', 'fix', and 'deps'. (A 'chore' or 'build' commit is not a releasable unit.)"（[release-please README](https://raw.githubusercontent.com/googleapis/release-please/main/README.md)）。本仓库历史里 `docs` / `chore` / `refactor` 占比高 → **可能连续多周不出 release PR**。这不是 bug，是设计。别把它当成"CI 坏了"。 |
| **首次上线时 release-please 找不到上一个版本** | 【源码行】`manifest.ts` 会打 `Expected 1 releases, only found 0` 并 fallback 到 tag 查找；因为仓库**无 tag**，最终会走全历史。→ 这就是 §2.4 必须设 `bootstrap-sha` 的原因。 |
| **release-please 的 `autorelease: pending` 标签卡死** | 【官方原文】"Due to GitHub API failures, it's possible that the tag was not removed correctly upon a previous release and Release Please thinks that the previous release is still pending." → 现象是"再也不出新 release PR"。修法：手工摘掉该 PR 上的 `autorelease: pending` 标签再重跑。（[README](https://raw.githubusercontent.com/googleapis/release-please/main/README.md)） |
| **必须用 squash merge** | 【官方原文】"We **highly** recommend that you use squash-merges when merging pull requests." 理由之一是 release-please 的 `BEGIN_COMMIT_OVERRIDE` 在普通 merge 下不工作。→ 在 repo Settings 里把 merge 方式收敛为 **Squash only**。 |
| **Windows runner 更贵** | 【官方原文】计费表：`Linux 2-core (x64)` = $0.006/分钟，`Windows 2-core (x64)` = $0.010/分钟（[Actions runner pricing](https://raw.githubusercontent.com/github/docs/main/content/billing/reference/actions-runner-pricing.md)）。且"GitHub rounds the minutes and partial minutes each job uses **up to the nearest whole minute**"。Windows job 的每一分钟都是 Linux 的 1.67 倍。**别把 Windows 矩阵铺得太宽。** |
| **Free 计划额度** | 【官方原文】private 仓库：Free 个人 = **2,000 分钟/月 + 500 MB artifact 存储**（Pro 3,000 / 1 GB；Team 3,000 / 2 GB；GHEC 50,000 / 50 GB）—— [actions-included-quotas](https://raw.githubusercontent.com/github/docs/main/data/reusables/billing/actions-included-quotas.md)。**注意**："If your account does not have a valid payment method on file, **usage is blocked once you use up your quota**."（[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)）→ 额度耗尽后 CI **直接停摆**，不是"超支收费"。 |
| **矩阵会吃掉额度** | 4 个矩阵组合 × 每次全量 `run_evals`（553 checks，本机实测口径）→ 每次 push 的成本是单 OS 的 4 倍。**如果 Free 额度紧张，建议先只跑 2 个组合**（`ubuntu/bash` + `windows/pwsh`），确认成本后再加。 |
| **`evals/run_evals.sh` 在 Windows 上需要 python3** | `AGENTS.md` 写明"bash 侧建议有 python3 以做严格 JSON 校验"。GitHub 的 `windows-latest` 镜像里有 Python，但 **`python3` 这个命令名在 Windows 上不一定存在**（通常是 `python`）。→ §2.5 里 `windows-latest` + `bash` 这一格**必须实测**，失败就把它从矩阵里去掉，改成只在 ubuntu 上跑 bash。列入 §6。 |
| **`pwsh` 是否预装在 `ubuntu-latest` 上** | 【推断】GitHub 的 Ubuntu runner 镜像历来含 PowerShell 7，但**我没有在官方文档里逐字确认**。→ §2.5 里 `ubuntu-latest` + `pwsh` 这一格**必须实测**。若不预装，去掉这一格，矩阵退化为 2×2 → 2 格（ubuntu/bash + windows/pwsh），仍然满足"两套 shell 都在 CI 里真跑过"这条底线。 |
| **`evals/results/` 入库** | `AGENTS.md` 说结果写 `evals/results/` 并入库作为验证证据。CI 里跑会产生**未提交的改动** → 后续任何"工作区干净"检查（含 `release_preflight`）会失败。**建议**：CI 用 `--no-write`（`release_preflight.sh:100` 用了 `evals/run_evals.sh --fixtures-dir "$tmp" --no-write`），或把 `evals/results/` 加进 `.gitignore`。**注意：`.gitignore` 是被并发修改的文件之一，本调研不碰它。** |

---

## 6. 我的推断清单（**没有**用官方文档确认的点）

> 诚实第一。以下每一条都**不能**当事实用。按"上线前必须先验证"排序。

| # | 推断 | 为什么无法确认 | 怎么验证 |
|---|---|---|---|
| 1 | **`v*` tag ruleset 的 conditions 该写 `v*` 还是 `refs/tags/v*`** | 官方 REST 参考只给了 branch 的示例（`refs/heads/main`、`refs/heads/dev*`），**没有给 tag 示例**；而 UI 文档说的是"pattern"（fnmatch） | 先在 UI 建一次，再 `gh api /repos/cgartlab/attention/rulesets` 回读真实结构 |
| 2 | **Immutable releases 在 Free + private 上是否可用** | 文档页 frontmatter 只有 `versions: feature: immutable-releases`（feature flag），**没有** `product:` 门控；`data/reusables/gated-features/immutable-releases.md` **404**。查不到 gating 不等于没有 gating | 去 repo → Settings → 找 "Releases / Enable release immutability" 开关 |
| 3 | **不开 immutable releases 时，已发布 Release 的 tag 默认是否可移动** | 官方只从正面定义了 immutable 的保护；**没有**找到"默认受保护"或"默认不受保护"的明文 | 在测试仓库上试 `git push --force origin v0.0.1` |
| 4 | **`pwsh` 是否预装在 `ubuntu-latest`** | 未在官方 runner 镜像文档中逐字确认 | 让 CI 跑一次 |
| 5 | **`python3` 在 `windows-latest` 上是否可解析** | 同上 | 让 CI 跑一次 |
| 6 | **`gh release edit <tag> --draft=false` 的确切写法** | `gh release edit` 存在且带 `--draft` 布尔旗标是确定的，但**"从草稿发布"这个具体调用形态我没逐字确认** | 本地 `gh release edit --help` |
| 7 | **PAT 的最小 scope 清单** | release-please-action README 只说"创建 PAT"，**没有列 scope**。permissions 一节讲的是 workflow 里的 `permissions:` 块，不是 PAT 的 scope | 用 fine-grained PAT 试最小集：`Contents: RW` + `Pull requests: RW` + `Issues: RW`（这是我从上面那个 workflow permissions 块**推**出来的，不是文档说的） |
| 8 | **private 仓库上 release-please-action 是否有额外限制** | 官方文档从未按可见性区分；**找不到**限制说明 | 小仓库实测 |
| 9 | **`x-release-please-date` 注解可用** | 源码 `INLINE_UPDATE_REGEX` 里有 `date|version-date`，但官方 customizing 文档的 inline 清单**只有** `version`/`major`/`minor`/`patch` —— 文档与源码不一致 | 不要用；若要用，先 `--dry-run` |
| 10 | **`draft: true` + `force-tag-creation: true` + `extra-files` 三者组合的实际行为** | 每个字段各有官方定义，**组合行为**无文档 | `release-please release-pr --dry-run` |
| 11 | **private 仓库的 release asset 能否被 `npx skills add <url>` 拉取** | skills README 说 `GITHUB_TOKEN`/`GH_TOKEN` 可用于"private repository downloads"，但**release asset 的下载走的是另一条路**（API `Accept: application/octet-stream`，需要认证）；我**没有**确认它对 release asset URL 也成立 | 实测；**更稳的做法是让用户用 `npx skills add cgartlab/attention` 的仓库简写形式**，那条路径 README 明确支持 |
| 12 | **skills.sh 不索引 private 仓库** | 只有间接证据（遥测说明区分 public/private）；**没有**明确句子 | 打开 `https://skills.sh/cgartlab/attention` 看是否 404 |
| 13 | **Dependabot 的 `commit-message.prefix` 是否产出合规的 conventional commit** | 未逐字确认 | 加 `dependabot.yml` 后看它开的 PR 标题 |
| 14 | **`gh attestation verify` 在 private 仓库上需要认证** | 官方 REST 说明 attestations 结果按调用者权限过滤（强证据），但没有一句"private 需要认证" | 本项**对本仓库不适用**（Free 计划根本不能用 attestations），仅记录 |
| 15 | **`[Unreleased]` 正则命中的推演** | 这是我从 `DEFAULT_VERSION_HEADER_REGEX = '\n###? v?[0-9[]'` + `'s'` flag **逐字符推**出来的，**没有**在官方文档或测试里看到"`[Unreleased]` 会被当作版本段"的明证 | `release-please release-pr --dry-run --debug`，检查它把新段插在哪 |

---

## 附录 A：关键官方原文摘录（可直接引用）

| 主题 | 原文 | URL |
|---|---|---|
| rulesets 的 plan 门控 | "Rulesets are available in public repositories with GitHub Free and GitHub Free for organizations, and in public and private repositories with GitHub Pro, GitHub Team, and GitHub Enterprise Cloud." | [link](https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/repo-rules.md) |
| 经典分支保护的 plan 门控 | "Protected branches are available in public repositories with GitHub Free… also available in public and private repositories with GitHub Pro, GitHub Team, GitHub Enterprise Cloud, and GitHub Enterprise Server." | [link](https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/protected-branches.md) |
| attestations 的 plan 门控 | "If you are on a GitHub Free, GitHub Pro, or GitHub Team plan, artifact attestations are only available for public repositories. To use artifact attestations in private or internal repositories, you must be on a GitHub Enterprise Cloud plan." | [link](https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/attestations.md) |
| attestations 的 private 后端 | "Private repositories that generate artifact attestations use GitHub's Sigstore instance. GitHub's Sigstore instance uses the same codebase as the Sigstore Public Good Instance, but it does not have a transparency log and only federates with GitHub Actions." | [link](https://raw.githubusercontent.com/github/docs/main/content/actions/concepts/security/artifact-attestations.md) |
| immutable releases 保护什么 | "Git tags cannot be moved: Once an immutable release is published, its associated Git tag is locked to a specific commit, cannot be changed, and cannot be deleted while the release exists. If you delete the immutable release, you can delete the tag, but you cannot reuse the same tag name." | [link](https://raw.githubusercontent.com/github/docs/main/content/code-security/concepts/supply-chain-security/immutable-releases.md) |
| immutable releases 最佳实践 | "1. Create the release as a draft. 1. Attach all associated assets to the draft release. 1. Publish the draft release." | 同上 |
| 默认不能开 PR | "By default, when you create a new repository in your personal account, workflows are not allowed to create or approve pull requests." | [link](https://raw.githubusercontent.com/github/docs/main/content/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository.md) |
| 默认 GITHUB_TOKEN 只读 | "By default, when you create a new repository in your personal account, `GITHUB_TOKEN` only has read access for the `contents` and `packages` scopes." | 同上 |
| GITHUB_TOKEN 造的 release 不触发 workflow | "When you use the repository's `GITHUB_TOKEN` to perform tasks, events triggered by the `GITHUB_TOKEN` will not create a new workflow run." | [release-please-action README](https://raw.githubusercontent.com/googleapis/release-please-action/main/README.md)（转引 GitHub 官方 docs） |
| release-please 需要的 workflow 权限 | "permissions: `contents: write` / `issues: write` / `pull-requests: write`" | 同上 |
| releasable unit | "A releasable unit is a commit to the branch with one of the following prefixes: 'feat', 'fix', and 'deps'. (A 'chore' or 'build' commit is not a releasable unit.)" | [release-please README](https://raw.githubusercontent.com/googleapis/release-please/main/README.md) |
| 用 squash merge | "We highly recommend that you use squash-merges when merging pull requests." | 同上 |
| extra-files 注解 | "To mark versions needing an update in those files, you will add annotations (usually in comments)." | [docs/customizing.md](https://raw.githubusercontent.com/googleapis/release-please/main/docs/customizing.md) |
| 强制 generic updater | "Default updaters are applied depending on the file extension. If you want to force the Generic updater, you must use type `\"generic\"`." | 同上 |
| YAML updater 会毁掉格式 | "Note that used parser does reformat the document and removes all comments… If you want to retain formatting, use generic updater with comment hints." | [src/updaters/generic-yaml.ts](https://raw.githubusercontent.com/googleapis/release-please/main/src/updaters/generic-yaml.ts) |
| manifest 初始化 | "The simplest way to tell release-please the current version for a package it has never released before is to manually add an entry into `.release-please-manifest.json`." | [docs/manifest-releaser.md](https://raw.githubusercontent.com/googleapis/release-please/main/docs/manifest-releaser.md) |
| bootstrap-sha | "you can add a top level `\"bootstrap-sha\": <full sha value>` key/value entry to the config which will cause release-please to stop there for collecting changelog commits (so choose one commit earlier than the first commit you want to include)" | 同上 |
| tag 形态不匹配的修法 | "To fix this, component can be removed from tagName being searched using the `include-component-in-tag` property. Setting this to `false` will change the tagName to: `v<release-version>`" | 同上 |
| Release 资产上限 | "Up to 1000 release assets may be associated with a single release. Each file included in a release must be under 2 GiB." | [About releases](https://raw.githubusercontent.com/github/docs/main/content/repositories/releasing-projects-on-github/about-releases.md) |
| 签名 tag 的展示 | "If a commit or tag has a GPG, SSH, or S/MIME signature that is cryptographically verifiable, GitHub marks the commit or tag 'Verified' or 'Partially verified.'" | [docs](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification) |
| skills CLI 支持 private 仓库 | "Use the same command for public and private repositories. The CLI uses the authentication already configured for the repository URL." | [vercel-labs/skills README](https://raw.githubusercontent.com/vercel-labs/skills/main/README.md) |
| skills 下发的压缩包限制 | "They may point to a single valid `SKILL.md` file or a `.zip`, `.tar`, `.tar.gz`, or `.tgz` archive… Downloads are limited to 10 MiB, extracted content to 25 MiB, and archives to 1000 files by default." | 同上 |
| Actions 计费 | "For private repositories, each GitHub account receives a quota of free minutes, artifact storage, and cache storage… Any usage beyond the included amounts is billed to your account." | [GitHub Actions billing](https://raw.githubusercontent.com/github/docs/main/content/billing/concepts/product-billing/github-actions.md) |
| 额度耗尽即停摆 | "If your account does not have a valid payment method on file, usage is blocked once you use up your quota." | 同上 |
| 分钟取整 | "GitHub rounds the minutes and partial minutes each job uses up to the nearest whole minute." | [Actions runner pricing](https://raw.githubusercontent.com/github/docs/main/content/billing/reference/actions-runner-pricing.md) |
| 社区健康文件对 private 也生效 | "GitHub will use and display default files for any repository owned by the account, regardless of the destination repository's visibility" | [Creating a default community health file](https://raw.githubusercontent.com/github/docs/main/content/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file.md) |

---

## 附录 B：实际访问过的 URL（含打不开的）

### B.1 release-please（全部 HTTP 200）

| URL | 拿到什么 |
|---|---|
| `https://raw.githubusercontent.com/googleapis/release-please/main/docs/customizing.md` | release type 表、注解清单、`extra-files` 全部形态 |
| `https://raw.githubusercontent.com/googleapis/release-please/main/docs/manifest-releaser.md` | manifest 全部顶层/包级选项、bootstrap 流程、tag 形态排错 |
| `https://raw.githubusercontent.com/googleapis/release-please/main/docs/troubleshooting.md` | `--dry-run`/`--debug` 调试法、`autorelease:*` 卡死修法 |
| `https://raw.githubusercontent.com/googleapis/release-please/main/README.md` | releasable unit、squash merge 建议、release type 表 |
| `https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json` | 配置 JSON Schema（字段名权威） |
| `.../main/src/strategies/base.ts` | `extraFileUpdates()` 的后缀分派链 → `.md` 走 `Generic` |
| `.../main/src/strategies/simple.ts` | `versionFile ?? 'version.txt'`、`createIfMissing: false` |
| `.../main/src/strategies/go.ts` | `versionFile ?? ''`，为空则不生成版本文件更新 |
| `.../main/src/updaters/generic.ts` | 注解正则、`VERSION_REGEX`、块/行内替换逻辑 |
| `.../main/src/updaters/generic-yaml.ts` | "会删注释并重排版"的警告 |
| `.../main/src/updaters/changelog.ts` | `DEFAULT_VERSION_HEADER_REGEX` → `[Unreleased]` 命中 |
| `.../main/src/updaters/default.ts` | `updateContent` 返回 `version + '\n'`（整个覆盖） |
| `.../main/src/github.ts` | `buildChangeSet()` 的 `createIfMissing: false` → 缺文件只 warn |
| `.../main/src/manifest.ts` | 配置解析、`initialReleaseVersion` 走 `base.ts` → 1.0.0 |
| `.../main/test/updaters/generic.ts` | Generic updater 测试入口 |
| `.../main/test/updaters/fixtures/README.md` | 官方 fixture 里的 `.md` 用法 |
| `.../main/test/updaters/fixtures/versions.tf` | 注解式替换的 fixture 样例 |
| `https://raw.githubusercontent.com/googleapis/release-please-action/main/README.md` | 权限块、PAT 必要性、`gh release upload` 官方范式、outputs |

**404（不存在）**：`src/updaters/factory.ts`、`src/updaters/index.ts`

### B.2 GitHub 官方文档

| URL | 结果 |
|---|---|
| `https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/repo-rules.md` | ✅ rulesets 的 plan 门控（**关键**） |
| `.../data/reusables/gated-features/protected-branches.md` | ✅ 经典分支保护的 plan 门控（**关键**） |
| `.../data/reusables/gated-features/attestations.md` | ✅ attestations 的 plan 门控（**关键**） |
| `.../data/reusables/billing/actions-included-quotas.md` | ✅ 各计划免费额度表 |
| `.../data/reusables/billing/actions-standard-runner-prices.md` | ✅ 各 OS 每分钟费率 |
| `.../data/reusables/actions/actions-billing.md` | ✅ 计费总述 |
| `.../data/variables/releases.yml` | ✅ `release_asset_limit: '1000'` |
| `.../content/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository.md` | ✅ "Allow GitHub Actions to create and approve pull requests"、默认 token 权限 |
| `.../content/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets.md` | ✅ rulesets 概念、fnmatch、enforcement |
| `.../content/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets.md` | ✅ Restrict creations/updates/deletions、Block force pushes |
| `.../content/code-security/concepts/supply-chain-security/immutable-releases.md` | ✅ immutable releases 保护范围 + 最佳实践 |
| `.../content/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes.md` | ✅ 启用路径："Enable release immutability" |
| `.../content/actions/concepts/security/artifact-attestations.md` | ✅ private 用 GitHub Sigstore / 无 transparency log |
| `.../content/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations.md` | ✅ `actions/attest@v4` + 权限块 + `subject-path` |
| `.../content/actions/concepts/billing-and-usage.md` | ✅ 计费/额度/复用 workflow 计费归属 |
| `.../content/billing/concepts/product-billing/github-actions.md` | ✅ 计费细则、Dependabot 免费、超额度停摆 |
| `.../content/billing/reference/actions-runner-pricing.md` | ✅ 费率表、分钟取整 |
| `.../content/repositories/releasing-projects-on-github/about-releases.md` | ✅ 资产上限、release 与 tag 的关系 |
| `.../content/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners.md` | ✅ CODEOWNERS 位置/语法/3MB 限制 |
| `.../content/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file.md` | ✅ 支持的社区健康文件类型、LICENSE 不能做默认 |
| `https://docs.github.com/api/article/body?pathname=/en/rest/repos/rules` | ✅ **REST rulesets 完整请求体 schema**（官方正文端点，绕开 HTML 截断） |
| `https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository` | ⚠️ 只拿到标题（正文被导航截断，未改用正文端点） |
| `https://docs.github.com/en/actions/tutorials/authenticate-with-github_token` | ⚠️ 只拿到标题（同上） |
| `https://raw.githubusercontent.com/github/docs/main/content/actions/security-for-github-actions/security-guides/automatic-token-authentication.md` | ❌ **404**（文档已重构，路径失效） |
| `https://raw.githubusercontent.com/github/docs/main/content/rest/repos/rules.md` | ⚠️ 200 但正文是自动生成占位（`<!-- Content after this section is automatically generated -->`），改用正文端点 |
| `https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/immutable-releases.md` | ❌ **404**（→ immutable releases 的 plan 门控无法确认） |
| `https://raw.githubusercontent.com/github/docs/main/data/reusables/repositories/rulesets-about-enforcement-statuses.md` | ✅ Active / Evaluate / Disabled |
| `https://api.github.com/repos/github/docs/contents/content/code-security/dependabot` | ❌ 404（放弃从 API 列目录） |
| `https://raw.githubusercontent.com/github/docs/main/content/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file.md` | ❌ **404**（→ `dependabot.yml` 我**没有**拿到官方字段级原文，见 §4.5 的未确认说明） |
| `https://raw.githubusercontent.com/github/docs/main/content/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot.md` | ❌ **404** |
| `https://api.github.com/repos/googleapis/release-please/contents/test/updaters/fixtures` | ✅ fixture 清单（用于定位 `.md` 样例） |
| `https://github.com/googleapis/release-please/blob/main/docs/customizing.md` | ⚠️ 只返回 `OK`（GitHub blob 页是 JS 渲染），改用 raw |

### B.3 Skills 生态

| URL | 结果 |
|---|---|
| `https://raw.githubusercontent.com/vercel-labs/skills/main/README.md` | ✅ **Private Repositories 整节**、下载/解压上限、遥测的可见性说明、`metadata.internal` |

### B.4 本会话**不可用**的工具

- **`web_search`**：两次调用均失败（第一次 HTTP 429 `rpm exhausted`，第二次 "DeepSeek returned no web_search_tool_result blocks"）。→ 本报告**没有**任何一条结论依赖搜索结果；也因此**没有**找到 GitHub Changelog 上关于 immutable releases GA 的公告帖，无法给出 GA 日期与版本号。
- **`docs.github.com` HTML 页面**：长页面会被导航截断。**可用的绕法**：`https://docs.github.com/api/article/body?pathname=<path>`（官方正文端点）或 `raw.githubusercontent.com/github/docs/main/content/...`（源 Markdown）。**这个绕法建议写进本仓库的调研规范**，能省很多次失败抓取。

---

## 附录 C：我对本仓库现状的两处观察（与本任务无关，但你可能想知道）

1. **`AGENTS.md` 引用了一个不存在的文件**：`AGENTS.md` 已更新为在自检一节指向 `pwsh -NoProfile -File scripts/release_preflight.ps1 --repo .` 并说"流程见 `docs/RELEASING.md`"，`CONTRIBUTING.md` 也说"发布前另跑 `scripts/release_preflight.ps1|sh`"。但**截至本次调研，`docs/RELEASING.md` 并不存在**（`docs/` 下只有 `DEVELOPMENT-PLAN.md`、`ecosystem-survey.md`、`QUALITY-AUDIT.md`、`VALIDATION.md` 与两个子目录）。→ 这是一个**悬挂引用**。我没有创建它（本任务只允许新建 `docs/research/github-release-pipeline.md`）。
2. **`SECURITY.md` 的措辞与 §3 #5 的开关是配套的**：`SECURITY.md` 写"（维护者需先在 Settings → Security 里启用该功能；未启用时请用下方邮箱。）"——作者已经预见到了未启用的情形。**这条自洽，做得好。**

---

*本文件由调研任务生成，只新建了这一个文件；未修改仓库内任何其它文件。*
