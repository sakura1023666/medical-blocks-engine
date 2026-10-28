# 课题薄封装：血脂异常队列不用血脂做中介。
# 主库筛查：舒张压（DBP）在无协变量时两库 path a/b/c 均显著；加入 Age 后共同显著消失。
# 定稿路径模型：无协变量（Unadj）。
# 引擎在 Blocks/20_mediation/13block_mediation_multi_db_cox.R。

.pv2_mediation_engine <- function() {
  if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final" else "/mnt/e/01block/01Block-new-Final"
}

#' 从各库基线挂上 DBP（mmHg），不改动已有列。
pv2_attach_dbp <- function(dbs, data_root = NULL) {
  if (is.null(data_root)) {
    if (exists("pv2_data_root", inherits = TRUE)) data_root <- get("pv2_data_root", inherits = TRUE)
    else data_root <- "G:/02block_result/49_Dyslipidemia/prognosis_41904528/data"
  }
  num <- function(x) suppressWarnings(as.numeric(x))
  out <- dbs
  if ("NHANES" %in% names(out)) {
    e <- new.env()
    load(file.path(data_root, "NHANES/D01_baseline_NHANES_0920.RData"), envir = e)
    b <- as.data.frame(e$baseline)
    b$ID <- as.character(b$ID)
    m <- b[, c("ID", "NBPD"), drop = FALSE]
    names(m)[2] <- "DBP"
    m$DBP <- num(m$DBP)
    d <- as.data.frame(out$NHANES)
    d$ID <- as.character(d$ID)
    d$DBP <- NULL
    out$NHANES <- merge(d, m, by = "ID", all.x = TRUE)
  }
  if ("SHHS" %in% names(out)) {
    sh <- data.table::fread(
      file.path(data_root, "SHHS(1)/EXCEL/shhs1-dataset-0.18.0.csv"),
      select = c("nsrrid", "diasbp"), showProgress = FALSE
    )
    m <- data.frame(ID = as.character(sh$nsrrid), DBP = num(sh$diasbp), stringsAsFactors = FALSE)
    d <- as.data.frame(out$SHHS)
    d$ID <- as.character(d$ID)
    d$DBP <- NULL
    out$SHHS <- merge(d, m, by = "ID", all.x = TRUE)
  }
  if ("CHARLS" %in% names(out)) {
    e <- new.env()
    load(file.path(data_root, "CHARLS/最终数据/D01_baseline_2011_DN.RData"), envir = e)
    b <- as.data.frame(e$baseline)
    b$ID <- as.character(b$ID)
    m <- b[, c("ID", "NBPD"), drop = FALSE]
    names(m)[2] <- "DBP"
    m$DBP <- num(m$DBP)
    d <- as.data.frame(out$CHARLS)
    d$ID <- as.character(d$ID)
    d$DBP <- NULL
    out$CHARLS <- merge(d, m, by = "ID", all.x = TRUE)
  }
  out
}

pv2_run_mediation <- function(dbs, tab_dir, fig_dir, bootstrap_iter = 100L, seed = 41904528L,
                              databases = NULL) {
  eng <- .pv2_mediation_engine()
  source(file.path(eng, "Blocks/20_mediation/13block_mediation_multi_db_cox.R"), local = FALSE)
  dbs <- pv2_attach_dbp(dbs)
  if (!is.null(databases)) dbs <- dbs[intersect(databases, names(dbs))]
  for (nm in names(dbs)) {
    dbs[[nm]]$time <- dbs[[nm]]$futime_years
    dbs[[nm]]$event <- dbs[[nm]]$fustatus
    if ("Gender" %in% names(dbs[[nm]])) dbs[[nm]]$Gender <- factor(dbs[[nm]]$Gender)
  }
  fig <- if (!is.null(fig_dir) && nzchar(fig_dir)) {
    file.path(fig_dir, "Figure 6. Mediation path diagram of sleep duration and all-cause mortality.pdf")
  } else {
    NULL
  }
  mediation_multi_db_cox_run(
    dbs = dbs,
    exposure = "Sleep_hours",
    mediators = "DBP",
    mediator_labels = c(DBP = "Diastolic blood pressure"),
    diagram_mediator = "DBP",
    ## 定稿：无协变量；S7 仍给 Age / Age+Gender 相关作对照
    path_covariates = character(0),
    cor_adj1 = "Age",
    cor_adj2 = c("Age", "Gender"),
    bootstrap_iter = bootstrap_iter,
    seed = seed,
    exposure_label = "Sleep duration",
    outcome_label = "All-cause mortality",
    fig_path = fig,
    tab_dir = tab_dir
  )
}
