# 发表质控 — 胆结石碎石成功列线图

- **日期**: 2026-09-30  
- **项目根**: `G:/02block_result/45_Gallstone/Nomogram_`  
- **套路**: 发病地基 + 列线图后缀（`decision_tree_gallstone_nomogram.md`）  
- **范围**: 全部 `by_index/【success】*`（10 个连续特征单元）；failed=0  
- **总评**: **WARN**

## 审阅对象

将审 success：Age, diameter_cm, volume_cm3, ct_min, ct_max, pct_lt40, pct_40_80, pct_gt80, energy_j, shots  
失败单元：0（不审）

## Layer A — 结构

| 检查 | 结果 |
|---|---|
| Batch 10/10 success | PASS（`Tables/Batch_summary_all_units.csv`） |
| 各 success 有 `summary_results/` | PASS |
| Figures 四目录（抽查 Age） | PASS：pdf/png/tiff/image_information 均有 |
| 0 字节 TIFF | PASS（抽查未见） |
| 根目录平铺 Figure*.pdf | WARN：`_shared/Figures/` 与项目根仍有平铺命名；summary_results 内已四目录 |
| Fig 编号与文献对齐 | **WARN**：finalize 顺延后出现重复编号并存（如 Age 下同时有 `Figure 2. Associations` 与 `Figure 2. LASSO`；`Figure 4/5/6` 多套命名）。预测套图（LASSO/列线图/ROC/DCA/CIC）与关联套图（Associations/RCS）混在同一 success 目录，编号未按文献 Fig1–9 锁定 |

## Layer B — 交叉数字

| 检查 | 证据 | 结果 |
|---|---|---|
| n=273 | Fig1 / ingest 日志 | PASS |
| 7:3 = 190 / 83 | `Methods_split_denominator_note.txt` | PASS |
| Table1 / Table2 已落盘 | `Tables/` | PASS |
| AUC train / val | `Table_AUC_train_val_boot.csv`：train≈1.000，val≈0.997 | **WARN**：接近完全分离/过拟合，临床解释需谨慎 |
| LASSO one-SE 入选 | `Table_LASSO_selected_lambda1se.csv`（dummy 形如 pct_lt40/pct_gt80/shape/color/stone_type） | PASS 有表；WARN 多因素 CI 不稳定（分离） |

## Layer C — 逻辑

| 点 | 结论 |
|---|---|
| 外验→bootstrap | 已按用户确认落地（Fig7–9 第三面板） | PASS |
| 关联段全连续特征并行 | 10 unit 均出 Associations + RCS + Subgroup | PASS |
| 预测段只应一套全局图 | 却被复制进每个 success 目录且与 unit 图编号冲突 | WARN |
| 小样本 n=273 + 分类哑变量 | 易分离；AUC≈1 符合该风险 | WARN |

## 建议返工（状态更新 2026-09-30）

1. ~~预测套图只留一套~~ → **已做**：`by_index/【success】NOMOGRAM/`；各特征 unit 仅 Fig2/3/S  
2. ~~锁定文献图号~~ → **已做**：`pub$renumber=FALSE` + `relock_figures_lit_numbering.R`  
3. 对分离：Firth / 减少哑变量水平 / 报告 unstable CI 脚注（仍建议）

## 结论（更新）

流水线全量跑通；图号重锁后结构 **PASS（图号）**，过拟合/分离信号仍为 **WARN**。
