# EMs Tertile + Illustrator Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify ML continuous exposures to tertiles across Cox/KM/subgroup, emit AI-editable PDF+SVG, fix SHAP labels and Figure 3 C/D calibration, then wipe and full-rerun EMs study.

**Architecture:** Add shared tertile helpers in `R/pipeline_capability_layer.R`; make Cox write shared cutpoints; KM already reads them; prognosis subgroup uses stored tertiles instead of median high/low; figure queue dual-writes PDF+SVG; SHAP display-only underscore strip; calibration plot stops double-scaling percent units.

**Tech Stack:** R 4.5.1, `survival`, `ggplot2`, `svglite`, `PredictABEL`, existing medical-blocks pipeline.

## Global Constraints

- Continuous ML features must all use method `tertile` (T1/T2/T3).
- Never silently drop a continuous ML feature from Cox because of duplicate quantile breaks.
- Mediation keeps raw continuous exposures.
- Figures must emit both PDF and SVG (svglite required; fail loudly if missing).
- Full wipe of study outputs/checkpoints then complete rerun; keep `Data/`, `config.R`, `run_ml.R`.

---

### Task 1: Shared tertile cutpoint helpers

**Files:**
- Modify: `R/pipeline_capability_layer.R`
- Test: inline Rscript smoke using EMs Total_Tx_Duration distribution

**Interfaces:**
- Produces: `pipeline_quantile_breaks(x, method)`, `pipeline_tertile_factor(x, breaks=NULL)`, `pipeline_store_continuous_km_cutpoints(...)` already exists and must accept tertile labels

- [ ] **Step 1: Ensure `pipeline_quantile_breaks` supports tertile**

```r
pipeline_quantile_breaks <- function(x, method = c("quartile", "tertile", "median")) {
  method <- match.arg(method)
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (length(x) < 3L) return(NULL)
  probs <- switch(
    method,
    quartile = c(0, 0.25, 0.5, 0.75, 1),
    tertile  = c(0, 1/3, 2/3, 1),
    median   = c(0, 0.5, 1)
  )
  br <- as.numeric(stats::quantile(x, probs = probs, na.rm = TRUE, type = 7))
  # keep min/max; de-duplicate only by tiny float tolerance later in consumers
  br
}
```

- [ ] **Step 2: Add tertile factor builder with rank fallback**

```r
pipeline_tertile_factor <- function(x, breaks = NULL) {
  x <- as.numeric(x)
  labs <- c("T1", "T2", "T3")
  if (is.null(breaks)) breaks <- pipeline_quantile_breaks(x, "tertile")
  br <- as.numeric(breaks)
  br_inner <- unique(br[-c(1L, length(br))])
  if (length(br_inner) >= 2L) {
    g <- cut(x, breaks = unique(c(-Inf, br_inner, Inf)),
             labels = labs, include.lowest = TRUE, right = FALSE)
    if (nlevels(droplevels(g[!is.na(g)])) >= 3L) return(factor(g, levels = labs))
  }
  # rank fallback: equal-frequency 3 groups
  r <- rank(x, ties.method = "first", na.last = "keep")
  n <- sum(is.finite(r))
  if (n < 3L) stop("无法为连续变量形成三分位组", call. = FALSE)
  q <- ceiling(3 * r / n)
  q[q < 1] <- 1; q[q > 3] <- 3
  factor(labs[q], levels = labs)
}
```

- [ ] **Step 3: Smoke-test on synthetic Total_Tx-like values**

Run:

```bash
RSCRIPT='/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe'
"$RSCRIPT" -e 'source("E:/01block/01Block-new-Final/R/pipeline_capability_layer.R");
x<-c(rep(0,400), rep(3,200), rep(6,200), rep(96,69));
br<-pipeline_quantile_breaks(x,"tertile"); print(br);
g<-pipeline_tertile_factor(x,br); print(table(g,useNA="ifany"));
stopifnot(nlevels(droplevels(g))==3)'
```

Expected: non-error, three non-empty T1/T2/T3 counts.

---

### Task 2: Cox continuous batch uses shared tertiles for all 4 features

**Files:**
- Modify: `Blocks/10_cox/08block_cox_ml_continuous_batch.R`
- Modify: `studies/.../config.R` (`cox_ml_continuous_batch$method="tertile"`)

**Interfaces:**
- Consumes: `pipeline_quantile_breaks`, `pipeline_tertile_factor`, `pipeline_store_continuous_km_cutpoints`
- Produces: Cox table with 4 continuous sections; `ctx$results$cox_ml_continuous_batch_features`; stored cutpoints

- [ ] **Step 1: Change quartile helper to tertile groups**

Replace `.cml08_quartile_table` grouping with:

```r
method <- "tertile"
gfac <- pipeline_tertile_factor(data[[index_var]])
d$Group <- gfac
d$Num <- as.numeric(d$Group)
group_labels <- levels(gfac)  # T1 T2 T3
# continuous model unchanged; grouped models use Group/Num
```

- [ ] **Step 2: Always store cuts before table build; never `next` on failed grouped table without continuous fallback**

```r
br <- pipeline_quantile_breaks(data2[[v]], method = "tertile")
ctx <- pipeline_store_continuous_km_cutpoints(ctx, v, br, method = "tertile")
tb <- tryCatch(.cml08_tertile_table(...), error=function(e) NULL)
if (is.null(tb)) stop("cox_ml_continuous_batch: ", v, " 未能生成三分位/连续 Cox 表", call.=FALSE)
```

- [ ] **Step 3: Count successes only after actual table rows appended**

Log must print the same number as sections in the exported table.

- [ ] **Step 4: Config**

