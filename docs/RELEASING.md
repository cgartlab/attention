# 发布流程（RELEASING）

> 本文只写**流程与判据**，规则细则留在单一事实源：版本门槛见 `references/judgment-criteria.md`（多层门）与 `references/release-versioning.md`、变更记录格式见 `references/changelog-sections.md` 与 `assets/templates/changelog-entry.md`、版本载体清单见 `references/version-file-inventory.md`。**本文不复述它们的规则**（复述出来的副本正是历史上漂移的地方）。

## 一、版本策略

| 项 | 约定 |
|---|---|
| 当前阶段 | **未切 1.0**：版本号保持 `0.1.0`，未发布变更记入 `CHANGELOG.md` 的 `[Unreleased]`；**是否切版、切到几，由维护者决定**（`AGENTS.md`） |
| 版本载体 | **唯一载体**：`SKILL.md` frontmatter 的 `metadata.version`（`version_consistency_audit` 识别为 `agent-skill` 生态） |
| 编号语义 | 切版后遵循 semver：`feat` → minor、`fix` → patch、破坏性变更 → major（0.x 期间 minor 可含破坏性变更，但必须在 CHANGELOG 里写明） |
| tag 命名 | `v<version>`（与 `SKILL.md` 版本**逐字一致**——CI 会强制校验，不一致直接拒绝发布） |

## 二、发布前的三道闸（缺一不可）

1. **本地预检**（只读，失败即退出 1）：

   ```powershell
   pwsh -NoProfile -File scripts/release_preflight.ps1 --repo .
   bash scripts/release_preflight.sh --repo .     # 两套实现判据一致
   ```

   检查：工作区干净 / 未在默认分支上直接发版 / 版本一致性（`consistent=true`；`consistent=null` 算"无从判定"，**不算通过**）/ `[Unreleased]` 至少一条 / 三层校验 / 冒烟。

2. **CI 门禁**（`.github/workflows/ci.yml`）：任何 push/PR 都要过 Windows(pwsh) 与 Linux(bash) 双侧的三层校验与冒烟，且"非 git 目录必须判失败"的负例必须成立。

3. **发布门禁**（`.github/workflows/release.yml` 的 `verify` job）：打 tag 后在**干净 runner** 上重跑三层校验、冒烟与 preflight——**不信任本地结果**。

## 三、切一次版的标准动作

1. **确认 `[Unreleased]` 内容完整且可溯源**（每条要能追到 diff 的文件/符号或 commit；追不到就标 `［待补充：…］`）。
2. **定版本号**：按 semver 判定，**拿不准就问维护者**（`reference/release-versioning.md` 的红线：不编造版本号、不擅自跳大版本）。
3. **一致 bump**：
   - `SKILL.md` → `metadata.version: "x.y.z"`
   - `CHANGELOG.md` → 把 `[Unreleased]` 改名为 `## [x.y.z] - <真实日期>`，并在其上方新开一个空的 `## [Unreleased]`
4. **跑闸门**：`release_preflight` + `evals/run_evals.ps1`/`.sh` + `smoke_test`，全绿。
5. **走 PR 合并到默认分支**（推荐）：发布变更本身也要评审；CI 会给双 OS 结论。
6. **打 tag 并推送**：

   ```bash
   git tag v<x.y.z>          # 本地 tag：可撤销，属本地变更
   git push origin v<x.y.z>  # 推 tag：远程不可逆，执行点单独确认
   ```

7. **CI 自动发布**：tag 推送触发 `release.yml` → 干净环境复跑门禁 → 校验 `tag == SKILL.md 版本` → 构建 `dist/attention-<ver>.zip` + `SHA256SUMS` → `gh release create --generate-notes` 创建 Release 并附产物。
8. **发布后核对**：Release 页面有产物与校验和；`git fetch --tags` 后 `git tag -l` 能看到；用 `sha256sum -c SHA256SUMS` 校验下载到的包。

## 四、GitHub 侧一次性设置（维护者）

| 设置 | 位置 | 作用 |
|---|---|---|
| **tag 保护（rulesets）** | Settings → Rules → Rulesets → New ruleset → **Tags** → 目标 `v*` | 禁止删除/强推已发布 tag |
| **不可变发布（若可用）** | Settings → General → Releases（仅在该选项存在时） | 锁定已发布 Release 的 tag 与产物 |
| **Actions 权限最小化** | Settings → Actions → General → Workflow permissions | 默认 `Read repository contents`；release workflow 自己按需声明 `contents: write` |
| **私密漏洞上报** | Settings → Security → Private vulnerability reporting → Enable | 让 `SECURITY.md` 里的上报路径可用 |
| **分支保护** | Settings → Branches → `main` | 要求 PR 评审 + CI 通过（`CODEOWNERS` 已就位） |

## 五、私有仓库的现实约束（本仓库是 private）

- **`npx skills add cgartlab/attention` 与 skills.sh 徽章不可用**：这些面向公开仓库。分发方式是**手动安装**（clone 或 junction），README 已按此写明。
- **Actions 用量**：私有仓库消耗额度；`ci.yml` 已设 `concurrency` 取消陈旧运行、`timeout-minutes` 兜底。
- **provenance/attestation**：`attest-build-provenance` 步骤标了 `continue-on-error: true`——若私库策略不允许则跳过，**不让它阻塞发布**；这一步是否真正生效需在首次发布时看日志确认（**未实测**）。
- 调研（`docs/ecosystem-research/`、`docs/research/`）随仓库一同私有，不会公开。

## 六、回滚

| 情形 | 动作 |
|---|---|
| tag 打错、**还没推** | `git tag -d v<x.y.z>`（本地可撤销） |
| tag 已推、Release 已发 | **不要强推/移动 tag**：发布一个新 patch 版本（`x.y.z+1`）并在 CHANGELOG 说明；随后删除错误 Release（tag 保护会自动拒绝删除 tag，这是刻意的） |
| 发布内容有安全问题时 | 按 `SECURITY.md` 走；修复走 patch 发布，必要时在 Release 说明里标注受影响版本 |

## 七、这一层尚未做到（诚实清单）

- **自动化"准备发布"PR**（release-please 之类：自动算版本 + 写 CHANGELOG + 开 PR）**尚未接入**——当前切版是**人工/模型驱动**的上表第三节流程。是否引入取决于调研结论（`docs/research/github-release-pipeline.md`）：release-please 对"版本写在 `SKILL.md` frontmatter"这种非标准载体的支持需要 `extra-files` + 注解，需实测。
- Release 产物是**源码包 + 校验和**，没有安装器/打包成 `.skill` 的格式（`package_skill.py` 属 skill-creator 生态，未接入）。
- 首次发布前，上面"GitHub 侧一次性设置"**都还没做**（仓库刚创建）。
