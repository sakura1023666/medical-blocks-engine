#!/usr/bin/env Rscript
# 将胆结石汇总表导出为发病套路同款 SCI 三线表 xlsx（export_sci_table / booktabs）
# 主序只留 .xlsx；裸 CSV 进 _archive
#
# Rscript run/gallstone_nomogram/export_tables_sci_xlsx.R \
#   --project /mnt/g/02block_result/45_Gallstone/Nomogram_41815074

`%||%` <- function(a, b) if (!is.null(a)) a else b
.args <- commandArgs(trailingOnly = TRUE)
.proj <- {
  i <- match("--project", .args)
  if (!is.na(i) && i < length(.args)) .args[[i + 1L]] else
    "/mnt/g/02block_result/45_Gallstone/Nomogram_41815074"
}
.proj <- normalizePath(.proj, winslash = "/", mustWork = TRUE)
.root <- {
  if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else getwd()
}

suppressPackageStartupMessages({
  library(dplyr)
  library(gtsummary)
})
source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/literature_gallstone_nomogram.R"), local = FALSE)

.sum <- file.path(.proj, "summary_results")
.tab <- file.path(.sum, "Tables")
.arch <- file.path(.tab, "_archive")
dir.create(.tab, recursive = TRUE, showWarnings = FALSE)
dir.create(.arch, recursive = TRUE, showWarnings = FALSE)

.message <- function(...) message(paste0(...))
.safe_copy <- function(from, to) {
  if (!file.exists(from)) return(FALSE)
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  fn <- normalizePath(from, winslash = "/", mustWork = FALSE)
  tn <- normalizePath(to, winslash = "/", mustWork = FALSE)
  if (identical(fn, tn)) return(TRUE)
  isTRUE(file.copy(from, to, overwrite = TRUE))
}
.archive_csv_keep_xlsx <- function() {
  fs <- list.files(.tab, pattern = "\\.csv$", full.names = TRUE)
  for (f in fs) {
    .safe_copy(f, file.path(.arch, basename(f)))
    unlink(f)
  }
}

# 展示名清洗：走引擎 pipeline_scrub_pub_df（全项目复用）
.export_sci <- function(df, stem, title = stem, footnotes = NULL) {
  path <- file.path(.tab, paste0(stem, ".xlsx"))
  if (exists("pipeline_scrub_pub_df", mode = "function")) {
    df <- pipeline_scrub_pub_df(df, label_map = .lbl)
  }
  if (!is.null(footnotes) && exists("pipeline_scrub_pub_text", mode = "function")) {
    footnotes <- pipeline_scrub_pub_text(footnotes)
  }
  # 发病套路：SCI 三线 xlsx
  if (exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    sci_xlsx_single_header_booktabs(
      path, title, df, sheet = "Table",
      footnotes = footnotes
    )
  } else if (exists("export_sci_table", mode = "function") &&
             exists("render_queued_tables", mode = "function")) {
    export_sci_table(df, path, title = title, table_footnotes = footnotes)
    ctx <- list(
      config = list(project = list(root = .proj, mirror_pub_outputs_to_root = FALSE)),
      output_dir = .sum,
      output_dir_tables = .tab
    )
    render_queued_tables(ctx)
  } else {
    openxlsx::write.xlsx(df, path, overwrite = TRUE)
  }
  .message("xlsx: ", basename(path))
  invisible(path)
}

# ---------- data ----------
.out <- "Success"
.xlsx <- file.path(.proj, "data", "gallstone_features.xlsx")
.df0 <- gallstone_nomogram_read_xlsx(.xlsx)
.df <- gallstone_collapse_stone_type(.df0, .out)
.y01 <- function(d) {
  y <- d[[.out]]
  if (is.factor(y)) as.integer(y == "Yes" | y == levels(y)[length(levels(y))])
  else as.integer(as.numeric(y) == 1L)
}
.df$.y <- .y01(.df)
.df[[.out]] <- factor(
  ifelse(.df$.y == 1L, "Yes", "No"),
  levels = c("No", "Yes")
)

.prespec <- c("Age", "diameter_cm", "volume_cm3", "energy_j", "shots")
.cats <- intersect(c("Sex", "shape", "color", "surface", "stone_type"), names(.df))
.conts_extra <- intersect(c("ct_min", "ct_max", "pct_lt40", "pct_40_80", "pct_gt80"), names(.df))
# Age 置顶（其余连续预指定 → 分类 → 探索性 CT）
.vars_t1 <- unique(c(
  "Age",
  setdiff(.prespec, "Age"),
  .cats,
  .conts_extra
))
.vars_t1 <- .vars_t1[.vars_t1 %in% names(.df)]

