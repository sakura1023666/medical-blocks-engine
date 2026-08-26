### Task 1: 列审阅 + Prep 派生 dabiao

**Files:**
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/_column_review.md`
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/prep_vitaldb_sodium.R`
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/D01_dabiao_VitalDB_sodium.RData`
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/_column_review_raw.txt`

**Interfaces:**
- Consumes: `D01_baseline_VitaIDB_CM(1).Rdata` 对象 `baseline`
- Produces: `dabiao` data.frame，含 `OpDuration_min`, `Vasopressor_use`, `Disease_Group`（因子：`No Postoperative AKI` / `Postoperative AKI`），保留 `judge`/`Sodium`/`ID` 与 Model 2/4 列

- [ ] **Step 1: 导出全列名**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript -e '
env <- new.env(parent = emptyenv())
load("/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/D01_baseline_VitaIDB_CM(1).Rdata", envir = env)
writeLines(names(env$baseline),
  "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/_column_review_raw.txt")
cat("n_cols=", length(names(env$baseline)), "\n")
'
```

Expected: 打印 `n_cols= 84`

- [ ] **Step 2: 写 `_column_review.md`（逐列）**

按 `skills/review-raw-covariate-columns/SKILL.md`：每列 `保留|排除` + 一句话理由。  
**必须排除出自动协变量池（写入后续 `disease_vars` / `exclude_*`）的示例：**  
`judge`（结局）、`icu_days`/`ICU_Days`、`death_inhosp`/`Death_Inhosp`、`IntraopUO`、`UreaNitrogen`、重复时间戳/文本诊断列（`Diagnosis`/`OpName`/`PreopECG` 等不进模型）、`GFR`/`CreatinineClearance`（与 Cr 共线，Model 2 只留 `Creatinine`）。  
**Creatinine：** Table1/Model2 **保留**（老师强制混杂）；不进亚组分层名单。

- [ ] **Step 3: 写并运行 prep 脚本**

`prep_vitaldb_sodium.R` 核心逻辑：

```r
.in <- "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb"
env <- new.env(parent = emptyenv())
load(file.path(.in, "D01_baseline_VitaIDB_CM(1).Rdata"), envir = env)
d <- env$baseline
stopifnot(is.data.frame(d), all(c("ID", "Sodium", "judge") %in% names(d)))

d$OpDuration_min <- as.numeric(d$opend - d$opstart) / 60
vaso_cols <- c("IntraopEPH", "IntraopPHE", "IntraopEPI", "IntraopCA")
d$Vasopressor_use <- factor(
  as.integer(rowSums(sapply(vaso_cols, function(v) as.numeric(d[[v]]) > 0), na.rm = TRUE) > 0),
  levels = c(0L, 1L), labels = c("No", "Yes")
)
# 结局因子（分析组 = Postoperative AKI）
d$Disease_Group <- factor(
  ifelse(as.integer(d$judge) == 1L, "Postoperative AKI", "No Postoperative AKI"),
  levels = c("No Postoperative AKI", "Postoperative AKI")
)
# 二值 0/1 兼容列（部分块读 Disease）
d$Disease <- as.integer(d$Disease_Group == "Postoperative AKI")

dabiao <- d
save(dabiao, file = file.path(.in, "D01_dabiao_VitalDB_sodium.RData"))
cat("nrow=", nrow(dabiao), " AKI=", sum(dabiao$Disease == 1L), "\n")
```

Run:

```bash
Rscript "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/prep_vitaldb_sodium.R"
```

Expected: `nrow= 6388 AKI= 268`

- [ ] **Step 4: 冒烟检查派生列**

```bash
Rscript -e '
e <- new.env(); load("/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/D01_dabiao_VitalDB_sodium.RData", envir=e)
print(summary(e$dabiao$OpDuration_min))
print(table(e$dabiao$Vasopressor_use, useNA="ifany"))
print(table(e$dabiao$Disease_Group, useNA="ifany"))
'
```

Expected: 手术时长有限值；Vasopressor_use 为 No/Yes；Disease_Group 两水平。

---

