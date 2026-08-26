# 发病 / 预后敏感性轻量化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 发病和预后敏感性改为：从主分析 Table 1 动态发现 Yes/No 场景（两库 Yes n>50 才跑）+ 保留年龄分层；用主分析**已插补**队列删人后只重跑 Table 1/Table 2；场景目录打 `【success】`/`【failed】`；表文件为 S12/S13 且文件名含 `Sensitivity analysis` 与中文描述。

**Architecture:** 纯函数放在 `R/incidence_sensitivity_suite.R`（发现场景、打标、拷贝 imputed ck、截断 pipeline、S12/S13 重命名、Model2 主对比判定）。Worker 识别 `.sensitivity_light` 后不再 copy `_shared`、不跑 imputation。Config 去掉写死的四个 `scenarios`。

**Tech Stack:** R, jsonlite, cli, 现有 dual-batch worker / baseline / logistic / Cox blocks。测试用 `Rscript tests/test_*.R` + `stopifnot`。

**Spec:** `docs/superpowers/specs/2026-08-17-incidence-prognosis-sensitivity-light-design.md`

## Global Constraints

- 数据必须来自主分析 per-index **插补后** checkpoint，禁止 copy `_shared` 再插补。
- Table 2 协变量 = 主分析 Gate B Model1/Model2；唯一例外是过滤后单水平/零方差变量必须删掉。
- 只跑主分析选中档（quartile/tertile/binary）的 Table 1 + Table 2，不跑 VIF/RCS/亚组/中介。
- Yes/No 只排除 Yes，保留 No 和 NA；Gender/Race 等非 Yes/No 不生成场景。
- 两库 Yes n 都必须 >50 才生成该 Yes/No 场景；年龄分层两库剩余都必须 ≥ `min_n_per_db`。
- 目录：`sensitivity/【success|failed】<label>/`；S12=基线，S13=关联表。
- 任一库 Table 2 Model2 主对比 p≥0.05 → `【failed】`，表仍保留。
- 忽略 config 里旧的 `scenarios` 名单。
- 不新增 `register_block`。不改 `subgroup_fallback`。
- 除非用户明确要求，否则不要 git commit。

## File map

| File | Responsibility |
|------|----------------|
| `R/incidence_sensitivity_suite.R` | 场景发现、中文描述、S12/S13 文件名、拷贝 imputed ck、截断 pipeline、打标、NS 判定 |
| `run/incidence/run_incidence_dual_batch_worker.R` | `.sensitivity_light`：跳过 copy shared，用已准备 ck，截断 pipeline |
| `run/survival/run_survival_dual_batch_worker.R` | 同上 |
| `R/pipeline_capability_layer.R` | `pipeline_default_sensitivity_scenarios` 只保留年龄分层 |
| `configs/templates/config_incidence_dual_batch.template.R` | 去掉手写 scenarios |
| `configs/study_interface/incidence_dual_batch_build.R` | 同上 |
| `configs/templates/config_survival_dual_batch.template.R` | 与发病同构 enable 键 |
| `configs/study_interface/survival_dual_batch_build.R` | 去掉手写 scenarios |
| `R/incidence_pipeline_brief.R` | 敏感性说明改为动态 + 轻量 Table1/2 |
| `tests/test_incidence_sensitivity_light.R` | 本特性单测 |
| `tests/test_result_review_guards.R` | 更新对 suite 文本的断言 |
| `skills/deploy-programmer-interface/reference.md` | 程序员口径 |

---

### Task 1: 纯函数 — Yes/No、中文描述、文件名、成败判定

**Files:**
- Create: `tests/test_incidence_sensitivity_light.R`
- Modify: `R/incidence_sensitivity_suite.R`（文件顶部、`incidence_sensitivity_resolve` 之前插入新函数）

**Interfaces:**
- Produces: `incidence_sensitivity_is_yes_no(x)` → logical
- Produces: `incidence_sensitivity_yes_n(x)` → integer
- Produces: `incidence_sensitivity_exclude_yes_expr(var)` → character
- Produces: `incidence_sensitivity_zh_desc(label, age_cutoff=65, display_names=NULL)` → character
- Produces: `incidence_sensitivity_pub_stem(s_num, db_tag, zh_desc, caption)` → character basename without `.xlsx`
- Produces: `incidence_sensitivity_judge_status(ok_t1, ok_t2, p_primary, p_secondary, sig_cutoff=0.05)` → `"success"` / `"failed"`

- [ ] **Step 1: Write failing tests**

