# 听力损失 UHR 三库发病（协变量对齐）— 设计规格

> 状态：已确认（2026-07-28）  
> 产出根：`G:/02block_result/15_hearing_loss/incidence_38341157`  
> WSL 数据：`/mnt/g/02block_result/15_hearing_loss/incidence_38341157/data`  
> 方案：**方案 1** — 预处理对齐 + 现有 `incidence_dual_batch`（NHANES+CHARLS）+ 李玲单库（同一锁定协变量）  
> 指标范围：**仅 UHR**

## 0. 已确认决策

| 项 | 选择 |
| ---- | ---- |
| 三库 | NHANES = `D04_dabiao_N_听力损失_45_69.RData`；CHARLS = `D04_dabiao_C_听力损失_45_69.RData`；李玲 = `D04_dabiao_李玲_听力损失_45_69.RData` |
| 不用 | `D01_baseline_NHANES_0728.RData`（母库，不作为分析库） |
| 统一方式 | **A**：三库各自建模；协变量取交集并锁定；NHANES 加权，CHARLS/李玲不加权 |
| 李玲单位 | **A**：尿酸 `UricAcid/59.48` → mg/dL；HDL `*38.67` → mg/dL；若 `HDL>10` 视为已是 mg/dL 不换 |
| 结局 | **A**：`1`/`Hearing Loss` → `Hearing_Loss`；`0`/`Normal` → `Normal`；`analysis_group=Hearing_Loss`，`reference_group=Normal` |
| 指标 | **仅 UHR**（`Uric_Acid / HDL`，引擎 `Blocks/00_index`） |
| 引擎改动 | **不**扩展三库 dual 引擎；**不**改 Blocks 01–70 核心逻辑（仅研究侧 prep + config + 可选薄编排脚本） |

## 1. 研究问题（本套路）

在 45–69 岁听力损失发病队列中，评估 **UHR** 与听力损失的关联，并在三个独立数据库中用**同一套锁定协变量**复现：

1. NHANES（复杂抽样加权 logistic）；
2. CHARLS（普通 GLM）；
3. 李玲库（普通 GLM，外推/验证）。

不做三库个体水平混合模型；主文报告的是三库平行结果对照。

## 2. 架构与数据流

```
raw RData (N / C / 李玲)
        ↓ prep 脚本（一次性）
data/harmonized/
  D04_NHANES_hearing_45_69.RData   (obj=dabiao)
  D04_CHARLS_hearing_45_69.RData
  D04_Liling_hearing_45_69.RData
  covariate_lock.json              (三库交集名单)
        ↓
config_incidence_dual_batch.R
  primary=NHANES (db_type=nhanes, weighted)
  secondary=CHARLS (db_type=regular)
  incidence_batch.only / --only-index UHR
        ↓ run_incidence_dual_batch.R
by_index/UHR/{NHANES,CHARLS}/...
        ↓
config_incidence_liling.R
  强制 common_model_factors = covariate_lock
  database_type=regular
        ↓ run/incidence/run_incidence_single.R --config ... --only-index UHR
by_index/UHR/Liling/...
```

**硬约束**

- 分析对象名统一为 `dabiao`；结局列统一为 `Disease_Group`。
- 引擎指标公式依赖标准列名 `Uric_Acid`、`HDL`（column_mapping / prep 必须落到这两名）。
- NHANES 保留 `SDMVPSU`、`SDMVSTRA`、`WTMEC2YR`/`WTMEC4YR`（或已有 `new_Weight`）；`nhanes$auto_new_weight = TRUE`。
- `index$enable = TRUE`，批量入口 `--only-index UHR`；不得默认跑 dual_safe 全表。
- 李玲 n≈411：亚组/中介允许失败跳过；主路径至少完成基线 + 分位数/连续 logistic。

## 3. 组件

### 3.1 预处理脚本

路径定稿：`scripts/prep_hearing_loss_uhr_triple.R`（写出到研究目录 `data/harmonized/`）。

职责：

1. 读三份原始 RData；
2. 结局重编码为因子/字符 `Hearing_Loss` / `Normal`；
3. 列名对齐到引擎字典（至少：`Uric_Acid`、`HDL`、`Disease_Group`、`Age`、`Gender`，以及交集协变量）；
4. 李玲单位换算与 HDL 异常处理（`HDL>10` 不换；换算后仍极端者剔除或记入 QC 表）；
5. 写出 harmonized RData + QC 摘要（n、事件数、UHR 分布、单位换算前后对照）；
6. 计算三库协变量交集 → `covariate_lock.json`。

交集规则：

- 仅考虑人口学/临床候选（排除 ID、权重、PSU/strata、纯实验室中间列若某一库缺失）；
- 列名先映射再求交；
- 至少保留 `Age`、`Gender`；若交集过窄（少于 3 个非指标协变量），prep 失败并打印各库可用列，不静默继续。

### 3.2 双库 config（NHANES + CHARLS）

自 `configs/templates/config_incidence_dual_batch.template.R` 复制到：

`G:/02block_result/15_hearing_loss/incidence_38341157/config_incidence_dual_batch.R`

必改：

