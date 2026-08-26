### Task 1: 合并 D04_dabiao + 冒烟检查

**Files:**
- Create: `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/build_merged_data.R`
- Create: `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/mimic/D04_dabiao.RData`

**Interfaces:**
- Consumes: `data/D01_baseline_MIMIC_GW_0804.RData` (`baseline`), `data/D03_result_子痫_MIMIC(1).RData` (`result`)
- Produces: `dabiao` data.frame，列含 `ID`, `DN`, 基线全部列；`nrow==4756`，`sum(DN==1)==482`

- [ ] **Step 1: 写合并脚本**

```r
# build_merged_data.R
.root <- if (nzchar(Sys.getenv("ECLAMPSIA_STUDY_ROOT"))) {
  Sys.getenv("ECLAMPSIA_STUDY_ROOT")
} else {
  normalizePath(dirname(sys.frame(1)$ofile %||% "."), winslash = "/", mustWork = FALSE)
}
# 稳定写法：相对本脚本
.args <- commandArgs(trailingOnly = FALSE)
.file <- sub("^--file=", "", grep("^--file=", .args, value = TRUE)[1])
.root <- if (length(.file) && nzchar(.file) && !is.na(.file)) {
  dirname(normalizePath(.file, winslash = "/"))
} else getwd()

dir.create(file.path(.root, "Data", "mimic"), recursive = TRUE, showWarnings = FALSE)

load(file.path(.root, "data", "D01_baseline_MIMIC_GW_0804.RData"))
load(file.path(.root, "data", "D03_result_子痫_MIMIC(1).RData"))

stopifnot(exists("baseline"), exists("result"))
dabiao <- merge(result, baseline, by.x = "subject_id", by.y = "ID", all.x = TRUE)
names(dabiao)[names(dabiao) == "subject_id"] <- "ID"
stopifnot(nrow(dabiao) == 4756L)
stopifnot(sum(dabiao$DN == 1L, na.rm = TRUE) == 482L)
stopifnot(!anyDuplicated(dabiao$ID))

save(dabiao, file = file.path(.root, "Data", "mimic", "D04_dabiao.RData"))
message("OK dabiao n=", nrow(dabiao), " events=", sum(dabiao$DN == 1))
```

- [ ] **Step 2: 运行合并**

```bash
cd "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007"
Rscript build_merged_data.R
```

Expected: `OK dabiao n=4756 events=482`；`Data/mimic/D04_dabiao.RData` 存在。

- [ ] **Step 3: 验证**

```bash
Rscript -e 'load("/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/mimic/D04_dabiao.RData"); stopifnot(nrow(dabiao)==4756, sum(dabiao$DN==1)==482); cat("PASS\n")'
```

Expected: `PASS`

---

