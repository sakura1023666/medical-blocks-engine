# NHANES 单库 CRM × 孟德尔随机化（Han 2025 JAHA）设计规格

> 状态：待用户确认
> 文献：Han et al. 2025 *JAHA* e038723（`adversarial_lit_reading/papers/双库发病孟德尔.pdf`）
> 范围：**仅 NHANES（Sample 2）+ 两样本 MR**；CHARLS（Sample 1）明确跳过
> 方案：薄编排 + 复用 `Blocks/57_*` + 缺口新建 `Blocks/70_crm_nhanes_pub`

## 0. 已确认决策

| 项                             | 选择                                                                                                                               |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| 主数据                         | `G:/02block_result/14_CRM/comorbid_Mendelia_randomization_40145269/data/nhanes/NHANES_文献_0722.RData`（对象 `df`，40959×83） |
| 死亡数据                       | 同目录`nhanes-死亡.Rdata`（对象 `combined_data`）                                                                              |
| 与 57 关系                     | **A**：pipeline `source` 复用，不改动 57；缺口新建 70+                                                                     |
| 图表范围                       | **A**：NHANES 专属 + MR 全套；CHARLS 专属标注跳过                                                                            |
| Batch 粒度                     | **A**：按分析任务并行（`obs_main` / `obs_strata` / `mr_cvd                                                               |
| 飞书                           | **A**：对齐 IPW，写 base `RBjfb2iwmamW14s4WhKcS7kwnie`；进程内临时覆盖 token，不改写 `.env.feishu`                       |
| `mirror_pub_outputs_to_root` | **TRUE**                                                                                                                     |
| R 运行时                       | `"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`                                                                           |
| 孟德尔代码/数据                | 优先从`E:/孟德尔` 与现有 `Data/smoke/GWAS_*.csv` 调用；缺则按 `0代码` 流程补齐                                               |
| 不动旧项目                     | 不修改`Blocks/01–69`、既有 `run/dual_incidence_mr` 等已交付物                                                                 |

## 1. 研究问题（本套路）

在 NHANES 中年及以上人群中：

1. SUA / 高尿酸 / 痛风与 CRM 条件（CVD、CKD、糖尿病计数）的横断面关联（加权有序 logistic）；
2. 在不同 CRM 负担下，SUA / 高尿酸 / 痛风与全因死亡的关联（加权 Cox、KM、RCS）；
3. 用两样本 MR 评估 SUA → CVD / CKD / Diabetes 的因果效应（IVW + 敏感性）。

## 2. 数据流

```
NHANES_文献_0722.RData (df)
        +
nhanes-死亡.Rdata (combined_data: seqn, eligstat, mortstat, permth_int, …)
        ↓  SEQN/seqn 左连接
入排过滤（年龄、关键变量缺失、CRM 定义可用性等，对齐 Figure S2）
        ↓
派生变量：
  SUA, hyperuricemia, gout, gout×SUA 控制状态,
  CRM_count (0–3), CVD/CKD/Diabetes,
  survey weight / SDMVSTRA / SDMVPSU,
  futime (permth_int), fustatus (mortstat)
        ↓
观察端（survey 加权）          MR 端（GWAS summary，与观察队列解耦）
```

**硬约束**

- 块内禁止 `data_source` 切换；由 pipeline 写入 `ctx$data$*`。
- 共享层只做合并/派生/checkpoint；插补与极值策略若需要，放在各观察 worker 内（与发病 batch v5 一致精神）。
- Windows 路径在 R 中使用 `G:/...`；WSL 侧等价 `/mnt/g/...`。

## 3. 产出清单（NHANES + MR）

| 原文                | 本套路                       | 实现                                            |
| ------------------- | ---------------------------- | ----------------------------------------------- |
| Figure S2           | 入排流程图                   | `70` flowchart                                |
| Table S4            | NHANES 加权基线              | `70` baseline 加权                            |
| Table 2             | 加权有序 logistic OR         | 复用`crm_nhanes_weighted`（加深发表格式）     |
| Table 4             | 加权 Cox HR（按 CRM 分层）   | 复用`crm_cox_mortality` + `crm_gout_strata` |
| Figure 1（NHANES）  | KM 全因死亡                  | `70` KM pub                                   |
| Figure 3            | SUA→死亡 RCS（按 CRM）      | 复用`crm_rcs_sua`（加深出图）                 |
| Table S6/S9/S11 等  | NHANES 补充/亚组             | `obs_strata` worker                           |
| Figure S3 + Table 5 | MR 框架 + 多方法估计         | 复用 57 MR 链                                   |
| Figures S4–S15     | scatter/forest/LOO/funnel 等 | 57 +`E:/孟德尔` 图模板补齐                    |
| Table S1–S2        | IV SNP                       | `mr_snp_screen`                               |

**明确跳过（CHARLS）**：Table 1/3、Figure 2、Table S3/S5/S7/S8/S10 等 → 决策树与 README 标注「单库跳过」，不伪造 CHARLS 结果。

## 4. 架构

### 4.1 目录落点（仅新增）

