### Task 4: 新建 Block `dxa_qct_agreement`

**Files:**
- Create: `Blocks/75_osteo_dxa_qct/01block_dxa_qct_agreement.R`
- Modify: `tests/test_osteo_dxa_qct_blocks.R`

**Interfaces:**
- Consumes: `ctx$data$imputed %||% ctx$data$cleaned`；列 `QCT_cat`, `DXA_cat_min`, `QCT_vBMD`, `DXA_T_min`
- Config: `config$dxa_qct_agreement = list(enable=TRUE, qct_cat=, dxa_cat=, qct_continuous=, dxa_continuous=, op_level=2L, bland_zscore=TRUE)`
- Produces: Table「DXA-QCT agreement」xlsx；Figure「Figure 3. DXA vs QCT agreement」；`ctx$results$dxa_qct_agreement`
- register_block: `"dxa_qct_agreement"`

- [ ] **Step 1: 扩展单测 — 合成 data 上 κ 与 n**

```r
# stub register_block if needed
if (!exists("register_block", mode = "function"))
  register_block <- function(...) invisible(NULL)
# 构造 6 行 mini ctx 调用内部函数（导出 .dqa75_compute）
```

- [ ] **Step 2: 实现 block**

文件头注释按引擎规范；`block_dxa_qct_agreement <- function(ctx, ...) { ...; ctx }`；末尾 `register_block(...)`。

图：左面板 2×2 或三分类马赛克/热力交叉；右面板 Bland–Altman（`bland_zscore=TRUE` 时对 vBMD 与 T-score 分别 z 化后画差 vs 均）。

表：κ（二分类 OP）、三分类一致率、n。

- [ ] **Step 3: Run 单测**

Expected: PASS；无依赖完整 pipeline。

---

