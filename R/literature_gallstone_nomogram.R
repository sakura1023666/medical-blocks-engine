###############################################################################
# literature_gallstone_nomogram.R — 胆结石碎石成功列线图辅助函数
# 文献方法: Chen et al. JAD 2026 (DOI 10.1177/13872877261424471)
# 映射: 发病地基 + 列线图后缀；外验 → 内部 bootstrap
###############################################################################

gallstone_nomogram_cont_features <- function(cfg = NULL) {
  bl <- (cfg$gallstone_nomogram %||% list())
  x <- bl$continuous_features
  if (is.null(x) || !length(x)) {
    x <- c("Age", "diameter_cm", "volume_cm3", "ct_min", "ct_max",
           "pct_lt40", "pct_40_80", "pct_gt80", "energy_j", "shots")
  }
  as.character(x)
}

gallstone_nomogram_cat_features <- function(cfg = NULL) {
  bl <- (cfg$gallstone_nomogram %||% list())
  x <- bl$categorical_features
  if (is.null(x) || !length(x)) {
    x <- c("Sex", "shape", "color", "surface", "stone_type")
  }
  as.character(x)
}

# 预测段临床预指定（小样本：不做 LASSO 海选；默认避开 CT 百分位/近分离分类）
gallstone_nomogram_prespec_predictors <- function(cfg = NULL) {
  bl <- (cfg$gallstone_nomogram %||% list())
  x <- bl$prespecified_predictors
  if (is.null(x) || !length(x)) {
    x <- c("Age", "diameter_cm", "volume_cm3", "energy_j", "shots")
  }
  as.character(x)
}

# 发表图/表展示名（禁止下划线；数据列名仍用 diameter_cm 等）
gallstone_nomogram_display_labels <- function(cfg = NULL) {
  bl <- (cfg$gallstone_nomogram %||% list())
  ov <- bl$display_labels
  base <- c(
    Age = "Age, y",
    Sex = "Sex",
    diameter_cm = "Diameter, cm",
    volume_cm3 = "Volume, cm3",
    energy_j = "Energy, J",
    shots = "Shots, n",
    shape = "Shape",
    color = "Color",
    surface = "Surface",
    stone_type = "Stone type",
    ct_min = "CT min, HU",
    ct_max = "CT max, HU",
    pct_lt40 = "CT <40 HU, %",
    pct_40_80 = "CT 40-80 HU, %",
    pct_gt80 = "CT >80 HU, %"
  )
  if (is.null(ov) || !length(ov)) return(base)
  ov <- as.character(ov)
  names(ov) <- names(bl$display_labels)
  base[names(ov)] <- ov
  base
}

gallstone_nomogram_read_xlsx <- function(path) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    stop("需要 readxl 读 xlsx: ", path, call. = FALSE)
  }
  df <- as.data.frame(readxl::read_excel(path, sheet = 1L), stringsAsFactors = FALSE)
  names(df) <- trimws(names(df))
  # 统一大小写别名
  ren <- c(
    id = "id", ID = "id", Id = "id",
    Sex = "Sex", sex = "Sex",
    Age = "Age", age = "Age",
    Shape = "shape", shape = "shape",
    Color = "color", color = "color",
    Surface = "surface", surface = "surface",
    Type = "stone_type", stone_type = "stone_type", Stone_type = "stone_type",
    Diameter_cm = "diameter_cm", diameter_cm = "diameter_cm",
    Volume_cm3 = "volume_cm3", volume_cm3 = "volume_cm3",
    Min_CT = "ct_min", ct_min = "ct_min",
    Max_CT = "ct_max", ct_max = "ct_max",
    Pct_CT_lt40 = "pct_lt40", pct_lt40 = "pct_lt40",
    Pct_CT_40_80 = "pct_40_80", pct_40_80 = "pct_40_80",
    Pct_CT_gt80 = "pct_gt80", pct_gt80 = "pct_gt80",
    Energy_J = "energy_j", energy_j = "energy_j",
    Shots = "shots", shots = "shots",
    Success = "success", success = "success"
  )
  for (nm in names(df)) {
    if (nm %in% names(ren)) names(df)[names(df) == nm] <- ren[[nm]]
  }
  # 百分比若在 0–1，转为 0–100（可选）
  for (pc in c("pct_lt40", "pct_40_80", "pct_gt80")) {
    if (pc %in% names(df)) {
      v <- suppressWarnings(as.numeric(df[[pc]]))
      if (all(is.na(v) | (v >= 0 & v <= 1.5), na.rm = TRUE) &&
          any(v <= 1, na.rm = TRUE) && max(v, na.rm = TRUE) <= 1.5) {
        df[[pc]] <- v * 100
      } else {
        df[[pc]] <- v
      }
    }
  }
  num_cols <- c("Age", "diameter_cm", "volume_cm3", "ct_min", "ct_max",
                "pct_lt40", "pct_40_80", "pct_gt80", "energy_j", "shots", "success")
  for (nc in intersect(num_cols, names(df))) {
    df[[nc]] <- suppressWarnings(as.numeric(df[[nc]]))
  }
  for (cc in intersect(c("Sex", "shape", "color", "surface", "stone_type"), names(df))) {
    df[[cc]] <- factor(df[[cc]])
  }
  if ("success" %in% names(df) && !"Success" %in% names(df)) {
    df$Success <- factor(ifelse(as.integer(df$success) == 1L, "Yes", "No"),
                         levels = c("No", "Yes"))
  }
  df
}

