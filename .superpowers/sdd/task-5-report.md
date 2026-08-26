# Task 5 Report: `threshold_logistic` 块

**Status**: DONE  
**Date**: 2026-08-26  
**Worker**: Task 5 subagent  
**Commits**: none（global constraints / 用户明确禁止）

---

## 1. 执行摘要

已按 TDD 实现发病侧 `threshold_logistic`：连续 index 分位数网格两段 logistic，`segmented` 精修 psi；导出阈值、阈值下/上每单位 OR 与 P、LRT；CSV 表 + PDF（平滑相对 OR 曲线 + 竖线）。`pub_figure$profile == "mimic_inc_prog_sle_aki"` 走文献版 theme（Task 6 getter 尚未存在时块内回退）。`pipeline_block_sources` 已注册；catalog AUTO 已同步。未 git commit。

TDD：先写 `tests/test_threshold_logistic.R`，Windows Rscript 首次失败为 `exists("block_threshold_logistic", mode = "function") is not TRUE`；实现 block + 注册后 PASS。

---

## 2. 交付物

| 项 | 路径 | 说明 |
|----|------|------|
| Block | `Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R` | 新建；`register_block("threshold_logistic", …)` |
| 注册 | `R/pipeline_runner.R` → `pipeline_block_sources` | `threshold_logistic = b("72_.../03block_threshold_logistic.R")`（仅追加一行，未改旧映射） |
| 测试 | `tests/test_threshold_logistic.R` | 假数据阈值/OR/CSV/PDF；非 incidence 跳过；lit profile；注册；真数据 Age 冒烟 |
| Catalog | `docs/Blocks_catalog.md` | `python3 scripts/update_blocks_catalog.py` exit 0；416 blocks；MANUAL §1–§3 未改 |

---

## 3. Block 行为

消费：`ctx$data$imputed`（空则 cleaned/raw）；`incidence$index_var` / `outcome_var`；协变量 `threshold_logistic$covariates` → Model2 → Model1。`study_type` 非 incidence 则跳过。

产出：

- 网格（默认 Q10–Q90，81 点；每段 `min_segment_n=20`）拟合 `y ~ pmin(x,τ) + pmax(x-τ,0) + covs`
- 若已装 `segmented`：以网格 τ（或 RCS `cutoff_value`）为初值精修
- `ctx$results$threshold_logistic`：threshold / or_below / or_above / p_below / p_above / p_lrt / method
- `Tables/Table_Threshold_logistic_<Index>.csv`（立即落盘）+ `export_sci_table` 入队
- `Figures/Figure_Threshold_<Index>.pdf`（经 `.pub_figure_filename` 后空格化，与引擎发表图命名一致）
- lit profile：`theme_classic` + Times + 阈值标注；否则 `theme_bw`

ggplot2 / segmented 已在 R-4.5.1 library，未新装包。

---

## 4. 测试摘要

命令：

```bash
cd /mnt/e/01block/01Block-new-Final
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" tests/test_threshold_logistic.R
```

| 阶段 | 结果 |
|------|------|
| RED | `Error: exists("block_threshold_logistic", mode = "function") is not TRUE` |
| GREEN | `OK test_threshold_logistic`；假数据 method=segmented threshold≈8.79；real-data smoke n=270 events=110 threshold=63（Age 作连续暴露） |

非 incidence 跳过无 CSV；`mimic_inc_prog_sle_aki` 同样落 PDF。

---

## 5. Catalog

- 脚本 exit OK；新 `register_block` id：`threshold_logistic`（416 blocks）
- AUTO 卡片用途行：`threshold_logistic — 发病侧连续 index 的 threshold / piecewise logistic 表+图`
- MANUAL §1/§2/§3 未改（套路 template 属 Task 7）

---

## 6. Concerns / 待后续确认

1. **假数据阈值未钉在 DGP hinge=5**：n=360 噪声下 segmented 落到 ~8.8；测试只要求有限阈值与两侧 OR>0。
2. **真数据冒烟用 Age 当暴露**：指标库尚未进流水线；Task 8 通跑才验收真实 index。
3. **PDF 文件名**：`.pub_figure_filename` 把 `Figure_Threshold_NLR.pdf` 变成 `Figure Threshold NLR.pdf`（去下划线），与 RCS 等发表图一致。
4. **Task 6 `is_pub_profile` 尚无**：块内字符串回退；Task 6 落地后自动走公共 getter。
5. **文献 Figure 3 版式**：当前为相对 OR 曲线 + 竖线 + 标注；更深面板留给 Task 6。
6. **export_sci_table 仅入队**：单测直接调 block 不 flush，xlsx 不一定落盘；CSV 已立即写出。
7. **未改旧课题 config**；未 git commit。

---

## 7. 自检清单

- [x] 失败测试先跑（`block_threshold_logistic` 未定义）
- [x] `register_block("threshold_logistic", …)` + `pipeline_block_sources` 一行
- [x] CSV + PDF；profile 分支不改默认 theme_bw
- [x] 测试 PASS（假数据 + 真数据冒烟）
- [x] catalog 脚本 OK；用途行非分隔线
- [x] 无 git commit
- [x] 本 report 已写入 `.superpowers/sdd/task-5-report.md`