```r
config$cox_ml_continuous_batch <- list(
  enable = TRUE,
  method = "tertile",
  time_var = "RFS_Months",
  event_var = "Is_Recurrence_factor",
  table_title = "Cox regression for ML continuous features (tertile, RFS)"
)
config$km_continuous <- list(
  enable = TRUE,
  method = "tertile",
  time_var = "RFS_Months",
  event_var = "Is_Recurrence_factor",
  single_use_main_figure = FALSE
)
```

---

### Task 3: KM + prognosis subgroup share tertile cutpoints

**Files:**
- Modify: `Blocks/27_KM/03block_km_continuous_router.R` (default method `tertile` when config set; keep existing cutpoint loader)
- Modify: `Blocks/18_subgroup/01block_subgroup_prognosis.R` exposure dichotomization section

- [ ] **Step 1: KM router preference**

Use `bl$method %||% "tertile"` and prefer stored cutpoints from Cox. If stored method mismatches, recompute with tertile.

- [ ] **Step 2: Prognosis subgroup continuous exposure uses stored tertiles**

Replace median high/low with:

```r
store <- ctx$results$continuous_km_cutpoints[[index_var]]
br <- store$breaks
rt[[index_var]] <- pipeline_tertile_factor(
  as.numeric(as.character(rt[[index_var]])),
  breaks = br
)
cli::cli_alert_info("分类/连续暴露 {.field {index_var}} 使用三分位: {paste(levels(rt[[index_var]]), collapse=', ')}")
```

For already-categorical exposures, keep previous dichotomize_majority / keep_levels behavior.

---

### Task 4: Dual PDF+SVG figure export

**Files:**
- Modify: `R/utils.R` (`render_queued_figures`, optionally `save_figure`)
- Modify: `R/subgroup_forest_plot.R` page writer to also emit SVG pages

- [ ] **Step 1: After PDF write, write SVG**

```r
svg_path <- sub("\\.pdf$", ".svg", out_path, ignore.case = TRUE)
if (!requireNamespace("svglite", quietly = TRUE)) {
  stop("需要 svglite 以输出 Illustrator 可编辑 SVG: ", svg_path, call. = FALSE)
}
svglite::svglite(svg_path, width = it$width, height = it$height)
# same theme/print as PDF
it$plot_fn()
grDevices::dev.off()
```

- [ ] **Step 2: PDF remains `useDingbats=FALSE`**

Keep current `grDevices::pdf(..., useDingbats=FALSE)`.

- [ ] **Step 3: Subgroup multipage**

For each page PDF temp, also write `..._pXX.svg`; after combine PDF, copy/keep SVGs under Figures.

---

### Task 5: SHAP display labels without underscores

**Files:**
- Modify: `Blocks/17_shap/01block_shap.R`

- [ ] **Step 1: Add display label helper**

```r
.shap_pretty_label <- function(x) {
  gsub("_", " ", as.character(x), fixed = TRUE)
}
```

- [ ] **Step 2: Apply only to plot titles / axis labels / waterfall feature names for display**

Before plotting, create a copy of shapviz object or rename display columns via `ggplot2` scales / labellers so matrix column names used for computation remain original.

Minimal approach when building plots:

```r
# after subset, rename X/col names used by shapviz plots only
disp <- .shap_pretty_label(colnames(X_df))
colnames(X_df) <- disp
# rebuild shapviz with renamed columns for plotting only
```

Ensure this happens after alignment/subsetting.

---

### Task 6: Fix Figure 3 C/D calibration empty panels

**Files:**
- Modify: `Blocks/23_ml_performance/01block_performance_ml.R` (`.pm_calibration_plot`)

- [ ] **Step 1: Stop double-percent scaling**

```r
# PredictABEL Table_HLtest meanpred/meanobs already in percent [0,100]
ggplot2::aes(x = .data$meanpred, y = .data$meanobs, colour = .data$model)
```

- [ ] **Step 2: Guard empty/invalid tables**

```r
caldf$meanpred <- as.numeric(caldf$meanpred)
caldf$meanobs  <- as.numeric(caldf$meanobs)
caldf <- caldf[is.finite(caldf$meanpred) & is.finite(caldf$meanobs), , drop=FALSE]
if (!nrow(caldf)) next
```

- [ ] **Step 3: Quick unit check**

Rscript: feed fake HL table with meanpred=20,meanobs=25; expect points not filtered by 0–100 scale.

---

### Task 7: Wipe study artifacts and full rerun

**Files:**
- Study root: `/mnt/g/DockerHome/5003/medical-blocks-studies/studies/01_EMs_ml_40395549`

- [ ] **Step 1: Kill any lingering EMs Rscript only (Windows process filter)**

- [ ] **Step 2: Delete `checkpoints/`, `step*`, `Figures/`, `Tables/`, old logs; recreate empty `Figures/` `Tables/` `checkpoints/`**

- [ ] **Step 3: Full `run_ml.R` without `--from`**

- [ ] **Step 4: Verify checklist from design spec**

1. EXIT=0
2. Cox table has 4 continuous vars with T1/T2/T3
3. KM legends T1/T2/T3 for 4 vars
4. Continuous-exposure subgroup uses T1/T2/T3
5. SHAP labels no underscores
6. Fig3 C/D has points (no mass removed-outside-scale warning for all models)
7. Matching SVG beside major PDFs
8. No leftover incidence/OR univariate artifacts

---

## Spec coverage checklist

- Unified tertile contract → Tasks 1–3
- Always keep 4 continuous Cox vars → Task 2
- KM + subgroup share cuts → Task 3
- PDF+SVG AI-editable → Task 4
- SHAP underscore strip → Task 5
- Fig3 C/D fix → Task 6
- Wipe + full rerun → Task 7