- `.batch_project_root` = 该研究目录；
- `project$disease_code=15`，`disease=hearing_loss`，`literature_pmid=38341157`；
- `analysis_group=Hearing_Loss`，`reference_group=Normal`；
- `dual_db$primary` → harmonized NHANES；`secondary` → harmonized CHARLS，`name` 分别为 `NHANES` / `CHARLS`；
- `harmonization$common_model_factors`（或等价锁字段）← `covariate_lock`；
- `incidence_batch` 指向本目录；飞书可先 `enable=FALSE`（除非用户另开）。

运行：

```bash
Rscript run/incidence/run_incidence_dual_batch.R \
  --config "G:/02block_result/15_hearing_loss/incidence_38341157/config_incidence_dual_batch.R" \
  --only-index UHR --db both
```

### 3.3 李玲单库 config + 入口

自 `configs/templates/config_incidence_single.template.R` 复制为：

`G:/02block_result/15_hearing_loss/incidence_38341157/config_incidence_liling.R`

- `rawdata_path` → harmonized 李玲；`rawdata_obj=dabiao`；
- `database_type=regular`；`database=Liling`；
- `output_dir` 指向 `.../by_index/UHR/Liling`（或研究根下由 pipeline 写入该子树）；
- 强制 multivariate / model factors = `covariate_lock`（与 dual 相同 JSON）；
- `incidence$index_var="UHR"`（单库不走多指标 batch 时直接钉死）。

**入口定稿**：仓库模板写明 `run_incidence_single.R`，但 `run/incidence/` 目前仅有 dual_batch；实现时**补薄入口** `run/incidence/run_incidence_single.R`，职责仅为：解析 `--config` / 可选 `--only-index` → `source` 依赖与 config → `run_pipeline(root, config, pipeline)`。复用 single 模板里的 `pipeline`（regular、非加权），禁止另起 Blocks。

```bash
Rscript run/incidence/run_incidence_single.R \
  --config "G:/02block_result/15_hearing_loss/incidence_38341157/config_incidence_liling.R"
```

### 3.4 产出布局

```
15_hearing_loss/incidence_38341157/
  data/                  # 原始
  data/harmonized/       # prep 产物
  config_incidence_dual_batch.R
  config_incidence_liling.R
  checkpoints/
  by_index/UHR/
    NHANES/
    CHARLS/
    Liling/
```

## 4. 错误处理与 QC

| 情况 | 行为 |
| ---- | ---- |
| 李玲换算后 UHR 全 NA / n 少于 50 | prep 中止 |
| CHARLS `Disease` NA（已知 44 行） | 随结局缺失剔除，记入 QC |
| NHANES 缺权重列 | dual 启动前 fail-fast |
| 李玲亚组/中介失败 | `fail_policy=continue`，主 logistic 仍算成功 |
| HDL 异常（李玲 max=96） | prep QC 表列出；默认：换算规则按决策执行，换算后 UHR 用 p_trim 与引擎一致 |

## 5. 测试 / 验收

1. Prep：三库 `Disease_Group` 水平仅为 `Hearing_Loss`/`Normal`；`Uric_Acid`/`HDL` 中位数落在 NHANES/CHARLS 同量级（尿酸约 3–7 mg/dL，HDL 约 40–60 mg/dL）。
2. Dual：`by_index/UHR/_batch_status.json` 为 success（或 NHANES/CHARLS 分支明确状态）；NHANES 路径走加权 logistic block。
3. 李玲：主表 OR/基线表产出；协变量名单与 lock 文件一致（允许 VIF 后再子集，但不得引入 lock 外变量）。
4. 全流程未跑非 UHR 指标目录。

## 6. 非目标（本期不做）

- 改造 `dual_db` 为原生三库引擎；
- 多指标 batch；
- 三库混合效应/个体池化；
- 使用 D01 全量 NHANES 重做纳排（已有 N 库 dabiao）。

## 7. 实现顺序（供 writing-plans）

1. 写 `scripts/prep_hearing_loss_uhr_triple.R` + 跑通 harmonized + `covariate_lock.json`；
2. 写 dual config，`--only-index UHR` smoke（NHANES+CHARLS）；
3. 补 `run/incidence/run_incidence_single.R` + 李玲 config，跑通 UHR；
4. 核对三库协变量一致性与主文表路径。

## 8. 协变量与附表编号（2026-07-30）

**协变量（回归 Model2）**：三库单因素 VIF 交集锁定为 `Age, WBC, Hypertension`（Model1=`Age`）。**不导出**多因素 / 最终 VIF 表。

**附表编号**（相对 MAFLD 模板去掉原 S5/S6 后数字顺延；**S-XX 仍为 RCS，不进数字链**）：

| 编号 | 内容 |
|------|------|
| Table 1/2 | 基线 / 四分位 logistic |
| S1–S4 | 插补、正态、单因素、单因素 VIF |
| S5–S6 | 指标~实验室关联、中介 |
| S7–S8 | NHANES 不加权敏感性（基线/logistic） |
| S-XX | RCS 分组 logistic |
| Fig1–3 / S1–S3 | Flowchart、RCS、亚组；ROC、箱线、中介路径 |
