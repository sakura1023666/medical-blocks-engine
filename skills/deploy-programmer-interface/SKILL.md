---
name: deploy-programmer-interface
description: >-
  为 Medical Blocks 新套路部署「程序员接口」：引擎与研究工作区分离、薄 config
  构建器、run_study 入口、templates 副本、敏感性/亚组补救挂接。当用户说给程序员
  接口、DockerHome/5001、看不见 block、只改 config 和数据、medical-blocks-studies、
  研究区部署、外部 config 跑流水线时使用。与 create-pipeline-config（写 config）
  和 run-batch-pipeline（批量引擎）配合。
---
# 部署程序员研究接口

把 Medical Blocks **引擎**（Blocks/R/runner）与 **研究工作区**（config + Data + 产出）分离，让程序员只改 config、放数据、点运行。

**关联 skill**：

- `create-pipeline-config` — 写 config / pipeline 模板
- `run-batch-pipeline` — 批量三层架构（共享层→指标层→汇总）
- `feishu-result-sync` — 飞书推送（程序员侧通常关闭）

**已有参考实现**：`\\192.168.68.133\DockerHome\5001\medical-blocks-studies\`（WSL: `/mnt/g/DockerHome/5001/medical-blocks-studies/`）

---

## 架构（必守）

```
程序员可见                         管理员/引擎（不可见）
─────────────────                 ─────────────────────
medical-blocks-studies/           MEDICAL_BLOCKS_ROOT/
├── run_study.bat/sh      ──────► run_*_batch.R
├── engine.env            ──────► Blocks/, R/, configs/templates/
├── templates/            （模板副本，复制后改）
├── docs/create-pipeline-config/
└── studies/<研究>/
    ├── config.R          ── --config ──► 引擎读外部 config
    ├── Data/
    └── by_index/ Tables/ （产出）
