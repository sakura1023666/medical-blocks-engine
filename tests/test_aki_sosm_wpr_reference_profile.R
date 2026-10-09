#!/usr/bin/env Rscript
# Task 7 TDD tests: AKI SOSM+WPR 原文（PMID 40537296）复刻 profile、
# Figure 1 双库真实纳排、Table 1 双库 Panel、S1 AKI 队列定义证据。
# 规格：docs/superpowers/specs/2026-09-17-aki-sosm-wpr-original-paper-replication-design.md
root <- normalizePath(Sys.getenv(
  "MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final"
), winslash = "/")
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
suppressWarnings(suppressMessages({
  library(ggplot2)
  source(file.path(root, "R/utils.R"), local = FALSE)
  source(file.path(root, "R/attrition_log.R"), local = FALSE)
  source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
  source(file.path(root, "R/pub_xlsx_surgical.R"), local = FALSE)
  source(file.path(root, "R/ml_reference_paper_profile.R"), local = FALSE)
}))

expect_true <- function(x, msg) {
  if (!isTRUE(x)) stop("expected TRUE: ", msg, call. = FALSE)
  invisible(TRUE)
}
expect_error <- function(expr, pattern = NULL) {
  err <- tryCatch(force(expr), error = identity)
  if (!inherits(err, "error")) stop("expected error: ", deparse(substitute(expr)),
                                    call. = FALSE)
  if (!is.null(pattern)) {
    if (!grepl(pattern, conditionMessage(err), ignore.case = TRUE)) {
      stop("error message mismatch: ", conditionMessage(err), call. = FALSE)
    }
  }
  invisible(err)
}

# ===========================================================================
# 1) profile：固定编号清单
# ===========================================================================
prof <- ml_reference_profile_40537296()
expect_true(is.data.frame(prof), "profile is data.frame")
need_cols <- c("kind", "number", "role", "title", "db_mode",
               "reference_source", "adaptation")
expect_true(identical(names(prof), need_cols),
            paste("profile columns exact:", paste(names(prof), collapse = ",")))

# --- 编号连续、无重号 ---
key <- paste(prof$kind, prof$number)
expect_true(!anyDuplicated(key), "profile kind+number 无重号")
sel <- function(k) prof$number[prof$kind == k]
expect_true(identical(sel("figure_main"), as.character(1:8)),
            "主图 Figure 1-8 连续")
expect_true(identical(sel("figure_supp"), as.character(1:8)),
            "补图 Figure S1-S8 连续")
expect_true(identical(sel("table_main"), as.character(1:2)),
            "主表 Table 1-2 连续")
expect_true(identical(sel("table_supp"), as.character(1:16)),
            "补表 S1-S16 连续")
expect_true(nrow(prof) == 8L + 8L + 2L + 16L,
            paste("profile 行数 = 34, got", nrow(prof)))

# --- 角色映射（对照规格） ---
.role <- function(k, n) {
  hits <- lapply(n, function(nn) prof$role[prof$kind == k & prof$number == nn][1L])
  unlist(hits)
}
expect_true(grepl("flowchart|纳排|流程图", .role("figure_main", "1")), "Fig1 flowchart")
expect_true(grepl("^KM", .role("figure_main", "2")), "Fig2 KM")
expect_true(grepl("RCS", .role("figure_main", "3")), "Fig3 RCS")
expect_true(grepl("ROC", .role("figure_main", "4")), "Fig4 ROC")
expect_true(grepl("landmark", .role("figure_main", "5"), ignore.case = TRUE),
            "Fig5 landmark")
expect_true(grepl("forest|森林", .role("figure_main", "6")), "Fig6 forest")
expect_true(grepl("Boruta", .role("figure_main", "7")), "Fig7 分层Boruta")
expect_true(grepl("ROC", .role("figure_main", "8")) &&
              grepl("SHAP", .role("figure_main", "8")), "Fig8 分层ROC+SHAP")
expect_true(grepl("AKI", .role("table_supp", "1")), "S1 AKI队列定义")
expect_true(grepl("单因素|univariate", .role("table_supp", "2"), ignore.case = TRUE),
            "S2 UV Cox")
expect_true(grepl("VIF", .role("table_supp", "3")) &&
              grepl("继承", .role("table_supp", "3")), "S3 VIF/继承审计")
