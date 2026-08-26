# IBD 双库轨迹预后（JLCM）设计

**日期**: 2026-08-25  
**课题路径**: `/mnt/g/02block_result/28_IBD/Prognosis_Trajectory_38882552`  
**方案**: 方案 1 — 数据预处理 + 轨迹预后 batch 配置，少改引擎  
**状态**: 待用户审阅后进入 implementation plan

---

## 1. 目标与范围

在 IBD 背景人群上，对 eICU + MIMIC 各自独立跑 **28 天院内死亡** 的轨迹预后（JLCM）分析；暴露为双库共同可用复合指标全集（`dual_safe`，约 60 个），按指标 `by_index` 并行。

**本课题专属例外（不改其他课题默认）：**

| 例外 | 本课题 | 其他课题 |
|------|--------|----------|
| Table 1 / Gate A 列交集 | **关闭**：两库各自保留本库变量 | 双库预后模板默认仍对齐 |
| `disease_vars` | 仅 `IBD_subtype`（纳排键） | 按各病种审阅；CRP 等是否排除由课题定 |

**不在范围**：发病分析、竞争风险、跨库迁移验证、把本例外写进全局引擎默认。

---

## 2. 已确认口径

| 项 | 设定 |
|----|------|
| 背景人群 | IBD（`IBD_subtype ∈ {CD, UC}`）；非 IBD 一开始删除 |
| 结局 | 28 天院内死亡 → `survival_28d` + `survival_time_28d` |
| 指标 | `index_group = "dual_safe"`（全量，非 10 个） |
| 队列 | eICU + MIMIC，各自独立拟合 JLCM |
| Table 1 | 不跑 `dual_db_column_harmonize`（关 Gate A） |
| 疾病硬排除 | `analysis_exclusion$disease_vars = c("IBD_subtype")`；CRP/HSCRP/Albumin **保留** |
| 样本量 | 全量 IBD（不做 `subsample_n`） |
| 年龄亚组 | `age_cutoff = 65` 二分类（无更强 IBD-ICU 文献时用默认；config 注释标明） |
| 模板 | `configs/templates/config_trajectory_prognosis_batch.template.R` |

粗算纳排后：MIMIC ≈ 211（28d 死亡 ≈ 34，~16%）；eICU ≈ 196（推导后 ≈ 9，~4.6%——事件偏少，JLCM/dynpred 可能不稳，日志需标明）。

---

## 3. 架构

```text
prepare_ibd_surv28_data.R
  dabiao + 预后 CSV → 筛 IBD → 合并 28d 院内死亡 → D04_rt_IBD_surv28.RData (rt)
       ↓
config_trajectory_prognosis_ibd_batch.R
       ↓
run_trajectory_prognosis_apri_batch.R
  共享层（每库一次）:
    data_clean → column_mapping → index → analysis_exclusion → trajectory_calc_28d_index
  指标层（dual_safe × by_index 并行）:
    imputation → baseline_binary → UV → VIF screen → MV → resolve → VIF final
    → JLCM → baseline_by_class → plot → KM → dynpred → … → chisq
```

**刻意不挂**：`dual_db_column_harmonize` / Gate A（本课题 Table 1 不统一两库列）。

复用现有：`R/trajectory_prognosis_batch_runner.R`、`run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R`（及 worker）。不新建第二套 batch 引擎。

---

## 4. 数据准备

脚本：`run/trajectory_prognosis/prepare_ibd_surv28_data.R`

输入（现有）：

- `data/mimic/D04_dabiao_MIMIC.RData`（`dabiao`）+ `mimic预后数据-all.csv`
- `data/eicu/D04_dabiao_eICU.RData`（`dabiao`）+ `EICU预后数据-all.csv`
- 实验室：eICU 12 个 UC/CD 分片 CSV；MIMIC `mimic-实验室指标-all-1~30天.csv`

步骤（每库）：

1. 读 dabiao，过滤 `IBD_subtype %in% c("CD", "UC")`。
2. 合并预后：
   - **MIMIC**：`death_within_hosp_28days` → `survival_28d`；`survival_time_28d = pmin(hosp_survival_day, 28)`（事件/截尾规则与字段一致；缺失需剔除或记入 attrition）。
   - **eICU**：`hospdischargestatus == "Expired"` 且 `hosplosday <= 28` → 事件 1；否则截尾；`survival_time_28d = pmin(hosplosday, 28)`。