```

**红线**：

- 程序员**不**接触其它 `Blocks/**`、`R/pipeline_runner.R`；**唯一例外**经研究区 `editable/01block_index.R` 改复合指标（全局共用）
- config 里**禁止** `run_block()` 可执行代码
- 队列过滤：敏感性在主分析插补后 checkpoint 上删人（轻量只 Table 1/2）；亚组补救仍走 worker 过滤。不用 `data_clean$age_filter`（会污染共享层）

---

## 何时走本 skill

| 场景                            | 走本 skill                                                    |
| ------------------------------- | ------------------------------------------------------------- |
| 新套路要给外部程序员跑          | ✅                                                            |
| 只在引擎内自己跑                | ❌ 用 create-pipeline-config 即可                             |
| 新批量套路（尚无 batch runner） | 先`run-batch-pipeline`，再本 skill                          |
| 单库非 batch                    | 可部署，但需新建`study_interface/*_build.R` + 对应 run 入口 |

---

## 工作流（新套路 checklist）

复制此清单并逐项打勾：

```
部署进度：
- [ ] 1. 引擎内套路已可跑（config 模板 + run_*.R + runner 映射）
- [ ] 2. 若是批量：batch runner + worker 已实现
- [ ] 3. 引擎内 configs/study_interface/<套路>_build.R（薄 config 构建器）
- [ ] 4. 同步 templates/config_<套路>.template.R 到研究区 templates/
- [ ] 5. 研究区目录 scaffold（run_study、engine.env、studies/_template）
- [ ] 6. docs/create-pipeline-config/程序员配置指南.md 补充该套路
- [ ] 7. 示例研究 + 冒烟测试
- [ ] 8. README 运行命令
- [ ] 9. Block 挂接：导出 catalog + 复制 CLI 包装器（见下文 § Block 挂接）
- [ ] 10. 各端口 `docs/Decisiontree/` 母版决策树已就位（按套路，见母版映射表）
```

---

## Step 1：确认引擎套路名称

| 套路           | run 入口                                     | 薄 config 构建器                                         | 模板                                       |
| -------------- | -------------------------------------------- | -------------------------------------------------------- | ------------------------------------------ |
| 发病双库批量   | `run/incidence/run_incidence_dual_batch.R` | `configs/study_interface/incidence_dual_batch_build.R` | `config_incidence_dual_batch.template.R` |
| 预后双库批量   | `run/survival/run_survival_dual_batch.R`   | `configs/study_interface/survival_dual_batch_build.R`  | `config_survival_dual_batch.template.R`  |
| ML 双库批量    | `run/ml/run_ml_dual_batch.R`               | `configs/study_interface/ml_dual_batch_build.R`        | `config_ml_dual_batch.template.R`        |
| 共病×孟德尔    | `run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R` | `configs/study_interface/crm_nhanes_mr_batch_build.R` | `config_crm_nhanes_mr_batch.template.R` |
| 发病双库单指标 | `run_incidence_dual.R`                     | 待建                                                     | `config_incidence_dual.template.R`       |
| 预后 SAE       | `run_survival_sae.R`                       | 待建                                                     | `config_survival_sae.template.R`         |
| …             | …                                           | …                                                       | …                                         |

**已有批量发病双库可直接复用**；新套路按下列模式新增 build 脚本。

---

## Step 2：编写薄 config 构建器（引擎内）

路径：`configs/study_interface/<routine>_build.R`

模式（以 incidence dual batch 为准）：

1. 要求程序员 config 定义 `.study` 列表 + `.batch_project_root <- normalizePath(getwd())`
2. 读取 `MEDICAL_BLOCKS_ROOT`；缺失则 stop
3. 由 `.study` 拼 `config` 骨架（路径、project、dual_db、incidence_batch、sensitivity_suite）
4. `source(configs/templates/config_<routine>.template.R)` 补全 block 段 + pipeline
5. **深合并**程序员段覆盖模板；**保存并恢复** `.batch_project_root`（模板 source 会覆盖）
6. 强制写回 `output_dir`、`rawdata_path`、checkpoint 路径

参考：`configs/study_interface/incidence_dual_batch_build.R`

程序员 config 末尾一行：

```r
source(file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT"),
  "configs/study_interface/incidence_dual_batch_build.R"))
```

---

## Step 3：引擎 run 入口能力

批量发病至少支持：

| CLI                          | 用途                 |
| ---------------------------- | -------------------- |
| `--config <path>`          | 外部研究 config      |
| `--workers N`              | 并行                 |
| `--shared-only`            | 只跑共享层           |
| `--only-index IX`          | 指定指标             |
| `--sensitivity-only`       | 只跑敏感性           |
| `--subgroup-fallback-only` | 只跑失败指标亚组补救 |
| `--no-skip`                | 强制重跑             |

环境变量：`MEDICAL_BLOCKS_ROOT`（run_study 设置，与 `--config` 解耦工作目录）

---

## Step 4：扩展能力（按需挂接 runner 末尾）

### 敏感性分析（success 指标）

- 模块：`R/incidence_sensitivity_suite.R`
- Config：`incidence_batch$sensitivity_suite`（`enable` / `age_cutoff` / `min_n_per_db` / `min_yes_n`；无手写 `scenarios`）
- 触发：主批量完成后 / `--sensitivity-only`
- 机制：主分析插补后删人，只重跑 Table 1 / Table 2；场景 = Table 1 Yes/No（两库 Yes>50）+ 年龄分层
- 产出：`by_index/<ix>/sensitivity/【success】<场景>/` 与 `【failed】`；表 S12/S13

### 亚组补救（failed 指标）

- 模块：`R/incidence_subgroup_fallback.R`
- Config：`incidence_batch$subgroup_fallback$enable`
- 触发：主批量 failed 后 / `--subgroup-fallback-only`
- **不是**主流程 `subgroup_incidence` 森林图

三者区别见 [reference.md](reference.md#三种亚组敏感性)。

---

## Step 5：部署研究区目录

目标根目录（默认）：`\\192.168.68.133\DockerHome\5001\medical-blocks-studies\`

```
medical-blocks-studies/
├── README.md
├── engine.env                 # MEDICAL_BLOCKS_ROOT=...
├── engine.env.example
├── run_study.bat
├── run_study.sh
├── editable/                  # 唯一可写引擎入口（方案 B）
│   ├── README.md              # 全局影响警告
│   └── 01block_index.R        # → MEDICAL_BLOCKS_ROOT/Blocks/00_index/01block_index.R
├── templates/                 # 从 configs/templates/ 同步副本 + README.md
├── docs/create-pipeline-config/
│   ├── 程序员配置指南.md
│   ├── examples.md
│   └── SKILL.md               # 引擎规范备查
└── studies/
    ├── _template/
    │   ├── config.R           # 薄 config 示例
    │   ├── STUDY.md
    │   └── Data/eicu|mimic/README.txt
    └── <示例研究>/
```

### run_study.bat 核心逻辑

1. 解析 `studies/<研究名>/config.R`
2. 读 `engine.env` → `MEDICAL_BLOCKS_ROOT`
3. `Rscript %ENGINE%/run_*_batch.R --config %CONFIG% %*`

### 跨平台路径

程序员 config / build 脚本内：

```r
.batch_project_root <- if (.Platform$OS.type == "windows") {
  "G:/path/to/studies/my_study"
} else {
  "/mnt/g/path/to/studies/my_study"
}
```

或研究 config 用 `normalizePath(getwd())`（推荐，产出写在本研究文件夹）。

---

## Step 6：同步模板与文档

每次引擎 `configs/templates/` 有更新：

```bash
cp configs/templates/*.template.R /path/to/medical-blocks-studies/templates/
cp configs/templates/README.md    # 若有；否则维护 templates/README.md 选型表
```

更新 `docs/create-pipeline-config/程序员配置指南.md`：

- 新套路的 `.study` 字段说明
- 模板文件名与【必改】键
- 数据格式要求

---

## Step 7：示例研究与测试

1. 复制 `_template` → `studies/<disease>_incidence_<pmid>/`
2. 链式或复制 Data（`Data/eicu`、`Data/mimic`）
3. 冒烟：

```bash
cd /mnt/g/DockerHome/5001/medical-blocks-studies
./run_study.sh <研究名> --shared-only
./run_study.sh <研究名> --workers 2 --only-index NLR
./run_study.sh <研究名> --sensitivity-only --only-index NLR   # 若启用 sensitivity_suite
```

4. 验证：`by_index/<ix>/_batch_status.json` status=success；`Tables/Batch_summary_all_indices.csv`

---

## 程序员交付命令模板

写入研究区 `README.md`：

```bat
cd \\192.168.68.133\DockerHome\5001\medical-blocks-studies
run_study.bat <研究名> --shared-only
run_study.bat <研究名> --workers 4
run_study.bat <研究名> --workers 4 --only-index NLR,SII
run_study.bat <研究名> --sensitivity-only
```

```bash
cd /mnt/g/DockerHome/5001/medical-blocks-studies
./run_study.sh <研究名> --workers 4
```

---

## 新套路扩展指南（管理员）

当套路**不是** incidence dual batch：

1. **create-pipeline-config** — 完成 `configs/templates/config_<new>.template.R` + `run_<new>.R`
2. **run-batch-pipeline**（若需批量）— batch runner + worker
3. **本 skill** —
   - 新建 `configs/study_interface/<new>_build.R`（定义 `.study` 字段契约）
   - `run_study` 改为调用对应 `run_<new>_batch.R`（或增加 `--routine` 参数分发）
   - 同步模板 + 更新程序员指南
   - `_template/config.R` 示例

### .study 字段契约（示例：incidence dual batch）

```r
.study <- list(
  disease_code, disease, literature_pmid,
  analysis_group, reference_group,
  index_group, index_vars,
  eicu_rdata_obj, mimic_rdata_obj,
  common_model_factors,
  sensitivity_enable, sensitivity_age_cutoff,
  feishu_enable
)
```

新套路在 build 脚本头部文档化必填/可选字段。

---

## 权限建议（NTFS 共享）

| 路径                             | 程序员 |
| -------------------------------- | ------ |
| `studies/`                     | 读写   |
| `editable/01block_index.R`（链接到引擎 index） | 读写（**唯一**可写引擎文件；全局共用） |
| `templates/`                   | 只读   |
| `engine.env`, `run_study.*`  | 只读   |
| `MEDICAL_BLOCKS_ROOT` 其它引擎路径 | 无访问 / 只读；**禁止**改非 index 的 `Blocks/**` |

---

## Block 挂接（程序员只读 catalog + 槽位插入）

> 设计：`docs/superpowers/specs/2026-07-16-programmer-block-hooks-design.md`  
> 引擎实现：`R/programmer_block_hooks.R`、`scripts/deploy_block_hooks_to_studies.sh`

程序员可**只读搜索**引擎已注册 block，在**声明的 hook slot** 挂接到自己研究的 `pipeline_*$blocks`；`run_study` 会真实执行；每次挂接生成新决策树版本，**不改**母版。

### 母版决策树映射（`R/programmer_block_hooks.R`）

| 套路 | 引擎母版 | 各端口 `docs/Decisiontree/` |
|------|----------|---------------------------|
| incidence | `Decisiontree/decision_tree_incidence_dual_batch.md` | **5001**、**5003** |
| survival | `Decisiontree/decision_tree_survival_dual_batch.md` | **5001** |
| crm | `Decisiontree/decision_tree_crm_nhanes_mr.md` | **5001** |
| ml | `Decisiontree/decision_tree_ml_dual_batch.md` | **5003** |
| environment | `Decisiontree/decision_tree_environment_voc_batch.md` | **5003**、**5006** |
| ipw | `Decisiontree/decision_tree_ipw_diabetes_stroke.md` | **5003** |
| trajectory | `Decisiontree/decision_tree_trajectory_prognosis_apri.md` | **5006** |
| competing | `Decisiontree/decision_tree_competing_risk_stroke.md` | **5006** |
| tst（两阶段 Transformer） | `Decisiontree/decision_tree_two_stage_transformer_stroke.md` | **5006**（可迁 34:2202） |
| ipw（用药Jin） | `Decisiontree/decision_tree_ipw_diabetes_stroke.md` | **5003**（可迁 34:2203） |

首次部署或母版缺失时，从引擎 `Decisiontree/` **复制**到对应端口（勿改内容）：

```bash
ENGINE=/mnt/e/01block/01Block-new-Final/Decisiontree
# 5001
cp "$ENGINE/decision_tree_incidence_dual_batch.md" \
   "$ENGINE/decision_tree_survival_dual_batch.md" \
   "$ENGINE/decision_tree_crm_nhanes_mr.md" \
   /mnt/g/DockerHome/5001/medical-blocks-studies/docs/Decisiontree/
# 5003
cp "$ENGINE/decision_tree_ml_dual_batch.md" \
   "$ENGINE/decision_tree_environment_voc_batch.md" \
   "$ENGINE/decision_tree_incidence_dual_batch.md" \
   /mnt/g/DockerHome/5003/medical-blocks-studies/docs/Decisiontree/
# 5006
cp "$ENGINE/decision_tree_environment_voc_batch.md" \
   "$ENGINE/decision_tree_trajectory_prognosis_apri.md" \
   "$ENGINE/decision_tree_competing_risk_stroke.md" \
   "$ENGINE/decision_tree_two_stage_transformer_stroke.md" \
   /mnt/g/DockerHome/5006/medical-blocks-studies/docs/Decisiontree/
```

### 导出 catalog + 部署 CLI（registry / hook_slots 变更后必做）

```bash
cd /mnt/e/01block/01Block-new-Final
./scripts/deploy_block_hooks_to_studies.sh
```

写入各端口：

- `docs/block_catalog/` — `catalog.json`、`hook_slots.yaml`（只读副本）
- `search_blocks` / `add_block` / `remove_block`（`.sh` + `.bat`）
- `editable/01block_index.R` — 符号链接到引擎 `Blocks/00_index/01block_index.R`（程序员唯一可写引擎文件）

**触发重导**：`pipeline_block_sources()` 增删 block、`configs/study_interface/hook_slots.yaml` 变更、或 CLI 包装器模板更新。

### 程序员 CLI（研究区根目录）

```bat
search_blocks.bat mediation
search_blocks.bat --list-slots --routine environment
add_block.bat 我的研究 --slot environment.tail_end --block plot_histogram
remove_block.bat 我的研究 --slot environment.tail_end --block plot_histogram
```

红线：程序员**不得**写其它 `Blocks/**`、不得手改 `pipeline_*$blocks` 绕过 CLI；母版 `docs/Decisiontree/*.md` 只读。  
**唯一例外**：经 `editable/01block_index.R` 改复合指标公式（全局共用；设计见 `docs/superpowers/specs/2026-07-17-programmer-writable-index-block-design.md`）。

---

## 附加资源

- 三种亚组/敏感性/补救区别：[reference.md](reference.md)
- 研究区 README 完整示例：[examples.md](examples.md)
- 批量引擎细节：`skills/run-batch-pipeline/SKILL.md`
- Block 挂接设计：`docs/superpowers/specs/2026-07-16-programmer-block-hooks-design.md`

