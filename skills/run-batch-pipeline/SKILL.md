---
name: run-batch-pipeline
description: 为本项目任意流水线（生存/发病单库/发病双库）创建批量多指标版本（config_*_batch.R、batch_runner.R、worker 脚本）。当用户说"做批量"、"跑多指标"、"batch"、"并行"、"100指标"等时使用。详细规范见 SURVIVAL_BATCH_GUIDE.md 附录 A。
---

# 批量多指标流水线构建规范

> 完整文档：`SURVIVAL_BATCH_GUIDE.md`（附录 A 为发病双库规范）  
> 现有实现参考：`run_incidence_dual_batch.R` / `R/incidence_dual_batch_runner.R`

## 三层架构（v5 架构，发病双库）

```
层 A 共享层（每库跑 1 次）
  ┌─ Gate A：column_mapping 后两库列名交集（gate_a_missing_threshold=1.0，不按缺失预删）─┐
  data_clean（不删列, threshold=1.0，由 runner 强制）
  → column_mapping
  → dual_db_column_harmonize（限制到 Gate A 公共列；mapped/cleaned 同步）
  → index（在 ctx$data$mapped 上算指标；行级 NA 保留）
  ↓ checkpoint: mapped + 指标列

层 B 指标层（并行 N 路，每指标独立 Worker 子进程）
  ① 复制 shared ck → 专属目录，删除其他指标列
  ② 过滤当前指标 NA 行（各指标用自己的有效人群，互不影响）
  ③ imputation（MICE；协变量缺失 > imputation_threshold 则删列，默认 0.4）
  ④ 完整分析链（baseline→单变量→VIF→多变量→VIF→logistic→RCS→亚组→中介；**不挂** trim_index_extreme）
  ⑤ 写状态 JSON → 重命名文件夹【成功】/【失败】

层 C 汇总层（跑 1 次）
  汇总所有 _batch_status.json → Batch_summary_all_indices.csv
```

**设计要点（v5 核心）：**

| 阶段 | 管什么 | 不管什么 |
|------|--------|----------|
| **Gate A** | 两库映射后**列名交集**（`gate_a_missing_threshold=1.0`） | 缺失率、能否插补 |
| **共享 index** | 在 `mapped` 上尝试算公式；行有 NA 就留着 | 不插补、不删行 |
| **筛查** | 双库交集 + 每库 `n_valid >= min_valid_per_db` | |
| **Worker imputation** | 该指标子人群内，协变量 `>0.4` 缺失删列 + MICE | 各指标人群独立 |

**数据槽约定（必须一致）：**

```
imputation / index 读取顺序：imputed > mapped > cleaned
harmonize 写：mapped + cleaned（同步）
index 写回后：cleaned <- mapped
批量 helper：incidence_batch_ctx_data(ctx) 统一取主数据框
```

**两个阈值不要混用：**

```r
gate_a_missing_threshold      = 1.0   # harmonize 列名交集
nhanes_imputation_threshold   = 0.40  # per-index worker 插补前删协变量
mimic_imputation_threshold    = 0.40
# 共享层 data_clean 由 runner 强制 threshold = 1.0
```

## 五个核心文件

| 文件 | 模板参考 | 职责 |
|------|----------|------|
| `configs/indices/composite_index_vars.R` | 已有 | 指标名单（4 组：A/B/C/D + dual_safe 子集） |
| `configs/config_*_batch.R` | `config_incidence_dual_batch.R` | 全量 config（index_var=NULL，由 runner patch） |
| `R/*_batch_runner.R` | `incidence_dual_batch_runner.R` | 编排引擎 |
| `run_*_batch.R` | `run_incidence_dual_batch.R` | 主入口（薄脚本） |
| `run_*_batch_worker.R` | `run_incidence_dual_batch_worker.R` | 子进程（独立 R 会话） |

## 构建步骤

### 1. 确认流水线类型

- **预后单库**（`config_survival_sae.R` → `run_survival_sae.R`）：共享层无 `dual_db_column_harmonize`；层 B 用 Cox 分析块
- **发病单库**（`config_incidence_single.R`）：共享层无 harmonize；层 B 用普通 logistic
- **发病双库**（`config_incidence_dual.R`）：共享层有 harmonize + Gate A/B；层 B 两阶段

### 2. 从现有 config 创建 batch config

