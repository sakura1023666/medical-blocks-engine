# Review package Task 1 (no git)
## Files
-rw-r--r-- 1 root root 1072 Aug 21 13:59 /mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/build_merged_data.R
-rw-r--r-- 1 root root 125020 Aug 21 14:00 /mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/mimic/D04_dabiao.RData

## build_merged_data.R
```r
# build_merged_data.R
# 稳定写法：相对本脚本
.args <- commandArgs(trailingOnly = FALSE)
.file <- sub("^--file=", "", grep("^--file=", .args, value = TRUE)[1])
.root <- if (length(.file) && nzchar(.file) && !is.na(.file)) {
  dirname(normalizePath(.file, winslash = "/"))
} else getwd()

if (nzchar(Sys.getenv("ECLAMPSIA_STUDY_ROOT"))) {
  .root <- Sys.getenv("ECLAMPSIA_STUDY_ROOT")
}

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

## Verification
nrow= 4756  events= 482  dup= 0 