expect_true(grepl("Cox", .role("table_supp", "4")), "S4 指标Cox")
expect_true(grepl("判别", .role("table_supp", "5")), "S5 判别力")
expect_true(all(grepl("PH|比例风险", .role("table_supp", c("6", "7", "8")))),
            "S6-S8 PH")
expect_true(grepl("基线血糖|Glucose", .role("table_supp", "9")), "S9 基线血糖敏感性")
expect_true(grepl("完整病例|complete", .role("table_supp", "10"), ignore.case = TRUE),
            "S10 complete-case")
expect_true(grepl("分层", .role("table_supp", "11")) &&
              grepl("ML|机器学习", .role("table_supp", "11")), "S11 分层ML")
for (n in as.character(12:16)) {
  expect_true(grepl("本课题额外|额外", .role("table_supp", n)),
              paste("S", n, " 标注本课题额外"))
}
extra_roles <- .role("table_supp", c("12", "13", "14", "15", "16"))
expect_true(any(grepl("三集|train.*internal.*external|性能", extra_roles)),
            "S12-S16 含三集性能")
expect_true(any(grepl("超参", extra_roles)), "S12-S16 含超参")
expect_true(any(grepl("Log-?Loss", extra_roles, ignore.case = TRUE)), "含 LogLoss")
expect_true(any(grepl("DeLong", extra_roles, ignore.case = TRUE)), "含 DeLong")
expect_true(any(grepl("NRI", extra_roles)), "含 NRI")

# --- 角色唯一（同 kind 内） ---
for (k in unique(prof$kind)) {
  r <- prof$role[prof$kind == k]
  expect_true(!anyDuplicated(r), paste("角色在同 kind 内唯一:", k))
}

# --- 每项 reference_source / adaptation 非空 ---
expect_true(all(nzchar(prof$reference_source)), "reference_source 全非空")
expect_true(all(nzchar(prof$adaptation)), "adaptation 全非空")
expect_true(all(nzchar(prof$title)), "title 全非空")
expect_true(all(nzchar(prof$db_mode)), "db_mode 全非空")
# 全清单禁止出现 90 天口径（结局只有 28 天）；adaptation 已含 SOFA/28 天/S9 口径差异
blob <- unlist(prof, use.names = FALSE)
expect_true(!any(grepl("90[- ]?(day|天)", blob, ignore.case = TRUE)),
            "profile 无 90 天字样")

# ===========================================================================
# 2) Figure 1：真实双库 attrition
# ===========================================================================
STUDY_INDEX_ROOT <- Sys.getenv(
  "AKI_SOSM_WPR_INDEX_ROOT",
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/17_AKI_院内28天死亡预测预后_静/by_index/【success】SOSM+WPR"
)
mimic_csv <- file.path(STUDY_INDEX_ROOT,
  "MIMIC_IV/step37_attrition_flowchart/Tables/Flowchart_attrition_nhanes.csv")
eicu_csv <- file.path(STUDY_INDEX_ROOT,
  "eICU/step28_attrition_flowchart/Tables/Flowchart_attrition_mimic.csv")
expect_true(file.exists(mimic_csv) && file.exists(eicu_csv),
            "真实 attrition CSV 可读（G 盘）")

fr <- ml_reference_read_flowcharts(mimic_csv, eicu_csv)
expect_true(is.data.frame(fr$rows) && all(c("database", "step", "n") %in% names(fr$rows)),
            "rows 含 database/step/n")
# 槽名陷阱：CSV database 列写 nhanes/mimic，必须按【目录位置】判库
expect_true(identical(sort(unique(fr$rows$database), method = "radix"), c("MIMIC-IV", "eICU")),
            paste("库身份按目录判定:", paste(unique(fr$rows$database), collapse = ",")))
m_n <- fr$rows$n[fr$rows$database == "MIMIC-IV"]
e_n <- fr$rows$n[fr$rows$database == "eICU"]
expect_true(identical(as.integer(m_n), c(26055L, 19018L, 19018L, 18394L)),
            "MIMIC 人数 = 26055/19018/19018/18394")
expect_true(identical(as.integer(e_n), c(15270L, 15270L, 10558L)),
            "eICU 人数 = 15270/15270/10558")
