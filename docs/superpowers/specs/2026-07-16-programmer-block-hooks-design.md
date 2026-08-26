# 设计：程序员只读挂接 Block（全套路）

> 日期：2026-07-16  
> 状态：已批准  
> 范围：5001 / 5003 / 5006 程序员研究接口 + 引擎校验  
> 方案：A（研究区 CLI + 槽位 + 只读 catalog）
> 实现计划：`docs/superpowers/plans/2026-07-16-programmer-block-hooks.md`
---

## 1. 背景与目标

程序员在隔离模式下只能改 `studies/<研究>/config.R` 与数据，不能接触 `Blocks/`。  
现需允许程序员：

1. **只读搜索**引擎已注册的 block；
2. 在**允许挂接槽位**将 block **插入**自己研究的 `pipeline_*$blocks`；
3. 下次 `run_study` **真实执行**该 block；
4. **生成新的决策树文件**反映扩展后的流水线（**不得改动**母版/原决策树）。

### 1.1 红线

| 允许 | 禁止 |
|------|------|
| 读 block catalog / hook slots | 写 `Blocks/`、改 `R/pipeline_runner.R` |
| 改自己研究的 `config.R`（经 `add_block`） | 新增未在 registry 中的 block |
| 在研究目录**新建**决策树版本文件 | 修改引擎或研究区 `docs/Decisiontree/` 母版 |
| `run_study` 跑挂接后的 pipeline | 手改乱插 pipeline 却仍能跑通 |

### 1.2 已确认决策

- 插入位置：任意，但必须落在声明的 **hook slot**（锚点之后 / 段末）。
- 交互：CLI（`search_blocks` / `add_block` / `remove_block`）。
- 套路：**全部**（incidence / survival / ml / environment）。
- 决策树：**原决策树不动**；每挂接一次（或每次扩展变更）**生成新决策树**。
- 校验：未走 `add_block`、手改乱插 → **直接报错停跑**。

---

## 2. 架构

```
程序员可见（medical-blocks-studies）          引擎 MEDICAL_BLOCKS_ROOT（只读）
───────────────────────────────────          ────────────────────────────────
search_blocks.sh/.bat  ──读──►  docs/block_catalog/catalog.json
add_block.sh/.bat      ──读──►  docs/block_catalog/hook_slots.yaml
remove_block.sh/.bat   ──读──►  （由管理员从引擎导出的副本）
                                ◄── 源：pipeline_block_sources() + hook_slots 权威稿

studies/<研究>/
  config.R                 ◄── add_block 写入插入
  extensions.json          ◄── 挂接审计（唯一合法扩展清单）
  Decisiontree/            ◄── 仅研究本地；母版只读复制进来
    baseline_<routine>.md  ◄── 首次从母版复制，之后永不改
    tree_v001.md           ◄── add_block 生成的新树
    tree_v002.md
    CURRENT.md             ◄── 指向当前版本的软说明或副本
```

**真能跑的前提**：block 名必须存在于引擎 `R/pipeline_runner.R` → `pipeline_block_sources()`。  
未注册的 `Blocks/**/*.R` **不进入 catalog**，无法挂接。

---

## 3. Catalog（只读目录）

### 3.1 生成（管理员）

引擎脚本（示例路径）：

```text
Rscript scripts/export_block_catalog.R \
  --out /path/to/medical-blocks-studies/docs/block_catalog/
```

产出：

| 文件 | 内容 |
|------|------|
| `catalog.json` | `block_id` → `{ path_rel, tags[], routines[], summary }` |
| `catalog.md` | 人读索引（由 json 生成） |
| `hook_slots.yaml` | 全套路槽位（见 §4） |
| `GENERATED_AT.txt` | 导出时间；程序员勿改 |

`path_rel` 仅作说明；运行时仍走 `pipeline_block_sources`，**禁止**按路径随意 `source`。

### 3.2 标签（可选过滤）

由管理员在导出映射表中维护，例如：`mediation` / `enrichment` / `plot` / `subgroup` / `report`。  
无标签的 block 默认可挂到声明了 `allow_tags: ["*"]` 的槽，或仅出现在全局搜索、不能挂到受限槽。

---

## 4. Hook slots（全套路）

权威稿放在引擎：`configs/study_interface/hook_slots.yaml`，导出到各端口 `docs/block_catalog/`。

### 4.1 字段

```yaml
slots:
  - id: environment.tail_after_mediation
    routine: environment
    pipeline_key: pipeline_tail      # config 中的对象名
    anchor_block: mediation_ers_environment
    position: after                  # after | end
    allow_tags: ["*"]
    max_extra: 8
    description: "尾段中介分析之后"
```

`position: end` 时忽略锚点，插入该 `pipeline_key` 的 `$blocks` 末尾。

### 4.2 首版槽位表

#### environment

