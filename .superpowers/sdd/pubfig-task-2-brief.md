# Task brief (extracted)

### Task 2: Dual-batch finalize 挂载 export

**Files:**
- Modify: `R/incidence_dual_batch_runner.R`（`incidence_batch_finalize_index_outputs` 末尾，约 1920 行后、函数结束前）
- Modify: `tests/test_result_review_guards.R`（拼图清扫后增加「export 后顶层无散落」断言，或新建轻量用例）
- Modify: `configs/templates/config_incidence_dual_batch.template.R`
- Modify: `configs/templates/config_survival_dual_batch.template.R`
- Modify: `configs/templates/config_ml_dual_batch.template.R`

**Interfaces:**
- Consumes: `export_pub_figures(figures_dir, meta, config)` from Task 1
- Produces: finalize 顺序固定为 combine → curate → **export**

- [ ] **Step 1: 在 finalize 末尾 source + 调用**

在 `incidence_batch_finalize_index_outputs` 函数体**最后**（所有 table curate 之后）加入：

```r
  # 发表图四目录导出（pdf/png/tiff + image_information）
  if (!exists("export_pub_figures", mode = "function")) {
    exp_src <- file.path(root, "R", "pub_figure_export.R")
    if (file.exists(exp_src)) source(exp_src, local = FALSE)
  }
  if (exists("export_pub_figures", mode = "function")) {
    figs_dir <- file.path(index_root, "Figures")
    meta <- list(
      exposure = as.character(config$project$exposure_var %||% config$project$index_var %||% ix)[1L],
      outcome = as.character(config$data$outcome_column %||% config$project$outcome %||% "")[1L],
      databases = as.character(db_seq),
      combined = length(db_seq) >= 2L,
      grouping = as.character(
        config$logistic_gate$grouping %||%
          config$project$grouping %||%
          ""
      )[1L]
    )
    tryCatch(
      export_pub_figures(figs_dir, meta = meta, config = config),
      error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
    )
  }
```

注意：若 `index_root` 变量名在该函数内已是成功目录路径，直接用；不要在 combine 之前调用。

- [ ] **Step 2: 模板加默认配置**

每个 dual template 增加：

```r
  pub_figures = list(
    formats_dir = TRUE,
    dpi = 300L,
    tiff_compression = "lzw",
    write_image_information = TRUE
  ),
```

- [ ] **Step 3: 回归测试**

Run:

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript tests/test_result_review_guards.R
Rscript tests/test_pub_figure_export.R
```

Expected: 两者均 OK。若 guards 因路径假设失败，只修断言不改业务语义。

- [ ] **Step 4: Commit**

```bash
git add R/incidence_dual_batch_runner.R configs/templates/config_*_dual_batch.template.R
git commit -m "$(cat <<'EOF'
feat: run pub figure format export at dual-batch finalize

After combine and curate, write pdf/png/tiff and image_information
under aggregate Figures for incidence/survival/ML dual pipelines.
EOF
)"
```

---