expect_true(all(diff(m_n) <= 0) && all(diff(e_n) <= 0), "两库人数单调不增")

# 排除账本：每步排除人数 = 相邻步差额（写「本步排除 X 人」）
expect_true(is.data.frame(fr$exclusions) &&
              all(c("database", "step", "excluded") %in% names(fr$exclusions)),
            "exclusions 账本存在")
m_ex <- fr$exclusions$excluded[fr$exclusions$database == "MIMIC-IV"]
e_ex <- fr$exclusions$excluded[fr$exclusions$database == "eICU"]
expect_true(identical(as.integer(m_ex), c(7037L, 0L, 624L)), "MIMIC 逐步排除 7037/0/624")
expect_true(identical(as.integer(e_ex), c(0L, 4712L)), "eICU 逐步排除 0/4712")

# 缺 CSV / 不单调 硬失败
tmp <- tempfile(); dir.create(tmp)
expect_error(ml_reference_read_flowcharts(file.path(tmp, "nope.csv"), eicu_csv),
             "缺|missing")
bad_csv <- file.path(tmp, "bad.csv")
write.csv(data.frame(step = c("a", "b"), n = c(100, 200), source = "log",
                    kind = "include", step_id = c("s1", "s2"),
                    exclude_label = NA_character_, database = "x"),
          bad_csv, row.names = FALSE)
expect_error(ml_reference_read_flowcharts(bad_csv, eicu_csv), "单调|non-monotonic")
expect_error(ml_reference_read_flowcharts(mimic_csv, mimic_csv), "两库|both")

# 双栏 PDF（fixture：staging/task7/Figures）
out_dir <- file.path(root, ".superpowers/sdd/staging/task7")
fig1_pdf <- ml_reference_build_flowchart(mimic_csv, eicu_csv, out_dir)
expect_true(file.exists(fig1_pdf), "Figure 1 PDF 存在")
expect_true(grepl("Figure 1\\.", basename(fig1_pdf)), "文件名 Figure 1. ...")
expect_true(file.info(fig1_pdf)$size > 2000, "Figure 1 PDF 非空")
if (requireNamespace("pdftools", quietly = TRUE)) {
  txt <- paste(pdftools::pdf_text(fig1_pdf), collapse = " ")
  expect_true(grepl("26,?055", txt), "PDF 含 26055")
  expect_true(grepl("18,?394", txt), "PDF 含 18394")
  expect_true(grepl("15,?270", txt), "PDF 含 15270")
  expect_true(grepl("10,?558", txt), "PDF 含 10558")
  expect_true(grepl("MIMIC-IV", txt) && grepl("eICU", txt), "双 Panel 标题")
  expect_true(grepl("本步排除", txt), "含『本步排除 X 人』")
  # 不得把槽名 nhanes 当库印在图上
  expect_true(!grepl("NHANES", txt), "图面无 NHANES 槽名")
  # 排除人数写进图（7,037 / 4,712 / 624）
  expect_true(grepl("7,?037", txt) && grepl("4,?712", txt) && grepl("624", txt),
              "排除人数 7037/4712/624 上图")
}

# ===========================================================================
# 3) Table 1：双库 Panel A/B，Survivor/Non-survivor
# ===========================================================================
# 引擎夹具（与 Task4 测试同风格的 make_db）
set.seed(20260918)
make_db1 <- function(n, db) {
  age <- round(runif(n, 30, 95))
  gender <- factor(sample(c("Female", "Male"), n, TRUE))
  sofa <- pmin(24L, pmax(0L, round(rnorm(n, 8, 5))))
  sosm <- rnorm(n, 300 + 3 * sofa, 60)
  wpr <- rnorm(n, 1.2 + 0.02 * sofa, 0.45)
  ev <- as.integer(runif(n) < 0.15 + 0.004 * sofa)
  data.frame(
    ID = paste0(db, "_", seq_len(n)),
    Age = age, Gender = gender, SOFA = sofa, SOSM = sosm, WPR = wpr,
    fustatus = factor(ifelse(ev == 1, "Non-survivor", "Survivor"),
                      levels = c("Survivor", "Non-survivor")),
    stringsAsFactors = FALSE
  )
}
tab1 <- ml_reference_build_table1(
  list(MIMIC_IV = make_db1(400, "M"), eICU = make_db1(300, "E")),
  out_dir,
  vars = list(
    continuous = c("Age", "SOSM", "WPR"),
    categorical = c("Gender"),
    levels = list(Age = 50)
  )
)
expect_true(is.data.frame(tab1), "Table1 返回 data.frame")
expect_true("Panel" %in% names(tab1), "含 Panel 列")
labs <- unique(as.character(tab1$Panel))
expect_true(any(grepl("Panel A", labs)) && any(grepl("Panel B", labs)),
            "Panel A/B 齐全")