| slot id | pipeline_key | 锚点 / 位置 |
|---------|--------------|-------------|
| `environment.shared_after_bkmr_analysis` | `pipeline_shared` | after `bkmr_analysis` |
| `environment.shared_end` | `pipeline_shared` | end |
| `environment.tail_after_qgcomp` | `pipeline_tail` | after `qgcomp_environment` |
| `environment.tail_after_mediation` | `pipeline_tail` | after `mediation_ers_environment` |
| `environment.tail_end` | `pipeline_tail` | end |

（`pipeline_voc_batch` 默认**不开放**挂接，避免打乱按 VOC 并行契约；若未来需要另开槽并专项测试。）

#### incidence

| slot id | pipeline_key | 锚点 / 位置 |
|---------|--------------|-------------|
| `incidence.nhanes_after_rcs` | `pipeline_nhanes_batch` | after `rcs_nhanes` |
| `incidence.nhanes_after_mediation` | `pipeline_nhanes_batch` | after `mediation_nhanes_weighted` |
| `incidence.nhanes_end` | `pipeline_nhanes_batch` | end |
| `incidence.regular_after_rcs` | `pipeline_regular_batch` | after `rcs_incidence` |
| `incidence.regular_after_mediation` | `pipeline_regular_batch` | after `mediation_incidence` |
| `incidence.regular_end` | `pipeline_regular_batch` | end |

共享层 `pipeline_shared_*`：**不开放**挂接（避免污染全指标共享检查点）。

#### survival

| slot id | pipeline_key | 锚点 / 位置 |
|---------|--------------|-------------|
| `survival.after_rcs_prognosis` | `pipeline_regular_batch` | after `rcs_prognosis` |
| `survival.after_subgroup_prognosis` | `pipeline_regular_batch` | after `subgroup_prognosis` |
| `survival.end` | `pipeline_regular_batch` | end |

共享层不开放。

#### ml

| slot id | pipeline_key | 锚点 / 位置 |
|---------|--------------|-------------|
| `ml.primary_after_shap` | `pipeline_regular_primary_ml_batch` 或 `pipeline_nhanes_batch`（按主库类型） | after `shap` |
| `ml.primary_end` | 同上 | end |
| `ml.secondary_after_shap` | `pipeline_mimic_ml_batch` | after `shap` |
| `ml.secondary_end` | `pipeline_mimic_ml_batch` | end |

共享层不开放。主库 `pipeline_key` 由研究 config 的 `dual_db$primary$db_type` 解析。

---

## 5. CLI 行为

部署于各端口 `medical-blocks-studies/` 根目录。

### 5.1 `search_blocks`

```bash
./search_blocks.sh mediation
./search_blocks.sh --routine environment
./search_blocks.sh --list-slots --routine survival
./search_blocks.sh --tag plot --routine ml
```

- 只读 `docs/block_catalog/`
- 输出：block 名、摘要、可用 routines、可用 slots（若 `--routine`）

### 5.2 `add_block`

```bash
./add_block.sh <研究名> --slot environment.tail_after_mediation --block environment_target_enrichment
```

步骤：

1. 解析研究目录与套路（同 `run_study` 识别逻辑；可用 `--routine` 覆盖）。
2. 校验 slot ∈ hook_slots 且 routine 匹配。
3. 校验 block ∈ catalog 且 ∈ `pipeline_block_sources` 名集合；校验 `allow_tags`。
4. 读取 `extensions.json`（无则建）；检查 `max_extra`、幂等（同 slot+block 已存在则跳过写入并提示）。
5. **改写** `config.R`：在目标 `pipeline_*$blocks` 锚点后（或 end）插入 block 名字符串。  
   - 实现优先：结构化编辑（R 解析 AST 或正则锚定 `pipeline_tail <- list(` / `blocks = c(`）；失败则报错，不半写。
6. 更新 `extensions.json`：追加 `{ slot, block, added_at, tree_version }`。
7. **决策树**：见 §6 —— **不改** baseline；生成新版本 `tree_vNNN.md`，更新 `CURRENT` 指针。
8. 打印下次运行命令：`run_study.bat <研究> ...`

### 5.3 `remove_block`

对称删除 config 中该次挂接插入的名称、更新 extensions、**再生成**新决策树版本（仍不改旧文件与 baseline）。

### 5.4 Windows

`search_blocks.bat` / `add_block.bat` / `remove_block.bat` 调用同一 R/bash 实现（优先 `Rscript` 与 5003 的 R-4.5.1 路径策略一致）。

---

## 6. 决策树策略（关键）

### 6.1 原则

- **母版不动**：引擎 `Decisiontree/*.md`、研究区 `docs/Decisiontree/*.md` 只作只读母版。
- **研究内 baseline 不动**：首次引入时复制为  
  `studies/<研究>/Decisiontree/baseline_<routine>.md`，之后 **永不修改**。
- **每次扩展变更生成新树**：  
  `studies/<研究>/Decisiontree/tree_v001.md`、`tree_v002.md`、…  
  内容 = baseline 全文（或结构化渲染）+ 「本版本挂接清单」+ 更新后的 mermaid（含新节点）。