gallstone_nomogram_model_sets <- function(cfg, data, expose = NULL, uv = NULL) {
  bl <- cfg$gallstone_nomogram %||% list()
  src <- as.character(bl$assoc_covariate_source %||% "uv_significant")[1L]
  force_m1 <- as.character(bl$force_model1 %||% "Age")[1L]
  drop_self <- function(vars, expose) {
    vars <- unique(as.character(vars))
    vars <- vars[nzchar(vars)]
    if (!is.null(data)) vars <- vars[vars %in% names(data)]
    if (!is.null(expose) && nzchar(expose)) vars <- setdiff(vars, expose)
    vars
  }

  if (identical(src, "uv_significant")) {
    m2_uv <- bl$model2 %||% (uv$sig_demo %||% character(0))
    m3_uv <- bl$model3 %||% (uv$sig_all %||% character(0))
    if ((!length(m2_uv) || !length(m3_uv)) && is.data.frame(uv$table)) {
      sig <- as.character(uv$table$variable[as.logical(uv$table$significant) %in% TRUE])
      demo <- uv$demo_pool %||% c("Age", "Sex")
      if (!length(m2_uv)) m2_uv <- intersect(sig, demo)
      if (!length(m3_uv)) m3_uv <- sig
    }
    # 死规则：Age 强制进 Model1；Model2/3 嵌套含 Age
    m1 <- force_m1
    m2 <- unique(c(force_m1, m2_uv))
    m3 <- unique(c(force_m1, m2_uv, m3_uv))
    return(list(
      Model1 = drop_self(m1, expose),
      Model2 = drop_self(m2, expose),
      Model3 = drop_self(m3, expose)
    ))
  }

  # 兼容旧口径：文献事先点名（仍强制 Age∈Model1）
  m2 <- bl$model2 %||% c("Age", "Sex")
  m3 <- bl$model3 %||% c("Age", "Sex", "shape", "color", "surface", "stone_type")
  list(
    Model1 = drop_self(force_m1, expose),
    Model2 = drop_self(unique(c(force_m1, m2)), expose),
    Model3 = drop_self(unique(c(force_m1, m3)), expose)
  )
}

#' 从 shared 产物或 ctx 取 UV 筛选结果（unit 侧兜底）
gallstone_nomogram_load_uv <- function(ctx) {
  uv <- ctx$results$gallstone_uv_covariate_screen
  if (!is.null(uv) && length(uv$sig_all)) return(uv)
  dirs <- tryCatch(gallstone_nomogram_out_dirs(ctx, "ALL"), error = function(e) NULL)
  if (is.null(dirs)) return(NULL)
  csv <- file.path(dirs$shared_tables, "Table_UV_covariate_screen.csv")
  if (!file.exists(csv)) {
    csv <- file.path(dirs$project, "Tables", "Table_UV_covariate_screen.csv")
  }
  if (!file.exists(csv)) return(NULL)
  tab <- utils::read.csv(csv, stringsAsFactors = FALSE)
  sig <- as.character(tab$variable[isTRUE(tab$significant) | tab$significant %in% TRUE |
                                     as.character(tab$significant) %in% c("TRUE", "True", "true")])
  demo <- intersect(sig, c("Age", "Sex"))
  list(table = tab, sig_all = sig, sig_demo = demo, demo_pool = c("Age", "Sex"),
       alpha = 0.05)
}