```r
# tests/test_incidence_sensitivity_light.R
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/incidence_sensitivity_suite.R"), local = FALSE)

stopifnot(isTRUE(incidence_sensitivity_is_yes_no(c("Yes", "No", "Yes", NA))))
stopifnot(isTRUE(incidence_sensitivity_is_yes_no(c(1, 0, 1))))
stopifnot(!isTRUE(incidence_sensitivity_is_yes_no(c("White", "Black", "Other"))))
stopifnot(!isTRUE(incidence_sensitivity_is_yes_no(c("Male", "Female"))))
stopifnot(identical(incidence_sensitivity_yes_n(c("Yes", "No", "Yes", "Yes ")), 3L))

ex <- incidence_sensitivity_exclude_yes_expr("Hypertension")
stopifnot(grepl("Hypertension", ex, fixed = TRUE))
stopifnot(grepl("Yes", ex, fixed = TRUE))

stopifnot(identical(incidence_sensitivity_zh_desc("SA_no_Hypertension"), "非高血压"))
stopifnot(identical(incidence_sensitivity_zh_desc("SA_no_T2DM"), "非糖尿病"))
stopifnot(identical(incidence_sensitivity_zh_desc("SA_age_ge_65", 65), "年龄≥65"))
stopifnot(identical(incidence_sensitivity_zh_desc("SA_age_lt_60", 60), "年龄<60"))

st <- incidence_sensitivity_pub_stem(
  12L, "eICU", "非高血压", "Baseline characteristics"
)
stopifnot(grepl("^Table S12-eICU\\. Sensitivity analysis-非高血压\\. Baseline characteristics$", st))
st13 <- incidence_sensitivity_pub_stem(
  13L, "MIMIC", "年龄≥65", "Cox regression of NLR quartile"
)
stopifnot(grepl("Table S13-MIMIC", st13, fixed = TRUE))
stopifnot(grepl("Sensitivity analysis-年龄≥65", st13, fixed = TRUE))

stopifnot(identical(
  incidence_sensitivity_judge_status(TRUE, TRUE, 0.01, 0.02, 0.05),
  "success"
))
stopifnot(identical(
  incidence_sensitivity_judge_status(TRUE, TRUE, 0.01, 0.20, 0.05),
  "failed"
))
stopifnot(identical(
  incidence_sensitivity_judge_status(TRUE, FALSE, 0.01, 0.02, 0.05),
  "failed"
))
cat("Task1 OK\n")
```

- [ ] **Step 2: Run — expect FAIL（函数不存在）**

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_incidence_sensitivity_light.R
```

Expected: `could not find function "incidence_sensitivity_is_yes_no"`

- [ ] **Step 3: Implement helpers in `R/incidence_sensitivity_suite.R`**

放在 `incidence_sensitivity_resolve` 之前：

```r
incidence_sensitivity_yes_tokens <- function() {
  c("Yes", "yes", "YES", "1", "TRUE", "True", "true", "Y", "y")
}

incidence_sensitivity_no_tokens <- function() {
  c("No", "no", "NO", "0", "FALSE", "False", "false", "N", "n")
}

incidence_sensitivity_as_yes_no_chr <- function(x) {
  xs <- trimws(as.character(x))
  yes <- incidence_sensitivity_yes_tokens()
  no  <- incidence_sensitivity_no_tokens()
  xs[xs %in% yes] <- "Yes"
  xs[xs %in% no]  <- "No"
  xs
}

incidence_sensitivity_is_yes_no <- function(x) {
  xs <- incidence_sensitivity_as_yes_no_chr(x)
  lv <- unique(xs[!is.na(xs) & nzchar(xs)])
  length(lv) >= 1L && length(lv) <= 2L && all(lv %in% c("Yes", "No"))
}

incidence_sensitivity_yes_n <- function(x) {
  xs <- incidence_sensitivity_as_yes_no_chr(x)
  as.integer(sum(xs == "Yes", na.rm = TRUE))
}

incidence_sensitivity_exclude_yes_expr <- function(var) {
  var <- as.character(var)[1L]
  sprintf(
    'is.na(%1$s) | trimws(as.character(%1$s)) != "Yes"',
    var
  )
}

incidence_sensitivity_zh_var_map <- function() {
  c(
    Hypertension = "高血压", T2DM = "糖尿病", Diabetes = "糖尿病",
    CKD = "CKD", Heart_Failure = "心衰", COPD = "COPD",
    Cancer = "癌症", Pneumonia = "肺炎", Stroke = "卒中"
  )
}

incidence_sensitivity_zh_desc <- function(label, age_cutoff = 65, display_names = NULL) {
  label <- as.character(label)[1L]
  m <- regexec("^SA_age_ge_([0-9]+)$", label, perl = TRUE)
  mm <- regmatches(label, m)[[1L]]
  if (length(mm)) return(paste0("年龄≥", mm[2L]))
  m <- regexec("^SA_age_lt_([0-9]+)$", label, perl = TRUE)
  mm <- regmatches(label, m)[[1L]]
  if (length(mm)) return(paste0("年龄<", mm[2L]))
  if (startsWith(label, "SA_no_")) {
    var <- sub("^SA_no_", "", label)
    dn <- as.character((display_names %||% list())[[var]] %||% "")[1L]
    mp <- incidence_sensitivity_zh_var_map()
    zh <- if (nzchar(dn)) dn else (unname(mp[var]) %||% var)
    return(paste0("非", zh))
  }
  label
}