| 类型     | 路径                                                                                             |
| -------- | ------------------------------------------------------------------------------------------------ |
| Config   | `configs/templates/config_crm_nhanes_mr.template.R`、`config_crm_nhanes_mr_batch.template.R` |
| Run      | `run/crm_nhanes_mr/run_crm_nhanes_mr.R`、`*_batch.R`、`*_batch_worker.R`                   |
| Runner   | `R/crm_nhanes_mr_batch_runner.R`                                                               |
| 决策树   | `Decisiontree/decision_tree_crm_nhanes_mr.md`                                                  |
| 复用块   | `Blocks/57_dual_incidence_mr_full/*`（只读 `source`）                                        |
| 缺口块   | `Blocks/70_crm_nhanes_pub/`（01 合并派生、02 flowchart、03 baseline、04 KM、05 pub 对齐）      |
| 飞书建表 | `run/feishu/run_feishu_setup_crm_nhanes_mr_tables.R`                                           |
| 输出     | `Output/CRM_NHANES_MR/`（含 step 子目录 + 根 `Tables`/`Figures`）                          |

`71+` 仅在实现中证实 57/70 仍不够时再开，不预先膨胀。

### 4.2 三层 batch（任务并行）

```
共享层（1 次）
  load + merge 死亡
  → data_clean
  → crm_nhanes_derive（入排 + 暴露/CRM/权重/随访派生）
  → checkpoint _shared

Worker 并行（processx / system2）
  obs_main     加权 baseline / ordinal / Cox / RCS / KM（主文 NHANES；不含痛风分层）
  obs_strata   痛风分层（gout strata）+ 年龄/性别/BMI 亚组补充表（S6/S9/S11）
  mr_cvd       SNP screen → IVW → Egger/PRESSO → pleiotropy → sensitivity + 图
  mr_ckd       同上
  mr_diabetes  同上

汇总层
  Batch_summary_all_tasks.csv
  → 飞书 Sheet1 upsert；各 worker 已推 Sheet2/3
```

CLI：`--shared-only` / `--only-task obs_main,mr_cvd` / `--workers N`。

### 4.3 Pipeline 块顺序（单次 / obs_main）

```
data_clean
→ crm_nhanes_derive
→ crm_nhanes_flowchart
→ crm_nhanes_baseline_weighted
→ crm_nhanes_weighted          # 57
→ crm_cox_mortality            # 57
→ crm_rcs_sua                  # 57
→ crm_nhanes_km_pub
→ crm_nhanes_pub_align
```

`obs_strata` worker：`crm_gout_strata`（57）+ 亚组补充表块。

MR worker：

```
mr_snp_screen → mr_twosample → mr_egger_presso → mr_pleiotropy → mr_sensitivity
```

### 4.4 飞书

- Base：`RBjfb2iwmamW14s4WhKcS7kwnie`
- 建表脚本幂等创建：项目汇总 / 成功任务 / 失败任务（字段对齐现有三表 schema）
- 只读 `.env.feishu` 的 `FEISHU_APP_ID` / `FEISHU_APP_SECRET`；`Sys.setenv(FEISHU_BITABLE_APP_TOKEN=...)` 仅进程内
- Config 固定：`disease_label="14_CRM_NHANES_MR"`、`protocol_label="crm_nhanes_mr"`、`project_id="14_crm_nhanes_mr_038723"`、`workplan_code` 在飞书工作计划表中取下一空号后回填（默认候选 `B30`，以表内实号为准）
- upsert 去重：Sheet2/3 = 项目编号+任务名；Sheet1 = 疾病标签

### 4.5 运行时与依赖

- R：Windows R-4.5.1 `Rscript.exe`；缺包装到该 R 库
- Python：MR-PRESSO 等走既有 ML/MR 流水线 Python 环境；缺包自行安装
- 孟德尔：算法与辅助脚本从 `E:/孟德尔`（`0代码/`、`MR/`）调用，禁止在块内重写一套无关实现

## 5. 错误处理与质量门

- 各新块实现 `pause_point`（`pause_enable` 可关便于 batch）
- Worker 结束写 `_batch_status.json`，失败文件夹标【失败】
- 禁止静默 `return(ctx)` 吞掉主分析失败
- CHARLS 产出不得用 NHANES 数据冒充

## 6. 非目标

- 不跑 CHARLS 队列、不生成 CHARLS 专属表/图
- 不修改 `Blocks/57_*` 源文件与既有 dual_incidence_mr 交付
- 不把 App Secret 写入任何 `.R` 或提交 Git
- 不在本阶段做对抗式文献阅读训练（除非用户另开任务）

## 7. 验收标准

1. `Rscript run/crm_nhanes_mr/run_crm_nhanes_mr_batch.R --shared-only` 成功写出共享 checkpoint
2. `--only-task obs_main` 产出 Table2/4、Figure1(NHANES)、Figure3、Table S4、Figure S2
3. `--only-task mr_cvd,mr_ckd,mr_diabetes` 产出 Table5 + S1–S2 + S4–S15 对应图
4. 根目录 `Tables/`、`Figures/` 有镜像副本
5. 飞书三表可 upsert；工作计划 base 为 `RBjfb...`
6. 决策树文件存在且 block↔表图映射完整
7. 回归：既有 57 / 其他 01–69 项目文件未被改动

## 8. 实现顺序（进入 writing-plans 后细化）

1. 数据探查（列名、CRM/SUA/权重/死亡合并键）
2. `70_crm_nhanes_pub` 派生 + flowchart + baseline + KM
3. Config/run/runner + 注册 57+70 到 `pipeline_runner`
4. 加深 57 调用侧的发表格式（通过 config/包装，不改 57 文件；若必须改行为则在 70 包一层）
5. Batch 并行 + 飞书建表/推送
6. MR 图模板对接 `E:/孟德尔`
7. 冒烟与全量验收