blob1 <- paste(unlist(tab1), collapse = " | ")
expect_true(grepl("Survivor", blob1) && grepl("Non-survivor", blob1),
            "含 Survivor/Non-survivor")
expect_true(grepl("Non-survivor N = ", blob1) && grepl("Survivor N = ", blob1),
            "列头为 Survivor/Non-survivor 分组")
expect_true(!grepl("No AKI", blob1, ignore.case = TRUE), "表体无 No AKI")
expect_true(!grepl("(^|[^A-Za-z])AKI N = ", blob1), "无 'AKI N =' 误写列头")
xlsx1 <- list.files(file.path(out_dir, "Tables"), pattern = "Table 1\\..*\\.xlsx$",
                    full.names = TRUE)
expect_true(length(xlsx1) >= 1, "Table 1 xlsx 落盘 staging/task7")
v <- pub_xlsx_verify(xlsx1[1])
expect_true(isTRUE(v$readable), "Table1 xlsx readable")
expect_true(identical(as.integer(v$corrupt_cells), 0L), "corrupt_cells=0")
expect_true(is.finite(v$styles) && v$styles > 0, "styles>0")
# 小数位 desc=2：描述统计单元（非 P 值列）两位小数；P 值列属 pub p=3 口径不计入
desc_cells <- unlist(tab1[, setdiff(names(tab1), c("p_value", "P", "p", "p-value")),
                          drop = FALSE])
desc_cells <- as.character(desc_cells[!is.na(desc_cells)])
pct <- regmatches(desc_cells,
                  regexpr("[0-9]+\\.[0-9]+%?", desc_cells, perl = TRUE))
digits <- suppressWarnings(nchar(sub(".*\\.", "", sub("%$", "", pct))))
digits <- digits[!is.na(digits)]
expect_true(length(digits) > 0 && all(digits <= 2),
            paste("描述统计 <=2 位小数, got:", paste(unique(digits), collapse = ",")))
# 排除任何 3 位小数出现在描述列（防误用 est=3）
expect_true(!any(grepl("[0-9]\\.[0-9]{3}", desc_cells)),
            "描述列无 3 位小数（应=2）")