3. 分析 ID：`subject_id <- ID`；保留 `IBD_subtype`（供纳排记录，进 `disease_vars` 后不进模型）。
4. 写出 `data/{eicu,mimic}/D04_rt_IBD_surv28.RData`，对象名 `rt`。
5. 写出 `Data/_column_review.md`（全列保留/排除理由）与纳排摘要（分库 n、排除非 IBD 人数、结局缺失人数）。

`trajectory_calc_28d_index`：`restrict_to_baseline_ids = TRUE`，实验室 ID 列分别为 eICU `patientunitstayid`、MIMIC `subject_id`。

---

## 5. 配置要点

文件：`configs/config_trajectory_prognosis_ibd_batch.R`（可由模板复制后改【必改】项）。

- `project`: `disease = "IBD"`, `disease_code = "28"`, `output_dir` → 课题根。
- `data` / `dual_db.*.rawdata_*`: 指向 `D04_rt_IBD_surv28.RData` / `rt`。
- `survival`: `time_var = "survival_time_28d"`, `event_var = "survival_28d"`。
- `trajectory_batch$index_group = "dual_safe"`；`index_vars = NULL`。
- `pipeline_shared`：含 `analysis_exclusion`，**不含** `dual_db_column_harmonize`。
- `analysis_exclusion`: `disease_vars = c("IBD_subtype")`, `component_scope = "current_transitive"`, 其余与模板铁律一致。
- `analysis_var_policy$dual_db_lock`: 本课题可不依赖 Gate A；若 runner 注入默认 TRUE，以「不跑 Gate A、两库独立 Table1」为准（必要时本 config 显式 `dual_db_lock = FALSE` 仅作用于本课题）。
- `data_clean`: 无 `subsample_n`（或显式关闭）。
- `subgroup$age_cutoff = 65L`；`level_order$Age_Group = c("< 65", "≥ 65")`。
- JLCM：`adaptive_class_cap = TRUE`（n &lt; 1000 → 最多 4 类）；`dual_db_harmonize_survival_covariates` 可保持模板默认（协变量在库内 VIF 后选取；非 Gate A 列对齐）。

---

## 6. 运行命令

```bash
# 仓库根目录
Rscript run/trajectory_prognosis/prepare_ibd_surv28_data.R

Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R \
  --config configs/config_trajectory_prognosis_ibd_batch.R
```

可选：`--only-index NLR --workers 1` 单指标冒烟；通过后再全量 `dual_safe`。

---

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| eICU 28d 院内死亡事件很少（~9） | 日志标明；失败指标记入 batch status，不拖死全批 |
| 小样本 JLCM 不稳定 | `adaptive_class_cap`；`stop_on_ng*_fail` 按模板；允许单指标失败跳过策略与现有 runner 一致 |
| 实验室分片命名杂乱 | `lab_sources$files = list.files(..., pattern = "实验室.*\\.csv$")` |
| 误改全局默认 | 例外只写进 IBD config + 本 spec；不改 survival/trajectory 模板默认 Gate A |

---

## 8. 验收清单

- [ ] 两库 `D04_rt_IBD_surv28.RData` 仅含 IBD，且有 `survival_28d` / `survival_time_28d` / `subject_id`
- [ ] `Data/_column_review.md` 存在；`disease_vars` 仅 `IBD_subtype`
- [ ] 共享层 checkpoint 无 Gate A / `dual_db_column_harmonize` 产物要求
- [ ] Table 1：eICU 与 MIMIC 列可以不一致（本课题预期）
- [ ] `by_index` 对 `dual_safe` 派发；产出在课题 `by_index/` 与汇总目录
- [ ] 其他课题模板 / `dual_db_lock` 默认未因本课题被改掉

---

## 9. 实现交付物（进入 plan 后）

1. `run/trajectory_prognosis/prepare_ibd_surv28_data.R`
2. `configs/config_trajectory_prognosis_ibd_batch.R`
3. 课题目录下 `_column_review.md` / 纳排摘要（由准备脚本写出）
4. 冒烟跑 1 指标 → 全量并行（用户确认后执行）