- `CURRENT.md`：纯文本或短 md，写明 `current: tree_v00N.md`；或复制当前版本以便打开。  
  **禁止**回头改写已发布的 `tree_v00N.md`（版本只增不改）。

### 6.2 新树内容要求

每个 `tree_vNNN.md` 必须包含：

1. 标题与版本号、生成时间、相对 baseline 的 diff 摘要；  
2. 挂接表：`slot` / `block` / `pipeline_key`；  
3. 完整流程图（mermaid），在对应 subgraph 画出新 block；  
4. 页脚注明：`Generated by add_block; do not edit Blocks/.`

### 6.3 与 config 一致性

`extensions.json` 是合法扩展的 **唯一真相**；`tree_v*` 与 config 均由 CLI 从该文件生成/更新。

---

## 7. 运行时硬校验（停跑）

在 `run_environment_dkd_batch.R` / `run_incidence_dual_batch.R` / `run_survival_dual_batch.R` / `run_ml_dual_batch.R`（或共享的 `R/pipeline_extension_guard.R`）于 `run_pipeline` / batch 开始前：

1. 加载套路 **基线 blocks**（模板或 build 后「无 extensions」快照）。  
2. 计算当前 `pipeline_*$blocks` 相对基线的 **多余** block 列表。  
3. 若存在多余 block：  
   - 必须每条都能在 `extensions.json` 找到匹配记录，且  
   - 在实际 blocks 向量中的位置符合对应 slot（锚点后 / end，且未越过下一硬边界若有定义）；  
   - 否则 **`stop()`**，信息示例：  
     `非法 pipeline 扩展: 'foo' 不在 extensions.json。请用 add_block.sh 挂接，勿手改。`
4. 多余 block 名不在 `pipeline_block_sources` → **stop**。  
5. 无 `extensions.json` 且 pipeline 与基线完全一致 → 通过。  
6. 有 `extensions.json` 但 config 缺少其中记录的 block → **stop**（配置被手删导致不一致）。

**手改乱插、绕过 CLI → 直接报错停跑**（已确认）。

薄 config（`.study` + build）场景：基线 = build 脚本展开后的默认 pipeline；extensions 仍只允许改研究目录内最终 `config` 环境中的 pipeline 对象（build 之后、run 之前由 guard 看见的对象）。实现时在 `source(config)` 之后、跑 batch 之前调用 guard。

---

## 8. 权限与部署

| 路径 | 程序员 |
|------|--------|
| `Blocks/`、`R/`、引擎 `Decisiontree/` | 无写 |
| `docs/block_catalog/`、`docs/Decisiontree/`（母版） | 只读 |
| `studies/<自己的研究>/` | 读写 |
| `search_blocks*` / `add_block*` / `remove_block*` | 可执行 |

同步到：

- `5001`：incidence + survival 槽 + CLI + catalog  
- `5003`：ml + environment  
- `5006`：environment  

管理员导出 catalog 的流程写入 `skills/deploy-programmer-interface/SKILL.md` 增量一节。

---

## 9. 分期交付

| 阶段 | 内容 |
|------|------|
| **P0** | `export_block_catalog.R`；`hook_slots.yaml`（四套路）；研究区 `search_blocks` / `add_block` / `remove_block`；`extensions.json`；决策树 baseline 复制 + `tree_vNNN` 生成 |
| **P1** | `pipeline_extension_guard.R` 接入四个 run 入口；非法扩展 stop |
| **P2** | `.bat`；三端口 README / 程序员指南；每套路一条冒烟（挂接 → 跑 `--shared-only` 或 `--tail-only` / `--only-index`） |

---

## 10. 非目标（本设计不做）

- 程序员新建/修改 block 源码；  
- 开放共享层任意插入；  
- 可视化拖拽 UI；  
- 自动把未注册的 `Blocks/**` 扫进可挂目录。

---

## 11. 验收标准

1. `search_blocks mediation` 能列出已注册相关 block，且不触碰 `Blocks/` 写入。  
2. `add_block` 后 config 中对应 `pipeline_*$blocks` 含新名；`run_study` 执行到该 block（日志出现 Block 头）。  
3. 母版与 `baseline_*.md` 字节级不变；出现新的 `tree_v00N.md` 且含新节点。  
4. 手改 `config.R` 在非法位置插入未登记 block → 启动即 stop。  
5. 5001/5003/5006 均可完成至少一条各自套路的挂接演示。

---

## 12. 开放实现细节（实现计划阶段敲定）

- `config.R` 结构化编辑：R `parse`/`deparse` vs 锚点正则的选择与失败回滚。  
- 薄 config 下 guard 的「基线快照」是 build 内嵌默认还是导出的 `baseline_blocks.json`。  
- `CURRENT.md` 用指针文件还是整文件复制。

以上不影响本设计的产品约束。
