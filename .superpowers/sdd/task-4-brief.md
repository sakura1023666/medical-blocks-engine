### Task 4: 模板 + 项目 config + runner

**Files:**
- Create: `configs/templates/config_ipw_pe_alteplase_dual_batch.template.R`
- Create: `run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R`
- Create: `run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch_worker.R`
- Create: `G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/config_ipw_pe_alteplase_MIMIC.R`
- Create: `.../config_ipw_pe_alteplase_eICU.R`

**Interfaces:**
- Consumes: Task 2 宽表路径；Task 3 block 名  
- Produces: 可 `--shared-only` / `--only-unit main` 的两套 config

- [ ] **Step 1: 以卒中 `config_ipw_diabetes_stroke_batch.R` 为底复制模板**

必改字段：

```r
project$disease <- "pe_ipw_alteplase"
project$database <- "MIMIC"  # eICU 配置改为 "eICU"
# index$enable <- FALSE
# ipw_alteplase$...（不用 ipw_diabetes HbA1c）
# iptw_balance$exposure_var <- "Alteplase"
# exposure_level_labels <- list(`0`="No alteplase", `1`="Alteplase")
# stepp_prognosis$index_var <- "composite_risk"
# stepp_prognosis$by_group$stratum_var <- "Alteplase"
# analysis_exclusion$disease_vars <- <from column review>
# analysis_exclusion$allow_no_index <- TRUE
# subgroup age_cutoff <- 65L  # 注释依据
```

pipeline_unit blocks：把 `ipw_diabetes_exposure` 换成 `ipw_alteplase_exposure`，其余保持卒中定稿顺序。

- [ ] **Step 2: runner/worker 从 `run/ipw_diabetes_stroke/` 复制并改默认 config 路径与日志前缀**

- [ ] **Step 3: dry-run**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R \
  --config "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/config_ipw_pe_alteplase_MIMIC.R" \
  --shared-only --dry-run
```

Expected: 打印 shared blocks，无缺文件报错。（若无 `--dry-run`，则 `source(config)` 能成功 `exists("pipeline_unit")`。）

---