#' 塌缩几乎完全分离的 stone_type → Favorable / Unfavorable（按结局交叉表）
gallstone_collapse_stone_type <- function(df, outcome = "Success") {
  if (!"stone_type" %in% names(df)) return(df)
  y <- df[[outcome]]
  if (is.factor(y)) y01 <- as.integer(y == levels(y)[length(levels(y))] | y == "Yes")
  else y01 <- as.integer(as.numeric(y) == 1L)
  st <- as.character(df$stone_type)
  tab <- table(st, y01)
  # 任一类事件率 0% 或 100% 且 n≥3 → 进塌缩映射
  rate <- if (ncol(tab) >= 2) tab[, ncol(tab)] / rowSums(tab) else rep(NA_real_, nrow(tab))
  names(rate) <- rownames(tab)
  fav <- names(rate)[is.finite(rate) & rate >= 0.85]
  unfav <- names(rate)[is.finite(rate) & rate <= 0.15]
  mid <- setdiff(names(rate), c(fav, unfav))
  lab <- rep("Intermediate", length(st))
  lab[st %in% fav] <- "Favorable"
  lab[st %in% unfav] <- "Unfavorable"
  # 若中间类为空且两类都有，用二分类
  lv <- unique(lab)
  if (length(intersect(lv, c("Favorable", "Unfavorable"))) == 2L && !"Intermediate" %in% lv) {
    df$stone_type <- factor(lab, levels = c("Favorable", "Unfavorable"))
  } else {
    df$stone_type <- factor(lab, levels = c("Favorable", "Intermediate", "Unfavorable"))
  }
  df$stone_type_raw <- st
  df
}

#' 拟合 OR 行：优先 brglm2（Firth/偏误缩减），失败回退 glm
gallstone_nomogram_fit_or_row <- function(data, expose, outcome, covars = character(0)) {
  d <- data
  y <- d[[outcome]]
  if (is.factor(y)) {
    d$.y <- as.integer(y == levels(y)[length(levels(y))] | y == "Yes" | y == "1")
  } else {
    d$.y <- as.integer(as.numeric(y) == 1L)
  }
  if (!expose %in% names(d)) return(NULL)
  x <- suppressWarnings(as.numeric(d[[expose]]))
  xs <- as.numeric(scale(x))
  d$.x <- xs
  rhs <- c(".x", covars)
  rhs <- unique(rhs[rhs %in% c(".x", names(d))])
  fml <- stats::as.formula(paste(".y ~", paste(rhs, collapse = " + ")))
  fit <- NULL
  method <- "glm"
  if (requireNamespace("brglm2", quietly = TRUE)) {
    fit <- tryCatch(
      stats::glm(fml, data = d, family = stats::binomial(), method = "brglmFit"),
      error = function(e) NULL
    )
    if (!is.null(fit)) method <- "brglm2"
  }
  if (is.null(fit)) {
    fit <- tryCatch(stats::glm(fml, data = d, family = stats::binomial()), error = function(e) NULL)
  }
  if (is.null(fit)) return(NULL)
  sm <- summary(fit)$coefficients
  if (!".x" %in% rownames(sm)) return(NULL)
  est <- sm[".x", "Estimate"]
  se <- sm[".x", "Std. Error"]
  p <- sm[".x", grepl("Pr\\(>", colnames(sm))][1]
  if (is.na(p)) p <- sm[".x", ncol(sm)]
  or <- exp(est)
  lo <- exp(est - 1.96 * se)
  hi <- exp(est + 1.96 * se)
  data.frame(
    feature = expose,
    OR = or, CI_low = lo, CI_high = hi, P = as.numeric(p),
    OR_CI = sprintf("%.2f (%.2f, %.2f)", or, lo, hi),
    method = method,
    stringsAsFactors = FALSE
  )
}

gallstone_nomogram_out_dirs <- function(ctx, unit = NULL) {
  out_root <- ctx$config$project$output_dir %||% "Output"
  sb <- (ctx$config$study_batch %||% list())$output_base
  proj <- sb %||% {
    p <- normalizePath(out_root, winslash = "/", mustWork = FALSE)
    if (grepl("/by_unit(/|$)", p)) sub("/by_unit(/.*)?$", "", p) else p
  }
  unit <- unit %||% ctx$config$incidence$index_var %||% "ALL"
  list(
    project = proj,
    unit_root = file.path(proj, "by_unit", unit),
    tables = file.path(proj, "by_unit", unit, "Tables"),
    figures = file.path(proj, "by_unit", unit, "Figures"),
    shared_tables = file.path(proj, "_shared", "Tables"),
    shared_figures = file.path(proj, "_shared", "Figures"),
    summary = file.path(proj, "by_index", paste0("\u3010success\u3011", unit), "summary_results")
  )
}

gallstone_nomogram_ensure_dirs <- function(paths) {
  for (p in unlist(paths, use.names = FALSE)) {
    if (grepl("(Tables|Figures|summary_results)$", p)) {
      dir.create(p, recursive = TRUE, showWarnings = FALSE)
    }
  }
  invisible(paths)
}