incidence_sensitivity_pub_stem <- function(s_num, db_tag, zh_desc, caption) {
  s_num <- as.integer(s_num)[1L]
  db_tag <- as.character(db_tag %||% "")[1L]
  zh_desc <- as.character(zh_desc)[1L]
  caption <- as.character(caption)[1L]
  db_part <- if (nzchar(db_tag)) paste0("-", db_tag) else ""
  sprintf(
    "Table S%d%s. Sensitivity analysis-%s. %s",
    s_num, db_part, zh_desc, caption
  )
}

incidence_sensitivity_judge_status <- function(ok_t1, ok_t2, p_primary, p_secondary,
                                               sig_cutoff = 0.05) {
  tables_ok <- isTRUE(ok_t1) && isTRUE(ok_t2)
  p1 <- suppressWarnings(as.numeric(p_primary)[1L])
  p2 <- suppressWarnings(as.numeric(p_secondary)[1L])
  sig_ok <- is.finite(p1) && is.finite(p2) &&
    p1 < sig_cutoff && p2 < sig_cutoff
  if (tables_ok && sig_ok) "success" else "failed"
}
```

`incidence_sensitivity_resolve` 改为**忽略** `sens$scenarios`，只返回空 list（真正场景由 Task 2 的 `incidence_sensitivity_scenarios_for_index` 生成）。暂时可留函数以免旧调用崩，但必须不再展开 config 里那四个。

- [ ] **Step 4: Re-run tests — expect PASS**

```bash
cd /mnt/e/01block/01Block-new-Final && Rscript tests/test_incidence_sensitivity_light.R
```

Expected: `Task1 OK`

---

### Task 2: 按 Table 1 + 插补数据发现场景

**Files:**
- Modify: `tests/test_incidence_sensitivity_light.R`（追加）
- Modify: `R/incidence_sensitivity_suite.R`

**Interfaces:**
- Consumes: Task 1 helpers
- Produces: `incidence_sensitivity_discover_yesno(t1_vars_by_db, data_by_db, min_yes_n=50L)` → list of `list(label, expr, var)`
- Produces: `incidence_sensitivity_age_scenarios(age_cutoff, data_by_db, min_n=50L, age_var="Age")` → list
- Produces: `incidence_sensitivity_scenarios_for_index(...)` 在 Task 5 接线；本 task 先完成两个发现函数

- [ ] **Step 1: Append failing tests**

```r
nh <- data.frame(
  Hypertension = c(rep("Yes", 51), rep("No", 60)),
  T2DM = c(rep("Yes", 40), rep("No", 71)),
  Race = c(rep("White", 80), rep("Black", 31)),
  Age = c(rep(70, 40), rep(50, 71)),
  stringsAsFactors = FALSE
)
mi <- data.frame(
  Hypertension = c(rep("Yes", 55), rep("No", 50)),
  T2DM = c(rep("Yes", 60), rep("No", 45)),
  Race = c(rep("White", 70), rep("Black", 35)),
  Age = c(rep(70, 80), rep(50, 25)),
  stringsAsFactors = FALSE
)
t1 <- list(nhanes = c("Hypertension", "T2DM", "Race", "Age"),
           mimic  = c("Hypertension", "T2DM", "Race", "Age"))
sc <- incidence_sensitivity_discover_yesno(
  t1, list(nhanes = nh, mimic = mi), min_yes_n = 50L
)
labs <- vapply(sc, `[[`, character(1), "label")
stopifnot("SA_no_Hypertension" %in% labs)
stopifnot(!"SA_no_T2DM" %in% labs)   # nhanes Yes=40
stopifnot(!"SA_no_Race" %in% labs)

age_sc <- incidence_sensitivity_age_scenarios(
  65L, list(nhanes = nh, mimic = mi), min_n = 50L
)
age_labs <- vapply(age_sc, `[[`, character(1), "label")
stopifnot("SA_age_ge_65" %in% age_labs)  # mimic ge65 n=80, nhanes=40 → 跳过 ge？
```

按 spec：年龄分层两库剩余都 ≥50 才跑。上面 nhanes Age≥65 只有 40 → `SA_age_ge_65` **跳过**；`SA_age_lt_65`：nhanes 71、mimic 25 → 也跳过。再造一份两库都够的数据测通过。

把上面最后一段改成明确的两套：

```r
# T2DM: nhanes Yes=40 → 不生成
stopifnot(!"SA_no_T2DM" %in% labs)

