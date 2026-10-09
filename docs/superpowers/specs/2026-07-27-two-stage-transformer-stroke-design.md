# 缺血性脑卒中两阶段 Transformer 双轨复现 — 设计规格

> 状态：待用户确认  
> 文献：Yang et al. 2025 *Precision Clinical Medicine* pbaf003（`adversarial_lit_reading/papers/两阶段transfomer.pdf`）  
> 方法迁移：`缺血性脑卒中两阶段Transformer双轨复现方案.pdf`  
> 方案：**方案 1** — 薄编排 + 复用 01–04 清洗/基线 + 缺口新建 `Blocks/71_two_stage_transformer_stroke`；`code/` 整理进 `python/`  
> 范围：A1 + A2 + B + 统计/ML/DL 基线 + 消融 + 校准/DCA/SHAP（对齐复现方案 E1–E12）

## 0. 已确认决策

| 项 | 选择 |
| ---- | ---- |
| 主结局 | **院内死亡**（存活出院=0，院内死亡=1） |
| 主数据 | `G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421/data`（WSL：`/mnt/g/...`） |
| 数据文件 | 基线 `D01_baseline_MIMIC_ICU_frist_0626 (1).RData`（ICU 池）；**卒中名单 `dabiao.csv`（必需内连接）**；长表 `mimic-实验室指标-all-1~30天.csv`；预后宽表 `mimic预后数据-all.csv`；`mimic/12_*.RData` 仅作特征字典参考，**不作为指标 batch 单位** |
| 并行模式 | **任务并行**（共享层 1 次 + worker 按任务派发）；**不做**预后式多指标 batch |
| 三轨范围 | **完整双轨**：A1 公开仓库迁移 + A2 修正单阶段 + B 两阶段 + 基线 + 消融 + 解释 |
| Blocks 前缀 | **`71_two_stage_transformer_stroke`**（接在 70 后） |
| `mirror_pub_outputs_to_root` | **FALSE**（表/图留在 step 子目录，不镜像到 Output 根） |
| 内部分割 | 患者级随机 **7:2:1**（对齐原文 Methods） |
| 时间外 | 若入院年份可用则跑；否则决策树标注跳过原因 |
| 地理外推 | 无第二卒中中心时：**代码必须有**；默认用**合成随机数据** smoke；结果标 `synthetic`，不进正式主文结论 |
| Python 落点 | `code/` → 整理为 `python/two_stage_transformer/` 包 + `python/block_two_stage_transformer.py`；根 `code/` 保留只读指针/说明，流水线只调 `python/` |
| `tst_cohort` | **R 实现**（纳排、院内死亡、时间零点）；Python 不碰队列定义 |
| R 运行时 | `"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"` |
| Python 运行时 | `C:/ProgramData/anaconda3/python.exe`（经 `R/python_literature.R`） |
| 飞书 | base `RBjfb2iwmamW14s4WhKcS7kwnie`；任务名 upsert；进程内可临时覆盖 token，不改写 `.env.feishu` 密钥正文习惯对齐 CRM |
| 不动旧项目 | 不修改 `Blocks/01–70`、`67_transformer_shortseq_full`、既有 `run/transformer_shortseq` 等已交付物；仅只读 `source` |

## 1. 研究问题（本套路）

以 MIMIC 急性缺血性脑卒中住院患者入院后连续临床信息为输入，在 landmark 24/48/72/96/120 小时建立动态预测模型，评价：

1. A1：作者公开实现迁移到卒中数据后的可运行性与性能；
2. A2：统一规范管线下的单阶段 Transformer 公平基线；
3. B：小时级 + 天级两阶段 Transformer 的增量价值；
4. 相对 Logistic / XGBoost / MLP / LSTM 等基线的区分度、校准与临床净获益；
5. 内部 7:2:1、可选时间外、以及（合成）地理外推代码路径的可复现性。

## 2. 数据流

```
基线 RData + 实验室长表 CSV (+ 预后宽表辅助)
        ↓ 共享层（R，1 次）
data_clean → column_mapping → tst_cohort（纳排 / 院内死亡 / 时间零点）
        → tst_split（7:2:1 + 可选时间外；**先划分**）
        → imputation（**fit_on=train**；val∪test 仅 mice ignore 套用，禁止 holdout 各自重拟合）
        → tst_timeseries（小时网格、单位、审计表；静态广播用插补后基线）
        → baseline_binary → tst_landmark（5 个可预测队列 ID）
        （标准化/特征选择参数亦仅训练集拟合）
        → checkpoint _shared
        ↓ 任务 worker（并行）
A1 / A2 / B / baselines / ablation / calibrate_dca / shap
        / temporal_holdout / external_synthetic
        ↓
tst_literature_validate → tst_pub_export
```

