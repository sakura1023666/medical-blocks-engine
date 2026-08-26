### Task 5: `threshold_logistic` 块

**Files:**
- Create: `Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R`
- Modify: `R/pipeline_runner.R`

**Interfaces:**
- Consumes: 锁定协变量 + 连续暴露；`rcs` 或分段搜索
- Produces: `Tables/Table_Threshold_logistic_*.csv`；`Figures/Figure_Threshold_*.pdf`（profile 文献版）

- [ ] **Step 1: 实现最小可用版本**

对连续 index：在分位数网格上拟合两段 logistic（或 `segmented`/`chngpt` 若已装），输出阈值点、阈值下/上 OR、P；图为平滑曲线+竖线阈值（对标论文 1 Figure 3 / Table 4）。

```r
register_block("threshold_logistic", block_threshold_logistic,
               "发病侧 threshold/piecewise logistic 表图")
```

缺包则 `install.packages` 到 R-4.5.1 library。

- [ ] **Step 2: 单指标冒烟**（在 Task 8 通跑时验收）

---