d_ok <- list(
  nhanes = data.frame(Age = c(rep(70, 60), rep(50, 60))),
  mimic  = data.frame(Age = c(rep(70, 60), rep(50, 60)))
)
age_ok <- incidence_sensitivity_age_scenarios(65L, d_ok, min_n = 50L)
stopifnot(length(age_ok) == 2L)
d_bad <- list(
  nhanes = data.frame(Age = c(rep(70, 40), rep(50, 80))),
  mimic  = data.frame(Age = c(rep(70, 80), rep(50, 40)))
)
age_bad <- incidence_sensitivity_age_scenarios(65L, d_bad, min_n = 50L)
stopifnot(length(age_bad) == 0L)
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```r
incidence_sensitivity_discover_yesno <- function(t1_vars_by_db, data_by_db, min_yes_n = 50L) {
  dbs <- intersect(names(t1_vars_by_db), names(data_by_db))
  if (length(dbs) < 2L) return(list())
  common <- Reduce(intersect, lapply(t1_vars_by_db[dbs], as.character))
  out <- list()
  for (v in common) {
    ok <- TRUE
    for (db in dbs) {
      df <- data_by_db[[db]]
      if (!is.data.frame(df) || !v %in% names(df)) { ok <- FALSE; break }
      if (!incidence_sensitivity_is_yes_no(df[[v]])) { ok <- FALSE; break }
      if (incidence_sensitivity_yes_n(df[[v]]) <= as.integer(min_yes_n)) {
        ok <- FALSE; break
      }
    }
    if (!ok) next
    out[[length(out) + 1L]] <- list(
      label = paste0("SA_no_", v),
      expr = incidence_sensitivity_exclude_yes_expr(v),
      var = v,
      required_vars = v
    )
  }
  out
}

incidence_sensitivity_age_scenarios <- function(age_cutoff, data_by_db, min_n = 50L,
                                                age_var = "Age") {
  age_cutoff <- as.integer(age_cutoff)[1L]
  min_n <- as.integer(min_n)[1L]
  dbs <- names(data_by_db)
  if (length(dbs) < 2L) return(list())
  n_ge <- n_lt <- integer(0)
  names_ge <- names_lt <- character(0)
  for (db in dbs) {
    df <- data_by_db[[db]]
    if (!is.data.frame(df) || !age_var %in% names(df)) return(list())
    age <- suppressWarnings(as.numeric(df[[age_var]]))
    n_ge <- c(n_ge, sum(is.finite(age) & age >= age_cutoff))
    n_lt <- c(n_lt, sum(is.finite(age) & age < age_cutoff))
  }
  out <- list()
  if (all(n_ge >= min_n)) {
    out[[length(out) + 1L]] <- list(
      label = sprintf("SA_age_ge_%s", age_cutoff),
      expr = sprintf("as.numeric(%s) >= %s", age_var, age_cutoff),
      required_vars = age_var
    )
  }
  if (all(n_lt >= min_n)) {
    out[[length(out) + 1L]] <- list(
      label = sprintf("SA_age_lt_%s", age_cutoff),
      expr = sprintf("as.numeric(%s) < %s", age_var, age_cutoff),
      required_vars = age_var
    )
  }
  out
}
```

读 Table 1 变量（供 Task 5 调用，本 task 一并实现并测）：

```r
incidence_sensitivity_read_table1_vars <- function(parent_dir, db_dir_name) {
  hits <- list.files(
    file.path(parent_dir, db_dir_name),
    pattern = "^categorical_vars\\.txt$",
    recursive = TRUE, full.names = TRUE
  )
  hits <- hits[!grepl("sensitivity", hits)]
  if (!length(hits)) return(character(0))
  unique(trimws(readLines(hits[[1L]], warn = FALSE)))
}
```

测试：临时目录写 `categorical_vars.txt` 再读回。

- [ ] **Step 4: Re-run full test file — expect PASS**

---

### Task 3: 复制主分析 imputed checkpoint，剥掉 baseline 之后的块

**Files:**
- Modify: `R/incidence_sensitivity_suite.R`
- Modify: `tests/test_incidence_sensitivity_light.R`

**Interfaces:**
- Produces: `incidence_sensitivity_copy_imputed_ck(src_dir, dest_dir)` → dest_dir；只保留 imputation 及更早的 `*.rds`（外加 `index.rds` 用 imputation 内容覆盖）
- Produces: 断言 dest 中没有 `baseline_binary.rds` / `imputation` 之后的 logistic/cox rds

- [ ] **Step 1: Failing test with temp ck dirs**