# ===========================================================================
# 3b) Table 1 重排路径：读旧双库 Table1 xlsx（No AKI/AKI 误标签）→ Survivor/Non-survivor
# ===========================================================================
OLD_T1 <- Sys.getenv("AKI_SOSM_WPR_INDEX_ROOT",
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/17_AKI_院内28天死亡预测预后_静/by_index/【success】SOSM+WPR")
old_mimic_t1 <- file.path(OLD_T1,
  "Tables/Table 1-MIMIC IV. Baseline characteristics of AKI.xlsx")
old_eicu_t1 <- file.path(OLD_T1,
  "Tables/Table 1-eICU. Baseline characteristics of AKI.xlsx")
if (file.exists(old_mimic_t1) && file.exists(old_eicu_t1)) {
  t1x <- ml_reference_table1_from_existing(old_mimic_t1, old_eicu_t1, out_dir)
  expect_true(is.data.frame(t1x), "Table1 重排 data.frame")
  labs2 <- unique(as.character(t1x$Panel))
  expect_true(any(grepl("Panel A", labs2)) && any(grepl("Panel B", labs2)),
              "重排后 Panel A/B 齐全")
  blob2 <- paste(unlist(t1x), collapse = " | ")
  expect_true(!grepl("No AKI", blob2, ignore.case = TRUE), "重排后无 No AKI")
  expect_true(!grepl("AKI N = ", blob2), "重排后无 'AKI N =' 列头")
  expect_true(grepl("Survivor N = 15,050", blob2) &&
                grepl("Non-survivor N = 3,344", blob2),
              "MIMIC 列头 n=15,050/3,344（=26055 队列内 28d 生存/死亡）")
  expect_true(grepl("Survivor N = 8,462", blob2) &&
                grepl("Non-survivor N = 2,096", blob2),
              "eICU 列头 n=8,462/2,096")
  # 描述统计 2 位小数（继承旧表口径，重排不得加位）
  dcols <- intersect(c("Overall", "Survivor", "Non-survivor", "Non_survivor"),
                     colnames(t1x))
  dcells <- as.character(unlist(t1x[, dcols, drop = FALSE]))
  dcells <- dcells[!is.na(dcells)]
  expect_true(!any(grepl("[0-9]\\.[0-9]{3}", dcells)),
              "重排后描述统计无 >=3 位小数（应<=2）")
  tx2 <- list.files(file.path(out_dir, "Tables"),
                    pattern = "Table 1\\..*survival.*\\.xlsx$", full.names = TRUE)
  expect_true(length(tx2) >= 1, "重排版 Table 1 xlsx 落盘")
  v2 <- pub_xlsx_verify(tx2[1])
  expect_true(isTRUE(v2$readable) && identical(as.integer(v2$corrupt_cells), 0L) &&
                v2$styles > 0, "重排版 xlsx 校验通过")
}

# ===========================================================================
# 3c) S3 继承审计（Task5 冻结资产真构建）
# ===========================================================================
ASSET_DIR <- file.path(root, ".superpowers/sdd/staging/task5/model_assets")
if (dir.exists(ASSET_DIR)) {
  s3 <- ml_reference_build_s3(ASSET_DIR, out_dir)
  expect_true(is.data.frame(s3$audit) && nrow(s3$audit) >= 24,
              "S3 审计行来自 sofa_le10 资产 24 特征")
  expect_true(all(s3$audit$trained_in == "MIMIC-IV"), "S3 trained_in=MIMIC-IV")
  expect_true(file.exists(s3$xlsx), "S3 xlsx 落盘")
}

# ===========================================================================
# 4) S1：AKI 队列定义 + 证据不足标注
# ===========================================================================
s1 <- ml_reference_build_s1(STUDY_INDEX_ROOT, out_dir)
expect_true(is.data.frame(s1$long), "S1 long data.frame")
s1_blob <- paste(unlist(s1$long), collapse = " || ")
expect_true(grepl("Acute_Renal_Failure", s1_blob), "S1 写明 MIMIC 旗标列")
expect_true(grepl("Yes", s1_blob) && grepl("No", s1_blob), "旗标 Yes/No 取值")
mimic_row <- s1$long[grepl("MIMIC", s1$long$database, ignore.case = TRUE), ]
eicu_row <- s1$long[grepl("eICU", s1$long$database, ignore.case = TRUE), ]
expect_true(nrow(mimic_row) >= 1 && nrow(eicu_row) >= 1, "两库各至少一行")
expect_true(any(grepl("证据不足", eicu_row$evidence_status)),
            "eICU 行含『证据不足』")
expect_true(any(grepl("上游", eicu_row$evidence_detail) &
                grepl("未提供|未随数据", eicu_row$evidence_detail)),
            "eICU 注明上游 ICD/KDIGO 提取代码未提供")
expect_true(any(grepl("用户确认", s1_blob)), "eICU 预筛为用户确认")
expect_true(file.exists(s1$xlsx), "S1 xlsx 落盘")
v1 <- pub_xlsx_verify(s1$xlsx)
expect_true(isTRUE(v1$readable) && identical(as.integer(v1$corrupt_cells), 0L),
            "S1 xlsx 校验通过")

# ===========================================================================
# 5) manifest：profile + 来源 + 状态列
# ===========================================================================
mf <- ml_reference_build_manifest(profile = prof, out_dir = out_dir,
                                  study_index_root = STUDY_INDEX_ROOT,
                                  asset_dir = file.path(root,
                                    ".superpowers/sdd/staging/task5/model_assets"))
expect_true(file.exists(mf), "MANIFEST.csv 落盘")
mdf <- read.csv(mf, stringsAsFactors = FALSE, check.names = FALSE)
for (cc in c("kind", "number", "role", "reference_source", "adaptation",
             "source", "denominator", "status")) {
  expect_true(cc %in% names(mdf), paste("manifest 列:", cc))
}
expect_true(nrow(mdf) == nrow(prof), "manifest 行数 = profile 行数")
expect_true(any(grepl("Task4|task4", mdf$source)), "Fig2-6/Table2/S4-S10 来源=Task4")
expect_true(any(grepl("Task5|task5", mdf$source)), "S11 来源=Task5")
expect_true(any(grepl("Task6|task6", mdf$source)), "Fig7/8/S2-S5 来源=Task6")
expect_true(any(grepl("真实 attrition|attrition", mdf$source[mdf$number == "1" &
                                                              mdf$kind == "figure_main"])),
            "Figure 1 来源=真实 attrition CSV")
# Task7 本次实产（Fig1/Table1/S1/S3）status 应为 ready
r7 <- mdf[(mdf$number %in% c("1") & mdf$kind == "figure_main") |
          (mdf$number %in% c("1") & mdf$kind == "table_main") |
          (mdf$kind == "table_supp" & mdf$number %in% c("1", "3")), ]
expect_true(all(r7$status == "ready"), "Task7 实产角色 status=ready")
# 缺 S2 入口：UV 表若无任何产物 → status=missing；有旧库产物 → legacy_available（不编造）
s2row <- mdf[mdf$kind == "table_supp" & mdf$number == "2", ]
expect_true(nrow(s2row) == 1 &&
              all(s2row$status %in% c("ready", "missing", "legacy_available")),
            paste("S2 状态合法:", s2row$status))
# Task4/5/6 来源只 smoke/ready，不谎报全量：Figure 7/8、S2-S5、S11 冒烟态
f78 <- mdf[mdf$kind == "figure_main" & mdf$number %in% c("7", "8"), ]
expect_true(all(f78$status %in% c("smoke_only", "ready", "pending")),
            "Fig7/8 状态诚实")
s11 <- mdf[mdf$kind == "table_supp" & mdf$number == "11", ]
expect_true(all(s11$status %in% c("smoke_only", "ready", "pending")), "S11 状态诚实")
# Fig S1（PH beta(t) 趋势图）Task4 实际未产 → 必须 pending，不得 ready
fs1 <- mdf[mdf$kind == "figure_supp" & mdf$number == "1", ]
expect_true(fs1$status == "pending", "Fig S1 趋势图诚实标 pending")

# ===========================================================================
# 6) Block 可 source + register_block + dry-run 模式
# ===========================================================================
block_file <- file.path(root, "Blocks/24_ml_dual/09block_ml_stratified_reference_profile.R")
expect_true(file.exists(block_file), "09block 文件存在")
env <- new.env(parent = globalenv())
sys.source(block_file, envir = env)
expect_true(is.function(get("block_ml_stratified_reference_profile", envir = env)),
            "block 函数存在")
expect_true(is.function(get("ml_reference_profile_block", envir = env)),
            "封装入口存在")
dry_dir <- tempfile("srp_dry_"); dir.create(dry_dir, recursive = TRUE)
res <- get("ml_reference_profile_block", envir = env)(dry_run = TRUE, out_dir = dry_dir)
expect_true(is.list(res) && is.data.frame(res$manifest), "dry-run 返回 manifest")
expect_true(nrow(res$manifest) == 34, "dry-run 列全部 34 角色")
expect_true(identical(names(res$manifest)[1:7], names(prof)),
            "dry-run manifest 前 7 列 = profile 列")
# dry-run 不得写图/表（只 manifest）
expect_true(isFALSE(res$built_figures) && isFALSE(res$built_tables),
            "dry-run 不产图表")
expect_true(!dir.exists(file.path(dry_dir, "Figures")) &&
              !dir.exists(file.path(dry_dir, "Tables")),
            "dry-run 目录无 Figures/Tables 产物")
# block fn 形态：ctx 驱动（enable=FALSE 时原样返回 ctx）
ctx0 <- list(config = list(ml_stratified_reference_profile = list(enable = FALSE)),
             output_dir = dry_dir)
ctx1 <- get("block_ml_stratified_reference_profile", envir = env)(ctx0)
expect_true(identical(ctx1$config$ml_stratified_reference_profile$enable, FALSE),
            "block enable=FALSE 直通")

cat("TEST_OK\n")
