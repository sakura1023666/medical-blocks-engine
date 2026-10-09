### Task 5: 新建 Block `diagnostic_vs_fracture`

**Files:**
- Create: `Blocks/75_osteo_dxa_qct/02block_diagnostic_vs_fracture.R`
- Modify: `tests/test_osteo_dxa_qct_blocks.R`

**Interfaces:**
- Consumes: `Vertebral_fracture`；`QCT_OP`/`DXA_OP` 或由 cat==`op_level` 派生；连续 `QCT_vBMD`, `DXA_T_min`
- Config: `config$diagnostic_vs_fracture = list(enable=TRUE, strata=c("Nathan_bin","AAC","BMI_bin"), strata_supplemental=c("Age_bin"), export_roc=TRUE, export_sens_bar=TRUE)`
- Produces: Table3 overall；Table4 stratified；Figure4 ROC（双曲线）；Figure5 分层 Sens；可选 Figure S3 Age；`ctx$results$diagnostic_vs_fracture`
- register_block: `"diagnostic_vs_fracture"`

- [ ] **Step 1: 单测 — 已知真值向量的 sens/AUC 有限**

```r
truth <- c(rep(1L, 10), rep(0L, 10))
score_good <- c(rnorm(10, 2), rnorm(10, 0))
auc <- .osteo75_auc_continuous(truth, score_good)
stopifnot(auc$auc > 0.5)
```

- [ ] **Step 2: 实现 block**

- 分类阳性：`cat == op_level`（默认 2）  
- ROC：`pROC::roc(fracture ~ score, direction = "<")` 对 vBMD（越低越病）与 T-score（越低越病）均 `direction="<"`  
- 分层行：每层 n、n_frac、DXA sens、QCT sens、Δsens  
- 脚注写清分母

- [ ] **Step 3: Run 单测 Expected PASS**

---