```r
src <- tempfile("ck_src")
dst <- tempfile("ck_dst")
dir.create(src)
saveRDS(list(ctx = list(data = list(imputed = data.frame(Age = 1:3)))),
        file.path(src, "imputation.rds"))
saveRDS(list(marker = "later"), file.path(src, "baseline_binary.rds"))
saveRDS(list(marker = "later"), file.path(src, "logistic_quartile_glm.rds"))
saveRDS(list(marker = "stale_index"), file.path(src, "index.rds"))
incidence_sensitivity_copy_imputed_ck(src, dst)
stopifnot(file.exists(file.path(dst, "imputation.rds")))
stopifnot(file.exists(file.path(dst, "index.rds")))
stopifnot(!file.exists(file.path(dst, "baseline_binary.rds")))
stopifnot(!file.exists(file.path(dst, "logistic_quartile_glm.rds")))
idx <- readRDS(file.path(dst, "index.rds"))
stopifnot(!is.null(idx$ctx$data$imputed))
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Keep 文件名（basename 去掉 `NN_` 前缀后）命中：

`data_clean`, `column_mapping`, `dual_db_column_harmonize`, `index`, `analysis_exclusion`, `imputation`

逻辑：

1. `dir.create(dest)`；若已存在则 `unlink(recursive=TRUE)` 再建。
2. 列出 src 下 `*.rds`。
3. `block_key <- sub("^[0-9]+_", "", tools::file_path_sans_ext(basename(p)))`
4. 复制 keep 集合中的文件。
5. 优先把 `imputation.rds`（或带编号的 imputation）复制为 dest/`index.rds`；若无 imputation 则复制 src/`index.rds` 并警告。
6. **不要**复制 baseline / logistic / cox / rcs / subgroup / mediation / obj / cutoff（obj 由轻量 pipeline 重跑）。

若 src 不存在或没有 imputed 数据：`stop("敏感性轻量路径需要主分析插补后 checkpoint: ", src)`。

- [ ] **Step 4: Re-run tests — PASS**

---

### Task 4: 截断 pipeline + 滤后删单水平协变量

**Files:**
- Modify: `R/incidence_sensitivity_suite.R`
- Modify: `tests/test_incidence_sensitivity_light.R`

**Interfaces:**
- Produces: `incidence_sensitivity_light_blocks(study_type, weighted, scheme)` → character
- Produces: `incidence_sensitivity_trim_pipeline(pipeline, blocks)` → pipeline list（`blocks` 与 `render_tables_after` 取交集）
- Produces: `incidence_sensitivity_constant_vars(df, vars)` → character
- Produces: `incidence_sensitivity_drop_constant_from_config(config, df)` → config

- [ ] **Step 1: Failing tests**

```r
inc_w <- incidence_sensitivity_light_blocks("incidence", TRUE, "quartile")
stopifnot(identical(inc_w[1:3], c("obj", "baseline_nhanes", "logistic_quartile_nhanes_weighted")))
stopifnot("dual_db_logistic_main_table_realign" %in% inc_w)
stopifnot(!"imputation" %in% inc_w)
stopifnot(!"rcs_nhanes" %in% inc_w)

inc_u <- incidence_sensitivity_light_blocks("incidence", FALSE, "tertile")
stopifnot("baseline_binary" %in% inc_u)
stopifnot("logistic_tertile_glm" %in% inc_u)

surv <- incidence_sensitivity_light_blocks("prognosis", FALSE, "binary")
stopifnot(identical(surv, c("baseline_binary", "cox_binary")))

pipe <- list(blocks = c("imputation", "baseline_binary", "boxplot", "cox_quartile", "rcs_prognosis"),
             render_tables_after = c("imputation", "baseline_binary", "cox_quartile"))
tr <- incidence_sensitivity_trim_pipeline(pipe, c("baseline_binary", "cox_quartile"))
stopifnot(identical(tr$blocks, c("baseline_binary", "cox_quartile")))
stopifnot(!"imputation" %in% tr$render_tables_after)

df <- data.frame(
  Age = 1:10,
  Hypertension = factor(rep("No", 10), levels = c("No", "Yes")),
  WBC = rnorm(10)
)
stopifnot(identical(incidence_sensitivity_constant_vars(df, c("Age", "Hypertension", "WBC")),
                    "Hypertension"))
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

```r
incidence_sensitivity_light_blocks <- function(study_type, weighted, scheme) {
  scheme <- as.character(scheme)[1L]
  if (!scheme %in% c("quartile", "tertile", "binary")) scheme <- "quartile"
  if (identical(as.character(study_type)[1L], "prognosis")) {
    return(c("baseline_binary", paste0("cox_", scheme)))
  }
  if (isTRUE(weighted)) {
    return(c(
      "obj", "baseline_nhanes",
      paste0("logistic_", scheme, "_nhanes_weighted"),
      "dual_db_logistic_scheme_harmonize",
      "dual_db_logistic_main_table_realign"
    ))
  }
  c(
    "baseline_binary",
    paste0("logistic_", scheme, "_glm"),
    "dual_db_logistic_scheme_harmonize",
    "dual_db_logistic_main_table_realign"
  )
}

incidence_sensitivity_trim_pipeline <- function(pipeline, keep_blocks) {
  keep <- as.character(keep_blocks)
  pipeline$blocks <- intersect(as.character(pipeline$blocks %||% character(0)), keep)
  if (!is.null(pipeline$render_tables_after)) {
    pipeline$render_tables_after <- intersect(pipeline$render_tables_after, pipeline$blocks)
  }
  if (!is.null(pipeline$render_figures_after)) {
    pipeline$render_figures_after <- intersect(pipeline$render_figures_after, pipeline$blocks)
  }
  pipeline
}

incidence_sensitivity_constant_vars <- function(df, vars) {
  vars <- as.character(vars %||% character(0))
  drop <- character(0)
  for (v in vars) {
    if (!v %in% names(df)) next
    u <- unique(df[[v]][!is.na(df[[v]])])
    if (length(u) < 2L) drop <- c(drop, v)
  }
  unique(drop)
}
```

`incidence_sensitivity_drop_constant_from_config`：从 `harmonized_model1_*` / `harmonized_model2_*` / `baseline_*$include_vars` 去掉 constant 列。

- [ ] **Step 4: Re-run — PASS**

---

### Task 5: 改 suite 编排 — 发现场景、拷 ck、打标、S12/S13、NS 判定