**硬约束**

- 块内禁止 `data_source` 切换；由 pipeline 写入 `ctx$data$*`。
- 患者级划分必须先于插补/标准化/特征选择；验证/测试只应用训练集参数。
- Landmark：预测时点前已发生结局者不得进入该时点队列；禁止用结局后缺失模式泄漏信息。
- A2 与 B 共享同一规范管线、同一划分、相近调参预算；A1 单独命名为「公开代码实现」，不与规范管线结果混名。
- 合成外推：`is_synthetic=TRUE`，输出路径含 `synthetic`，飞书/文献对照表不得当作真实外推阳性结果。

## 3. R / Python 分工

| 层 | 语言 | 内容 |
| ---- | ---- | ---- |
| 队列与表格前端 | **R** | `tst_cohort`、baseline Table1、流程图、特征审计、Landmark ID、划分种子落盘 |
| 时序张量与深度学习 | **Python** | 读 R 导出的 ID/划分/长表 → prepare / train A1·A2·B / baselines / ablation / SHAP / synthetic external |
| 发表汇总 | **R** | 读 Python 指标 CSV → 校准/DCA（R 或调 Python）→ literature_validate → pub_export |

### 3.1 Python 目录（由 `code/` 整理）

```
python/
  block_two_stage_transformer.py          # 统一 --mode CLI
  two_stage_transformer/
    __init__.py
    model.py              # ← code/model_5day.py
    dataloader.py         # ← code/custom_dataloader_5day.py
    focal.py              # ← code/focalloss.py
    prepare.py            # ← code/prepare_data.py + split
    train.py              # ← code/main_5day.py 扩展（A1/A2/B）
    eval.py               # ← plot_roc + metrics
    shap_plot.py          # ← code/shap_5day.py
    baselines.py          # Logistic/XGB/MLP/LSTM
    synthetic_external.py # 随机合成外推队列
  requirements-two-stage-transformer.txt
code/
  README.md               # 指向 python/；原文件可保留只读，流水线不直接调用
```

**拟 `--mode`**：`tst_prepare`、`tst_train_a1`、`tst_train_a2`、`tst_train_b`、`tst_baselines`、`tst_ablation`、`tst_calibrate`、`tst_shap`、`tst_external_synthetic`、`tst_external`。

R 调用：扩展使用 `literature_python_script(root, name="block_two_stage_transformer.py")` + `run_literature_python`；**不重写**既有 `block_literature_extensions.py` 的其他 mode。

## 4. Blocks 清单（71）

| 文件 | register_block | 语言侧重 | 职责 |
| ---- | ---- | ---- | ---- |
| `01block_tst_cohort.R` | `tst_cohort` | R | 纳排、院内死亡、时间零点 |
| `02block_tst_timeseries.R` | `tst_timeseries` | R→导出 | 长表小时网格、单位/异常、覆盖率审计 |
| `03block_tst_landmark.R` | `tst_landmark` | R | 24/48/72/96/120h 队列 |
| `04block_tst_split.R` | `tst_split` | R | 7:2:1 + 可选时间外；防泄漏参数 |
| `05block_tst_repo_a1.R` | `tst_repo_a1` | R 调 Py | A1 仓库格式适配 + 训练 |
| `06block_tst_train_eval.R` | `tst_train_eval` | R 调 Py | A2/B/基线/消融 |
| `07block_tst_calibration_dca.R` | `tst_calibration_dca` | R/Py | 校准 + DCA |
| `08block_tst_shap.R` | `tst_shap` | R 调 Py | 全局/分日/小时热图 |
| `09block_tst_external.R` | `tst_external` | R 调 Py | 地理外推；默认合成随机数据 |
| `10block_tst_literature_validate.R` | `tst_literature_validate` | R | 对照原文目标与交付清单 |
| `11block_tst_pub_export.R` | `tst_pub_export` | R | 发表级导出（不 mirror 根目录） |

共享前端复用：`data_clean`、`column_mapping`、`imputation`、`baseline_binary`（只读 source）。

## 5. 目录落点（仅新增）

| 类型 | 路径 |
| ---- | ---- |
| Config | `configs/templates/config_two_stage_transformer_stroke.template.R`、`config_two_stage_transformer_stroke_task_parallel.template.R` |
| Run | `run/two_stage_transformer_stroke/run_two_stage_transformer_stroke.R`、`*_task_parallel.R`、`*_worker.R` |
| Runner | `R/tst_stroke_task_runner.R` |
| 决策树 | `Decisiontree/decision_tree_two_stage_transformer_stroke.md` |
| 缺口块 | `Blocks/71_two_stage_transformer_stroke/` |
| Python | `python/block_two_stage_transformer.py`、`python/two_stage_transformer/` |
| 飞书建表 | `run/feishu/run_feishu_setup_tst_stroke_tables.R` |
| 输出 | `Output/TwoStage_Transformer_Stroke/`（step 子目录；**不** mirror 到根 Tables/Figures） |
| 合成外推数据 | `Data/smoke/tst_stroke_synthetic_external/`（或 Output 下 interim，config 指定） |