#' Fig1 文献风 CONSORT：白底直角框、竖主轴、右侧 Exclude、底部分叉 Training|Validation
#' 视觉对齐用户提供的 NHANES 纳排图（无粉绿底、无圆角、图内无大标题）
gallstone_draw_fig1_lit <- function(pdf_path,
                                    n_total,
                                    n_final = n_total,
                                    n_exclude = max(0L, as.integer(n_total) - as.integer(n_final)),
                                    exclude_label = "missing modeling covariates",
                                    n_train,
                                    n_val,
                                    width = 7.2,
                                    height = 8.5) {
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(pdf_path, width = width, height = height, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()

  .box <- function(x0, y0, x1, y1, lab, cex = 11) {
    grid::grid.rect(
      x = grid::unit((x0 + x1) / 2, "npc"),
      y = grid::unit((y0 + y1) / 2, "npc"),
      width = grid::unit(abs(x1 - x0), "npc"),
      height = grid::unit(abs(y1 - y0), "npc"),
      gp = grid::gpar(fill = "white", col = "black", lwd = 1.25)
    )
    grid::grid.text(
      lab,
      x = grid::unit((x0 + x1) / 2, "npc"),
      y = grid::unit((y0 + y1) / 2, "npc"),
      gp = grid::gpar(fontsize = cex, fontfamily = "sans", col = "black", lineheight = 1.15)
    )
  }
  .vline <- function(x, y0, y1) {
    grid::grid.lines(
      x = grid::unit(c(x, x), "npc"),
      y = grid::unit(c(y0, y1), "npc"),
      arrow = grid::arrow(type = "closed", length = grid::unit(8, "pt"), angle = 22),
      gp = grid::gpar(col = "black", fill = "black", lwd = 1.2)
    )
  }
  .hline <- function(x0, x1, y) {
    grid::grid.lines(
      x = grid::unit(c(x0, x1), "npc"),
      y = grid::unit(c(y, y), "npc"),
      gp = grid::gpar(col = "black", lwd = 1.2)
    )
  }

  n_total <- as.integer(n_total)[1L]
  n_final <- as.integer(n_final)[1L]
  n_exclude <- as.integer(n_exclude)[1L]
  n_train <- as.integer(n_train)[1L]
  n_val <- as.integer(n_val)[1L]
  fmt <- function(n) format(n, big.mark = ",")

  # 主列（偏左，给右侧 Exclude 留位）— 对齐参考图：Total → Exclude → Final → 分叉
  cx <- 0.36
  mw <- 0.48
  x0 <- cx - mw / 2
  x1 <- cx + mw / 2
  bh <- 0.10

  y1_top <- 0.86
  y1_bot <- y1_top - bh
  y2_top <- 0.48
  y2_bot <- y2_top - bh

  .box(x0, y1_bot, x1, y1_top,
       sprintf("Total eligible gallstone lithotripsy records\nN = %s", fmt(n_total)), 11)
  .vline(cx, y1_bot - 0.002, y2_top + 0.002)

  # 右侧 Exclude（即使 n=0 也画，对齐文献）
  ex0 <- 0.62
  ex1 <- 0.97
  ymid <- (y1_bot + y2_top) / 2
  eh <- 0.08
  grid::grid.lines(
    x = grid::unit(c(cx, ex0), "npc"),
    y = grid::unit(c(ymid, ymid), "npc"),
    arrow = grid::arrow(type = "closed", length = grid::unit(7, "pt"), angle = 22),
    gp = grid::gpar(col = "black", fill = "black", lwd = 1.1)
  )
  .box(ex0, ymid - eh / 2, ex1, ymid + eh / 2,
       sprintf("Excluded %s\nn = %s", exclude_label, fmt(n_exclude)), 9)

  .box(x0, y2_bot, x1, y2_top,
       sprintf("Final participants included\nN = %s", fmt(n_final)), 11)

  # 底部分叉 Training | Validation
  t_y <- y2_bot - 0.07
  ow <- 0.30
  gap <- 0.06
  left_x0 <- cx - gap / 2 - ow
  right_x0 <- cx + gap / 2
  y_out <- 0.12
  oh <- 0.10
  grid::grid.lines(
    x = grid::unit(c(cx, cx), "npc"),
    y = grid::unit(c(y2_bot, t_y), "npc"),
    gp = grid::gpar(col = "black", lwd = 1.2)
  )
  .hline(left_x0 + ow / 2, right_x0 + ow / 2, t_y)
  .vline(left_x0 + ow / 2, t_y, y_out + oh + 0.002)
  .vline(right_x0 + ow / 2, t_y, y_out + oh + 0.002)
  .box(left_x0, y_out, left_x0 + ow, y_out + oh,
       sprintf("Training set\n(n = %s)", fmt(n_train)), 11)
  .box(right_x0, y_out, right_x0 + ow, y_out + oh,
       sprintf("Validation set\n(n = %s)", fmt(n_val)), 11)

  invisible(TRUE)
}