.lbl <- if (exists("gallstone_nomogram_display_labels", mode = "function")) {
  gallstone_nomogram_display_labels()
} else {
  c(
    Age = "Age, y", Sex = "Sex",
    diameter_cm = "Diameter, cm", volume_cm3 = "Volume, cm3",
    energy_j = "Energy, J", shots = "Shots, n",
    shape = "Shape", color = "Color", surface = "Surface",
    stone_type = "Stone type",
    ct_min = "CT min, HU", ct_max = "CT max, HU",
    pct_lt40 = "CT <40 HU, %", pct_40_80 = "CT 40-80 HU, %",
    pct_gt80 = "CT >80 HU, %"
  )
}

# train/val split（与 Methods 人数对齐）
.set_seed <- 42L
set.seed(.set_seed)
.n <- nrow(.df)
.tr_n <- {
  note <- file.path(.proj, "Tables", "Methods_split_denominator_note.txt")
  if (file.exists(note)) {
    ln <- readLines(note, warn = FALSE)
    hit <- grep("^train_n=", ln, value = TRUE)
    if (length(hit)) as.integer(sub(".*=", "", hit[[1]])) else floor(0.7 * .n)
  } else floor(0.7 * .n)
}
.idx <- sample.int(.n, size = min(.tr_n, .n))
.df$Set <- factor("Validation", levels = c("Training", "Validation"))
.df$Set[.idx] <- "Training"