## 6. 任务并行（非指标 batch）

```
共享层（1 次）
  clean → map → impute → baseline → cohort → timeseries → landmark → split
  → checkpoint _shared

Worker（processx / system2 wait=FALSE）
  按 unit = landmark × 模型族（及独立任务）派发，例如：
    L24_B_twostage, L48_B_twostage, …, L120_B_twostage
    L72_A2_single, L72_A1_repo
    L72_logistic, L72_xgb, L72_mlp, L72_lstm
    L72_ablation_mask, L72_ablation_structure
    temporal_holdout, external_synthetic
  每 worker：复制 shared ck → 调对应 blocks / Python mode → 状态 JSON → 飞书 upsert

汇总层（1 次）
  合并 metrics → literature_validate → pub_export → Sheet1 汇总
```

命令风格对齐现有 batch：

```bash
R="/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
"$R" run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R
"$R" run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R --shared-only
"$R" run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R --only-unit L72_B_twostage,external_synthetic
```

## 7. 产出清单（不少一张）

| 来源 | 本套路产出 | 实现 |
| ---- | ---- | ---- |
| 原文 Fig.1 | 入排流程图 | R cohort + flowchart |
| 原文 Table1 风格 | 存活 vs 院内死亡基线表 | `baseline_binary` |
| 原文 Table 性能（Day1–5） | Landmark AUROC/AUPRC/Accuracy 等 | `tst_train_eval` |
| 原文模型对比 | A1/A2/B vs Logistic/XGB/MLP/LSTM | E2–E7 |
| 原文 Fig.4 / SHAP | 分日/小时热图 | `tst_shap` |
| 原文 External | 地理外推表/图 | `tst_external` + **synthetic** 标注 |
| 复现方案校准/DCA | 校准曲线、DCA | `tst_calibration_dca` |
| 复现方案消融 E8–E11 | Mask/Δt、特征子集、结构消融 | `tst_train_eval` ablation units |
| 复现方案 E12 | 时间外；医院外无数据则跳过+合成路径 | split + external |
| 文献对照 | `Table_Literature_Validation` | `tst_literature_validate` |

不可比项（脓毒症 eICU 开发 → 卒中 MIMIC 迁移）在决策树与 validation 表中标记【场景迁移 / 证据不足】，禁止把合成外推 AUC 写成真实外推结论。

## 8. 原文外推对照（证据绑定）

- **开发集**：eICU 脓毒症，n=13610；内部 7:2:1（Methods, Data preprocessing）。  
- **外推 1**：中国三甲 ICU 脓毒症 2021–2023，n=417，Accuracy≈81.8%，AUC=0.73（Results, External validation）。  
- **外推 2**：MIMIC-IV-3.1 脓毒症（ICD-9 99591/99592/78552），AUC=0.84（同上）。  
- 本套路主库已是 MIMIC 卒中，无法 1:1 复刻「eICU→MIMIC」；用内部协议对齐 + 合成地理外推保代码完整。

## 9. 风险与质量控制

| 风险 | 控制 |
| ---- | ---- |
| 未来信息泄漏 | Landmark 截断 + 变量可用时间字典 + day_mask |
| 预处理泄漏 | 先患者级 split，仅训练集拟合 |
| A1/A2/B 不公平比较 | A2↔B 共享管线与预算；A1 单独命名 |
| 合成外推被误用 | 路径/表头/`is_synthetic`/飞书备注强制标注 |
| 改旧项目 | 禁止写入 01–70 与既有 run；缺口只进 71 + 新 run/config |

## 10. 非目标（本规格明确不做）

- 不以 `mimic/12_*.RData` 复合指标为 batch 并行单位。  
- 不把合成外推结果写入正式论文主结论。  
- 不修改 `Blocks/67_*` 或覆盖 `python/block_literature_extensions.py` 既有 mode。  
- 不默认 `mirror_pub_outputs_to_root = TRUE`。

## 11. 实施顺序（实现阶段，本规格批准后）

1. 写 decision tree + config templates + 薄 run 入口。  
2. 迁移 `code/` → `python/two_stage_transformer/` + CLI。  
3. 实现 71 共享层 R blocks（cohort→split）。  
4. 实现 train/eval/校准/SHAP/external_synthetic。  
5. 任务 runner + 飞书 setup。  
6. smoke：`--shared-only` + `--only-unit L72_B_twostage,external_synthetic`。  
7. 全量任务并行与 literature_validate。