**Files:**
- Modify: `R/incidence_sensitivity_suite.R`（`incidence_sensitivity_write_config`, `incidence_sensitivity_run_one`, `incidence_sensitivity_for_index`, 打印汇总）
- Modify: `tests/test_incidence_sensitivity_light.R`
- Modify: `tests/test_result_review_guards.R`（仍要求 `force = FALSE` 与 `--no-skip，重跑已成功敏感性` 字符串存在）

**Interfaces:**
- Consumes: Tasks 1–4
- Produces: `incidence_sensitivity_scenarios_for_index(config, parent_dir, main_ck_base, ix, db_names)`
- Produces: `incidence_sensitivity_rename_pub_tables(tables_dir, db_tag, zh_desc, study_type)`
- Produces: `incidence_sensitivity_model2_primary_p(ctx)` → numeric
- Changes: `run_one` 拷贝 **主分析** `index_ck_base/ix/<db>` 而不是让 worker copy shared
- Changes: 产物目录 `incidence_batch_output_dir_name(sg$label, status)`
- Changes: write_config 注入 `.sensitivity_light=TRUE`、`.sensitivity_scheme`、锁协变量；**删除**「整条重跑 + 关闸门堆 RCS」中与轻量无关的 cox degrade 长段可保留关闸门（防 Table2 早停）

- [ ] **Step 1: Tests for rename + model2 p + dir name**

```r
td <- tempfile("sa_tab")
dir.create(td)
file.create(file.path(td, "Table 1-eICU. Baseline characteristics.xlsx"))
file.create(file.path(td, "Table 2-eICU. Logistic regression of NLR quartile.xlsx"))
incidence_sensitivity_rename_pub_tables(td, "eICU", "非高血压", "incidence")
fns <- list.files(td)
stopifnot(any(grepl("^Table S12-eICU\\. Sensitivity analysis-非高血压", fns)))
stopifnot(any(grepl("^Table S13-eICU\\. Sensitivity analysis-非高血压", fns)))

# 12 列 logistic 表：第 12 列是 Model2 P，最后一行是最高组
rt <- as.data.frame(matrix("0.40", 3, 12), stringsAsFactors = FALSE)
rt[3, 12] <- "0.012"
ctx <- list(results = list(logistic_table2 = rt))
p <- incidence_sensitivity_model2_primary_p(ctx)
stopifnot(abs(p - 0.012) < 1e-8)

stopifnot(grepl(
  "【success】SA_no_Hypertension",
  incidence_batch_output_dir_name("SA_no_Hypertension", "success"),
  fixed = TRUE
))
```

`incidence_sensitivity_model2_primary_p`：优先 `ctx$results$logistic_table2` / `nhanes_logistic_table2` / Cox 主表；取最后一行、Model2 的 P 列（logistic 12 列宽表第 12 列；Cox 同类）。解析 `pub_format_p_cell` 的 `"<0.001"` 为 0.0005。

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Rewrite `incidence_sensitivity_write_config`**

保留：source 主 config、写回 study_root、锁 M1/M2、关 feishu、关 early_stop / logistic gate。

新增行：

```r
"config$incidence_batch$.sensitivity_light <- TRUE",
paste0("config$incidence_batch$.sensitivity_scheme <- ", .q(scheme)),
paste0("config$incidence_batch$.sensitivity_zh_desc <- ", .q(zh_desc)),
"config$incidence_batch$.subgroup_fallback_expr  <- ...",  # 仍用于滤人
```

预后：`config$survival_batch$.sensitivity_light <- TRUE` 同样注入。

删掉「从 shared 再跑全流程」不再需要的 RCS/亚组/中介相关覆盖（轻量 pipeline 里那些块根本不在）。

`run_one` 关键顺序：

1. `incidence_sensitivity_copy_imputed_ck(main_ck/<db>, sens_ck/<db>)` 对每个 db。
2. `incidence_batch_apply_subgroup_filter(sens_ck/.../index.rds, expr, ix)`。
3. 读过滤后 imputed，`drop_constant_from_config` 后再写 temp config（或 filter 后改 config 再 spawn）。
4. spawn worker（worker 见 Task 6）。
5. 在 staging 的 Tables 上 `rename_pub_tables`。
6. 从 worker ctx/status 抽 Model2 p；`judge_status`。
7. `file.rename` 到 `parent/sensitivity/【status】label/`（先删旧的 success/failed/裸名三个变体）。
8. 失败时拷 `worker.log`。

`for_index`：用主分析 parent 的 `categorical_vars.txt` + 主分析 ck 的 imputed 列（不要用 shared 的未插补表做 Yes n，与 spec 一致）。两库 dir 名用 `dual_db_slot_path_name`。

读 imputed：

```r
incidence_sensitivity_load_imputed <- function(main_ck_base, ix, db_path_name) {
  p <- file.path(main_ck_base, ix, db_path_name, "imputation.rds")
  if (!file.exists(p)) p <- file.path(main_ck_base, ix, db_path_name, "index.rds")
  obj <- readRDS(p)
  df <- obj$ctx$data$imputed %||% incidence_batch_ctx_data(obj$ctx)
  if (exists("pipeline_normalize_yes_no_factors", mode = "function"))
    df <- pipeline_normalize_yes_no_factors(df)
  df
}
```

