### Task 8: Runner + Worker（并行 batch）

**Files:**
- Create: `R/ip_two_stage_batch_runner.R`
- Create: `run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R`
- Create: `run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch_worker.R`

**Interfaces:**
- CLI：`--config` `--workers` `--only-index` `--shared-only` `--from` `--to` `--no-skip`
- Shared：跑到 `imputation`（含纳排/index/exclusion）
- Worker：每指标 Stage1 全链 → `ip_stage2_cohort_28d` → Stage2 全链 → finalize（Tables/Figures 镜像到结果根；成功则 `index_code_bundle_finalize`）

- [ ] **Step 1: 入口脚本头仿 `run_incidence_dual_batch.R`**，但调用 `ip_two_stage_batch_run()`
- [ ] **Step 2: Worker 内两阶段**

```r
# 伪代码
run_pipeline(ctx, blocks = stage0_or_stage1_blocks)
run_pipeline(ctx, blocks = "ip_stage2_cohort_28d")
# 切换 config$project$study_type <- "prognosis"；outcome/time/event
run_pipeline(ctx, blocks = stage2_blocks)
incidence_batch_finalize_index_outputs(ctx)  # 若可复用；否则写 ip_finalize
```

协变量综合：Stage2 开始前

```r
m1 <- unique(c(ctx$results$model1_incidence, ctx$config$ip_two_stage$force_covariates))
# Stage2 UV/MV 后再 union 写回 Model factors
```

- [ ] **Step 3: 试跑 1 个指标**

```bash
cd /mnt/e/01block/01Block-new-Final
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R \
  --config "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R" \
  --only-index NLR --workers 1
```

Expected: 结果根出现 `by_index/` 与 `Tables/`/`Figures/`（含 flowchart、Table1×2、ROC、RCS、threshold、KM）

---