关键修改：
```r
incidence_batch = list(
  index_vars       = NULL,
  index_group      = "dual_safe",
  gate_a_missing_threshold = 1.0,    # Gate A 列名交集
  min_valid_per_db         = 50L,    # 筛查：每库最少非 NA 样本
  nhanes_imputation_threshold = 0.40,
  mimic_imputation_threshold  = 0.40,
  db_mode          = "both",
  ...
)

# 共享层 pipeline（v5，无 imputation）
pipeline_shared = list(
  blocks = c("data_clean", "column_mapping",
             "dual_db_column_harmonize", "index")
)
```

### 3. patch_config_for_index 必须覆盖的字段

```r
config$incidence$index_var            <- ix
config$logistic$index_var             <- ix
config$nhanes$cutoff_index_var        <- ix
config$prediction$index_vars          <- c(ix)
config$multicollinearity$exclude_vars <- c(base_excl, ix)
```

### 4. Worker 过滤步骤（必须在分析前执行）

```r
incidence_batch_copy_shared_ck(shared_dir, per_index_ck, ix, p_trim = 0)  # 只删 NA
# 发病/预后套路不挂 trim_index_extreme，不做百分位极端值裁剪
```

### 5. 文件夹命名（worker 完成后）

```r
incidence_batch_rename_output_folder(output_base, ix, status)
# 成功：NLR【成功】 / 失败：NLR【失败】
```

## 命令模板

```bash
R="/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"

# 全量（自动推算并行路数）
"$R" run_incidence_dual_batch.R

# 只跑共享层（确认能算多少指标）—— 改代码后须删旧 _shared checkpoint
rm -rf checkpoints/D04_OA_dual_batch/_shared
"$R" run_incidence_dual_batch.R --shared-only

# 冒烟测试
"$R" run_incidence_dual_batch.R --workers 2 --only-index NLR,WPR,HHR --ptrim 0

# 调试单 worker
"$R" run_incidence_dual_batch_worker.R --index NLR --db both --ptrim 0.01
```

## 指标筛查逻辑（v5）

```
1. incidence_batch_resolve_index_vars()     → 候选池（dual_safe / all / 显式列表）
2. incidence_batch_gate_a_from_clean()      → Gate A 列名交集注入 config
3. 共享层 index 在 mapped 上计算
4. incidence_batch_resolve_from_shared_ck() → 双库交集 ∩ 候选
                                              且每库 n_valid >= min_valid_per_db
5. 只派发通过筛查的指标给 worker
```

**db_mode = "both"** 时严格取**交集**（不再降级并集）。若交集为空，检查 index 是否读 `mapped`、Gate A 阈值、min_valid。

Worker 若某库算不出该指标，自动降级 `nhanes_only` / `mimic_only`。

## 常见问题与已知修复

| 问题 | 原因 | 修复 |
|------|------|------|
| 双库交集 0 个指标 | index 读了 `cleaned` 而非 `mapped`；MIMIC 列名未统一 | index 优先读 mapped；harmonize 同步 cleaned |
| 只有 ~5 个 CBC 指标 | Gate A 用 0.4 预删列，交集仅 ~14 列 | `gate_a_missing_threshold = 1.0` |
| worker cutoff 报指标列不存在 | imputation 读 mapped 但指标只在 cleaned | harmonize/index 同步 mapped↔cleaned |
| 共享层改代码后指标数不变 | 跳过已有 `_shared/*/index.rds` | 删除 `_shared` 目录后 `--shared-only` 重跑 |
| Worker 日志为空 | bash nohup 在 Windows R 下失效 | 改用 `processx::process$new()` |

### WSL + Windows R

Windows R → `processx` 派发 worker；Linux/WSL → `system2(..., wait=FALSE)`（勿用 `system("... &")`）。

## 适配不同流水线的关键差异

### 预后（Survival）
- 层 B：`univariate_prognosis → VIF → cox_quartile → km_strata → subgroup_prognosis`
- 无 Gate A/B

### 发病单库（Incidence Single）
- 层 B：`univariate_incidence_binary → VIF → logistic_quartile_glm → …`
- 无 harmonize

### 发病双库（Incidence Dual）
- 见 `SURVIVAL_BATCH_GUIDE.md` 附录 A

## 飞书结果管理表同步

batch 跑完后将指标结果写入飞书多维表格，见 **`.cursor/skills/feishu-result-sync/SKILL.md`**（凭证、文档应用授权、`run_feishu_test.R`、worker 推送）。