scheme 来源：主分析 `_batch_status.json` 的 `nhanes_branch` / `mimic_branch`，都缺则 `"quartile"`。预后同字段或 `cox` 选中档。

跳过已成功：检查 `sensitivity/【success】<label>/` 是否存在。

- [ ] **Step 4: 更新 `test_result_review_guards.R`**

现有断言 `force = FALSE` 和 `--no-skip，重跑已成功敏感性` 必须仍成立。若改了那行中文，同步改测试字符串。

- [ ] **Step 5: Re-run both test files — PASS**

```bash
Rscript tests/test_incidence_sensitivity_light.R
Rscript tests/test_result_review_guards.R
```

---

### Task 6: Worker 轻量路径（发病 + 预后）

**Files:**
- Modify: `run/incidence/run_incidence_dual_batch_worker.R`（约 287–376 行 copy shared / `.run_db_phase`）
- Modify: `run/survival/run_survival_dual_batch_worker.R`（约 234–260 行 copy shared；后续 phase 循环）
- Modify: `tests/test_incidence_sensitivity_light.R`（对 worker 源码做字符串守卫，避免再走 shared+imputation）

**Interfaces:**
- Consumes: `config$incidence_batch$.sensitivity_light`（预后读 `survival_batch` 或 incidence 合并段）
- 当 light=TRUE：禁止 `incidence_batch_copy_shared_ck`；`pipe <- incidence_sensitivity_trim_pipeline(pipe, incidence_sensitivity_light_blocks(...))`；`run_pipeline` 的 from/to 覆盖为截断后的首尾块（不要走三阶段 VIF/RCS）

- [ ] **Step 1: Guard test（读 worker 源码）**

```r
inc_w <- paste(readLines("run/incidence/run_incidence_dual_batch_worker.R", warn = FALSE), collapse = "\n")
stopifnot(grepl("\\.sensitivity_light", inc_w))
stopifnot(grepl("incidence_sensitivity_copy_imputed_ck|sensitivity_light", inc_w))
# 轻量分支不得在 light 为 TRUE 时无条件 copy shared
surv_w <- paste(readLines("run/survival/run_survival_dual_batch_worker.R", warn = FALSE), collapse = "\n")
stopifnot(grepl("\\.sensitivity_light", surv_w))
```

更严：用正则确认 `if (isTRUE(...sensitivity_light))` 出现在 `incidence_batch_copy_shared_ck` 之前，且 copy 在 else 里。

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Incidence worker**

在「复制 shared checkpoint」整段外包一层：

```r
bc <- config$incidence_batch %||% list()
light <- isTRUE(bc$.sensitivity_light)
if (light) {
  cli::cli_alert_info("[{ix}] 敏感性轻量路径：使用主分析插补后 ck，不复制 shared、不插补")
  scheme <- as.character(bc$.sensitivity_scheme %||% "quartile")[1L]
  # 确认 per_index_ck/index.rds 已存在（suite 已拷+过滤），否则 failed
} else if (!resume_mode) {
  # 现有 copy shared + subgroup filter
}
```

`.run_db_phase` 里：

```r
pipe <- if (dual_db_is_weighted(config, db)) pipeline_nhanes_batch else pipeline_regular_batch
if (isTRUE((config_ix$incidence_batch %||% list())$.sensitivity_light)) {
  scheme <- as.character(config_ix$incidence_batch$.sensitivity_scheme %||% "quartile")[1L]
  keep <- incidence_sensitivity_light_blocks(
    "incidence", dual_db_is_weighted(config, db), scheme
  )
  pipe <- incidence_sensitivity_trim_pipeline(pipe, keep)
}
```

轻量时**不要**跑 Phase1 VIF / Phase2 三档 cascade / Phase3 RCS。Worker 主 `try` 里若 `light`，改为：对 `actual_db_seq` 各跑一次 `.run_db_phase(db, from=pipe$blocks[1], to=tail(pipe$blocks,1))`，然后 `dual_db_logistic_main_table_realign` 若还在 blocks 里已包含则不必再手调。最后 `finalize` + `write_status`。

关 logistic_gate：write_config 已关；worker 也可 `pipe$logistic_gate$enable <- FALSE`。

- [ ] **Step 4: Survival worker**

同样：`sb <- config$survival_batch %||% config$incidence_batch`；`light <- isTRUE(sb$.sensitivity_light)`。

轻量时跳过 copy shared（suite 已拷），跳过 Cox 闸门链三档，只跑 `incidence_sensitivity_light_blocks("prognosis", FALSE, scheme)`。

预后 scheme：`sb$.sensitivity_scheme`，来自主分析 status 的 cox 选中档，缺省 `quartile`。

- [ ] **Step 5: Re-run tests — PASS**

---

### Task 7: Config、能力层默认场景、文档、brief

