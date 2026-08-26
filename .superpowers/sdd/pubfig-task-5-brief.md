# Task brief

### Task 5: 竞争风险 + 通用单流水线收口

**Files:**
- Modify: `Blocks/55_competing_risk_full/18block_competing_pub_export.R`（在 `cli_alert_success` 之前）
- Modify: `R/pipeline_runner.R`（`run_pipeline` 在 `pub_renumber_pub_dir` **之后**对根 `Figures/` 调用 export）

**Interfaces:**
- Consumes: `export_pub_figures`
- 多库竞争风险：若根 `Figures/` 仍有 `-DB` 成对文件，先 `dual_db_combine_paired_figures(..., figures_dir=...)` 再 export

- [ ] **Step 1: competing_pub_export 末尾**

```r
  if (!exists("export_pub_figures", mode = "function")) {
    src <- file.path(ctx$config$project$root %||% getwd(), "R/pub_figure_export.R")
    if (file.exists(src)) source(src, local = FALSE)
  }
  if (exists("export_pub_figures", mode = "function")) {
    tryCatch(
      export_pub_figures(
        fig_dir,
        meta = list(
          exposure = ctx$config$project$exposure_var %||% "",
          outcome = ctx$config$data$outcome_column %||% "",
          databases = ctx$config$project$database %||% character(0),
          combined = FALSE
        ),
        config = ctx$config
      ),
      error = function(e) cli::cli_alert_warning("发表图导出跳过: {e$message}")
    )
  }
```

- [ ] **Step 2: `run_pipeline` 收尾**

在 `pub_renumber_pub_dir` 循环之后：

```r
  if (exists("export_pub_figures", mode = "function") ||
      file.exists(file.path(root, "R/pub_figure_export.R"))) {
    if (!exists("export_pub_figures", mode = "function")) {
      source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
    }
    out_root <- ctx$root_output_dir %||% config$project$output_dir
    figs <- file.path(out_root, "Figures")
    if (dir.exists(figs)) {
      # 若顶层已有 pdf/ 子目录则跳过，避免 dual-batch 子进程误二次处理
      if (!dir.exists(file.path(figs, "pdf"))) {
        tryCatch(
          export_pub_figures(figs, meta = list(
            exposure = config$project$exposure_var %||% config$project$index_var %||% "",
            outcome = config$data$outcome_column %||% "",
            databases = config$project$database %||% character(0),
            combined = FALSE
          ), config = config),
          error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
        )
      }
    }
  }
```

说明：dual-batch 指标目录由 Task 2 finalize 导出；worker 内 `run_pipeline` 若指向分库 `Figures/`，`pdf/` 尚不存在会导出分库底稿——**不可取**。改为：

```r
# 仅当非 dual 分库输出时导出：config$dual_db$current_db 为空/NULL，且路径不是 */<DB>/Figures
is_dual_slot <- !is.null(config$dual_db$current_db) && nzchar(as.character(config$dual_db$current_db)[1L])
if (!isTRUE(is_dual_slot) && dir.exists(figs) && !dir.exists(file.path(figs, "pdf"))) {
  export_pub_figures(...)
}
```

- [ ] **Step 3: 跑 `Rscript tests/test_pub_figure_export.R` + 相关 guards**

- [ ] **Step 4: Commit**

```bash
git add Blocks/55_competing_risk_full/18block_competing_pub_export.R R/pipeline_runner.R
git commit -m "$(cat <<'EOF'
feat: export publication figure formats from competing and single pipelines

Hook export_pub_figures after competing pub export and at run_pipeline
end for non-dual aggregate Figures directories.
EOF
)"
```

---