.fmt_p <- function(p) {
  p <- as.numeric(p)
  ifelse(!is.finite(p), "—",
         ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}

# ---------- Table 1：按 Success 分层（发病套路 gtsummary 宽表）----------
.message("→ Table 1 SCI xlsx (by Success) …")
.d1 <- .df[, c(.out, .vars_t1), drop = FALSE]
for (cc in .cats) .d1[[cc]] <- factor(.d1[[cc]])
# 预指定/CT 连续变量强制 continuous（避免 energy_j 仅 5 个取值被当成分类）
.cont_force <- intersect(c(.prespec, .conts_extra), names(.d1))
for (vv in .cont_force) .d1[[vv]] <- as.numeric(.d1[[vv]])
.tbl1 <- .d1 %>%
  tbl_summary(
    by = all_of(.out),
    include = all_of(.vars_t1),
    type = c(all_of(.cont_force) ~ "continuous"),
    statistic = list(
      all_continuous() ~ "{mean} ({sd})",
      all_categorical() ~ "{n} ({p}%)"
    ),
    digits = list(all_continuous() ~ 2, all_categorical() ~ c(0, 1)),
    label = as.list(.lbl[intersect(names(.lbl), .vars_t1)]),
    missing = "no"
  ) %>%
  add_overall() %>%
  add_p(
    test = list(
      all_continuous() ~ "t.test",
      all_categorical() ~ "chisq.test"
    )
  ) %>%
  modify_header(
    label ~ "**Characteristic**",
    all_stat_cols() ~ "**{level}**\nN = {n}"
  ) %>%
  bold_labels()
.df1 <- as.data.frame(.tbl1)
# 规范列名（对标发病 Table1：Overall N = … / 分层 N = …）
names(.df1)[1] <- "Characteristic"
.n_all <- nrow(.d1)
.n_no <- sum(.d1[[.out]] == "No", na.rm = TRUE)
.n_yes <- sum(.d1[[.out]] == "Yes", na.rm = TRUE)
.fmt_n <- function(n) {
  if (exists("pub_format_int", mode = "function")) pub_format_int(n) else format(n, big.mark = ",", scientific = FALSE)
}
if (ncol(.df1) >= 5) {
  names(.df1)[2:5] <- c(
    paste0("Overall N = ", .fmt_n(.n_all)),
    paste0("No N = ", .fmt_n(.n_no)),
    paste0("Yes N = ", .fmt_n(.n_yes)),
    "P value"
  )
} else if (ncol(.df1) >= 4) {
  names(.df1)[2:4] <- c(
    paste0("Overall N = ", .fmt_n(.n_all)),
    paste0("No N = ", .fmt_n(.n_no)),
    paste0("Yes N = ", .fmt_n(.n_yes))
  )
}
# P 格式化
if ("P value" %in% names(.df1)) {
  .df1[["P value"]] <- vapply(.df1[["P value"]], function(x) {
    x <- as.character(x)
    if (!nzchar(trimws(x)) || x %in% c("NA", "—")) return("")
    # gtsummary 可能已是 <0.001
    if (grepl("^<", x) || grepl("^[0-9]", x)) {
      px <- suppressWarnings(as.numeric(gsub("[^0-9.eE+-]", "", x)))
      if (is.finite(px)) return(.fmt_p(px))
      return(x)
    }
    x
  }, character(1))
}
.t1_stem <- "Table 1. Baseline characteristics of the participants"
.t1_title <- .t1_stem
.t1_fn <- c(
  "Values are mean (SD) for continuous variables and n (%) for categorical variables.",
  "P values compare Success = No vs Yes (t-test / chi-square).",
  "Outcome = lithotripsy success."
)
# 优先 guan-style Table1（与发病 baseline_binary 同路）
.t1_path <- file.path(.tab, paste0(.t1_stem, ".xlsx"))
.ok_t1 <- FALSE
if (exists("write_table1_xlsx_guan_style", mode = "function") &&
    exists("table1_build_display_df", mode = "function")) {
  tryCatch({
    built <- table1_build_display_df(
      .df1,
      section_insert_rows = NULL,
      gtsummary_tbl = .tbl1
    )
    write_table1_xlsx_guan_style(
      .df1, .t1_path, .t1_title,
      footnotes = .t1_fn, prebuilt = built
    )
    .ok_t1 <- TRUE
    .message("Table 1 guan-style ok")
  }, error = function(e) .message("Table1 guan-style fail: ", conditionMessage(e)))
}
if (!.ok_t1) {
  .export_sci(.df1, .t1_stem, .t1_title, footnotes = .t1_fn)
}

# ---------- Table 2：Training vs Validation ----------
.message("→ Table 2 SCI xlsx (train vs validation) …")
.d2 <- .df[, c("Set", .vars_t1), drop = FALSE]
for (cc in .cats) .d2[[cc]] <- factor(.d2[[cc]])
for (vv in intersect(.cont_force, names(.d2))) .d2[[vv]] <- as.numeric(.d2[[vv]])
.tbl2 <- .d2 %>%
  tbl_summary(
    by = Set,
    include = all_of(.vars_t1),
    type = c(all_of(intersect(.cont_force, names(.d2))) ~ "continuous"),
    statistic = list(
      all_continuous() ~ "{mean} ({sd})",
      all_categorical() ~ "{n} ({p}%)"
    ),
    digits = list(all_continuous() ~ 2, all_categorical() ~ c(0, 1)),
    label = as.list(.lbl[intersect(names(.lbl), .vars_t1)]),
    missing = "no"
  ) %>%
  add_p(
    test = list(
      all_continuous() ~ "t.test",
      all_categorical() ~ "chisq.test"
    )
  ) %>%
  modify_header(
    label ~ "**Characteristic**",
    all_stat_cols() ~ "**{level}**\nN = {n}"
  ) %>%
  bold_labels()
.df2 <- as.data.frame(.tbl2)
names(.df2)[1] <- "Characteristic"
.n_tr <- sum(.d2$Set == "Training", na.rm = TRUE)
.n_va <- sum(.d2$Set == "Validation", na.rm = TRUE)
.fmt_n2 <- function(n) {
  if (exists("pub_format_int", mode = "function")) pub_format_int(n) else format(n, big.mark = ",", scientific = FALSE)
}
if (ncol(.df2) >= 4) {
  names(.df2)[2:4] <- c(
    paste0("Training N = ", .fmt_n2(.n_tr)),
    paste0("Validation N = ", .fmt_n2(.n_va)),
    "P value"
  )
}
if ("P value" %in% names(.df2)) {
  .df2[["P value"]] <- vapply(.df2[["P value"]], function(x) {
    x <- as.character(x)
    if (!nzchar(trimws(x)) || x %in% c("NA", "—")) return("")
    px <- suppressWarnings(as.numeric(gsub("[^0-9.eE+-]", "", x)))
    if (is.finite(px)) .fmt_p(px) else x
  }, character(1))
}
.t2_stem <- "Table 2. Baseline characteristics between training and validation sets"
.t2_fn <- c(
  "Values are mean (SD) or n (%).",
  "P values compare Training vs Validation.",
  "Split seed = 42; train:validation ratio aligned with Methods split denominator note."
)
.t2_path <- file.path(.tab, paste0(.t2_stem, ".xlsx"))
.ok_t2 <- FALSE
if (exists("write_table1_xlsx_guan_style", mode = "function") &&
    exists("table1_build_display_df", mode = "function")) {
  tryCatch({
    built2 <- table1_build_display_df(
      .df2, section_insert_rows = NULL, gtsummary_tbl = .tbl2
    )
    write_table1_xlsx_guan_style(
      .df2, .t2_path, .t2_stem,
      footnotes = .t2_fn, prebuilt = built2
    )
    .ok_t2 <- TRUE
    .message("Table 2 guan-style ok")
  }, error = function(e) .message("Table2 guan-style fail: ", conditionMessage(e)))
}
if (!.ok_t2) .export_sci(.df2, .t2_stem, .t2_stem, footnotes = .t2_fn)

# ---------- Table S1 ----------
.message("→ Table S1 …")
.s1_csv <- file.path(.tab, "Table S1. Descriptions and assessments of the variables.csv")
if (!file.exists(.s1_csv)) .s1_csv <- file.path(.arch, basename(.s1_csv))
if (!file.exists(.s1_csv)) {
  # regenerate minimal
  .s1 <- data.frame(
    Variable = c("Success", .prespec, .cats),
    Label = c("Lithotripsy success", .lbl[.prespec], .lbl[.cats]),
    Description_and_assessment = c(
      "Binary endpoint: lithotripsy success (Yes/No).",
      rep("See Methods.", length(.prespec) + length(.cats))
    ),
    Role = c("Outcome", rep("Nomogram predictor", length(.prespec)),
             rep("Baseline / subgroup", length(.cats))),
    stringsAsFactors = FALSE
  )
} else {
  .s1 <- utils::read.csv(.s1_csv, stringsAsFactors = FALSE)
}
.export_sci(
  .s1,
  "Table S1. Descriptions and assessments of the variables",
  footnotes = "Aligned with Chen Supplemental Table 1 (variable dictionary)."
)

# ---------- Table S2 ----------
.message("→ Table S2 …")
.s2_csv <- file.path(.tab, "Table S2. Variance inflation factors between variables.csv")
if (!file.exists(.s2_csv)) .s2_csv <- file.path(.arch, basename(.s2_csv))
if (file.exists(.s2_csv)) {
  .s2 <- utils::read.csv(.s2_csv, stringsAsFactors = FALSE)
} else {
  .use <- .prespec[.prespec %in% names(.df)]
  .dtr <- .df[.df$Set == "Training", c(".y", .use), drop = FALSE]
  .fit <- stats::glm(
    stats::as.formula(paste(".y ~", paste(.use, collapse = "+"))),
    data = .dtr, family = stats::binomial()
  )
  if (requireNamespace("car", quietly = TRUE)) {
    vf <- car::vif(.fit)
    .s2 <- data.frame(Variable = names(vf), VIF = as.numeric(vf), stringsAsFactors = FALSE)
  } else {
    .s2 <- data.frame(Variable = .use, VIF = NA_real_)
  }
}
# round VIF
if ("VIF" %in% names(.s2)) .s2$VIF <- round(as.numeric(.s2$VIF), 3)
.export_sci(
  .s2,
  "Table S2. Variance inflation factors between variables",
  footnotes = "VIF from multivariable logistic model of prespecified predictors on the training set."
)

# ---------- Table S3 ----------
.message("→ Table S3 …")
.s3_csv <- file.path(.tab, "Table S3. Association of features with lithotripsy success (Model 1-3).csv")
if (!file.exists(.s3_csv)) .s3_csv <- file.path(.arch, basename(.s3_csv))
if (!file.exists(.s3_csv)) {
  .s3_csv <- file.path(.arch, "Table_assoc_OR_Model123_all.csv")
}
if (file.exists(.s3_csv) && grepl("Model 1-3", basename(.s3_csv))) {
  .s3 <- utils::read.csv(.s3_csv, stringsAsFactors = FALSE)
} else if (file.exists(file.path(.arch, "Table_assoc_OR_Model123_all.csv"))) {
  a <- utils::read.csv(file.path(.arch, "Table_assoc_OR_Model123_all.csv"), stringsAsFactors = FALSE)
  mk <- function(mod, pref) {
    sub <- a[a$model == mod, , drop = FALSE]
    out <- data.frame(
      feature = sub$feature,
      OR_CI = sub$OR_CI,
      P = ifelse(is.finite(sub$P) & sub$P < 0.001, "<0.001",
                 ifelse(is.finite(sub$P), sprintf("%.3f", sub$P), "—")),
      stringsAsFactors = FALSE
    )
    names(out)[2:3] <- paste0(pref, c("_OR (95%CI)", "_P"))
    out
  }
  .s3 <- Reduce(function(x, y) merge(x, y, by = "feature", all = TRUE),
                list(mk("Model1", "Model1"), mk("Model2", "Model2"), mk("Model3", "Model3")))
  .ord <- c(.prespec, setdiff(unique(a$feature), .prespec))
  .s3 <- .s3[match(intersect(.ord, .s3$feature), .s3$feature), , drop = FALSE]
} else {
  stop("missing S3 source")
}
names(.s3)[names(.s3) == "feature"] <- "Variable"
.export_sci(
  .s3,
  "Table S3. Association of features with lithotripsy success (Model 1-3)",
  footnotes = c(
    "OR per 1-SD increase for continuous predictors unless otherwise noted.",
    "Model 1: crude; Model 2/3: covariate sets as in Methods.",
    "Aligned with Chen Supplemental Table 3 layout."
  )
)

# ---------- Table S4 ----------
.message("→ Table S4 …")
.s4_csv <- file.path(.tab, "Table S4. Characteristics of predictors between training and validation sets.csv")
if (!file.exists(.s4_csv)) .s4_csv <- file.path(.arch, basename(.s4_csv))
# Prefer rebuild from gtsummary subset of predictors only
.d4 <- .df[, c("Set", .prespec[.prespec %in% names(.df)]), drop = FALSE]
.tbl4 <- .d4 %>%
  tbl_summary(
    by = Set,
    statistic = list(all_continuous() ~ "{mean} ({sd})"),
    digits = list(all_continuous() ~ 2),
    label = as.list(.lbl[intersect(names(.lbl), names(.d4))]),
    missing = "no"
  ) %>%
  add_p(test = list(all_continuous() ~ "t.test")) %>%
  modify_header(label ~ "**Characteristic**", all_stat_cols() ~ "**{level}**\nN = {n}") %>%
  bold_labels()
.df4 <- as.data.frame(.tbl4)
names(.df4)[1] <- "Characteristic"
.n_tr4 <- sum(.d4$Set == "Training", na.rm = TRUE)
.n_va4 <- sum(.d4$Set == "Validation", na.rm = TRUE)
.fmt_n4 <- function(n) {
  if (exists("pub_format_int", mode = "function")) pub_format_int(n) else format(n, big.mark = ",", scientific = FALSE)
}
if (ncol(.df4) >= 4) {
  names(.df4)[2:4] <- c(
    paste0("Training N = ", .fmt_n4(.n_tr4)),
    paste0("Validation N = ", .fmt_n4(.n_va4)),
    "P value"
  )
}
if ("P value" %in% names(.df4)) {
  .df4[["P value"]] <- vapply(.df4[["P value"]], function(x) {
    x <- as.character(x)
    if (!nzchar(trimws(x))) return("")
    px <- suppressWarnings(as.numeric(gsub("[^0-9.eE+-]", "", x)))
    if (is.finite(px)) .fmt_p(px) else x
  }, character(1))
}
.export_sci(
  .df4,
  "Table S4. Characteristics of predictors between training and validation sets",
  footnotes = c(
    "Prespecified nomogram predictors only.",
    "Chen Supplemental Table 4 used external validation; this study reports internal validation."
  )
)

# ---------- archive CSVs; keep only xlsx + README in main ----------
.message("→ archive bare CSV from publication Tables …")
.archive_csv_keep_xlsx()

writeLines(c(
  "# 发表表 — Chen 顺序 + 发病套路 SCI 三线 xlsx",
  "",
  "格式与发病 dual-batch 一致：`export_sci_table` / `sci_xlsx_single_header_booktabs`",
  "（Times、顶底粗线、无竖线；Table 1/2 优先 `write_table1_xlsx_guan_style`）。",
  "",
  "## 主文",
  "",
  "| 文件 | 对标 |",
  "|------|------|",
  "| `Table 1. Baseline characteristics of the participants.xlsx` | Chen Table 1 |",
  "| `Table 2. Baseline characteristics between training and validation sets.xlsx` | Chen Table 2 |",
  "",
  "## 补充",
  "",
  "| 文件 | 对标 |",
  "|------|------|",
  "| `Table S1. ….xlsx` | Supplemental Table 1 |",
  "| `Table S2. ….xlsx` | Supplemental Table 2 |",
  "| `Table S3. ….xlsx` | Supplemental Table 3 |",
  "| `Table S4. ….xlsx` | Supplemental Table 4（内验） |",
  "",
  "裸 CSV / Methods 中间表见 `_archive/`。多因素与 AUC 对应 Figure 5 / 7，不是主表。",
  ""
), file.path(.tab, "README.md"))
file.copy(file.path(.tab, "README.md"), file.path(.sum, "README.md"), overwrite = TRUE)

.message("DONE SCI xlsx tables:")
.message(paste(" -", list.files(.tab, pattern = "\\.xlsx$")))