**Files:**
- Modify: `R/pipeline_capability_layer.R` `pipeline_default_sensitivity_scenarios`（约 760–778 行）只返回年龄两场，删除高血压/糖尿病
- Modify: `configs/templates/config_incidence_dual_batch.template.R`（约 265–277）
- Modify: `configs/study_interface/incidence_dual_batch_build.R`（约 184–195）
- Modify: `configs/templates/config_survival_dual_batch.template.R`（约 115）
- Modify: `configs/study_interface/survival_dual_batch_build.R`（约 195–207）
- Modify: `R/incidence_pipeline_brief.R`（约 420–443）
- Modify: `skills/deploy-programmer-interface/reference.md` 敏感性一节
- Modify: `R/sensitivity_scenario_runner.R` 若仍调用 default 四场，改为年龄 + 文档注释（单库 runner 不是本需求主路径，但默认函数变了必须能跑）

**Config 形状（发病 build 与 template 一致）：**

```r
sensitivity_suite = list(
  enable       = TRUE,
  age_cutoff   = 65L,
  min_n_per_db = 50L,
  min_yes_n    = 50L
)
```

不要 `scenarios`。注释写明：Yes/No 从两库 Table 1 动态生成；忽略旧课题残留的 scenarios。

预后 template 现 `enable = FALSE`：改为与发病同构（build 里 `sens_enable` 仍控制）。去掉手写四场。

`pipeline_default_sensitivity_scenarios`：

```r
pipeline_default_sensitivity_scenarios <- function(cfg = list()) {
  alias <- (cfg$capability %||% list())$variable_aliases %||% list()
  age_v <- as.character(alias$age %||% "Age")[1L]
  cut <- as.integer(
    (cfg$incidence_batch %||% list())$sensitivity_suite$age_cutoff %||%
      (cfg$survival_batch %||% list())$sensitivity_suite$age_cutoff %||% 65
  )[1L]
  list(
    list(name = "age_lt", label = sprintf("SA_age_lt_%s", cut),
         expr = sprintf("as.numeric(%s) < %s", age_v, cut),
         required_vars = age_v),
    list(name = "age_ge", label = sprintf("SA_age_ge_%s", cut),
         expr = sprintf("as.numeric(%s) >= %s", age_v, cut),
         required_vars = age_v)
  )
}
```

双库 Yes/No 发现**不要**放进这个无数据的 default（没有 Table 1 会误生成）。

brief 第五节改成：

- 轻量：主分析插补后删人，只重跑 Table 1/Table 2
- 场景来自 Table 1 Yes/No（两库 Yes>50）+ 年龄分层
- 目录 `【success】`/`【failed】`
- 表 S12/S13

reference.md 表格「排除 HTN/DM、年龄分层」改为上述口径。

- [ ] **Step 1: 改文件**
- [ ] **Step 2: 追加测试**

```r
src_tpl <- paste(readLines("configs/templates/config_incidence_dual_batch.template.R", warn = FALSE), collapse = "\n")
stopifnot(!grepl("SA_no_hypertension", src_tpl))
stopifnot(grepl("min_yes_n", src_tpl))
src_b <- paste(readLines("configs/study_interface/incidence_dual_batch_build.R", warn = FALSE), collapse = "\n")
stopifnot(!grepl("SA_no_hypertension", src_b))
defs <- pipeline_default_sensitivity_scenarios(list())
labs <- vapply(defs, function(s) s$label, character(1))
stopifnot(any(grepl("age_lt", labs)))
stopifnot(!any(grepl("hypertension", labs, ignore.case = TRUE)))
```

- [ ] **Step 3: Run all related tests**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript tests/test_incidence_sensitivity_light.R
Rscript tests/test_result_review_guards.R
```

Expected: 全部 PASS，无 `SA_no_hypertension` 残留在新 template/build。

本任务不跑 `python3 scripts/update_blocks_catalog.py`（没有新 `register_block`）。若只改了 MANUAL 程序员说明，手改 `docs/Blocks_catalog.md` 的 ROUTINES/PITFALLS 里「敏感性写死四场」的句子（若存在）。

```bash
rg -n "SA_no_hypertension|排除高血压/糖尿病" docs/Blocks_catalog.md skills/deploy-programmer-interface/reference.md Decisiontree/decision_tree_incidence_dual_batch.md || true
```

命中则改成新口径，避免文档继续教人写死四场。

---

## Spec coverage（自检）

| Spec | Task |
|------|------|
| Yes/No 动态、两库 Yes n>50 | 2 |
| 只删 Yes、留 NA | 1 expr + 2 |
| 年龄分层 cutoff 可配 | 2, 7 |
| 忽略旧 scenarios | 1 resolve + 7 |
| 用主分析 imputed，不插补 | 3, 5, 6 |
| 只 Table 1 + 选中档 Table 2 | 4, 6 |
| 锁 M1/M2，删单水平 | 4, 5 |
| `【success】`/`【failed】` 目录 | 5 |
| S12/S13 + Sensitivity analysis + 中文描述 | 1, 5 |
| Model2 NS → failed 仍出表 | 1 judge + 5 |
| 发病+预后 worker | 6 |
| template/build/docs | 7 |

无 TBD。函数名前后任务一致：`incidence_sensitivity_*`。
