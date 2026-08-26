#!/usr/bin/env Rscript
# 文献风格长图：Fig S4（年×结局双柱）、Fig S5（国×结局双柱）、Fig 4（CLPN 网络）
# + Figure S1/S2：CLPN 边权 bootstrap CI / case-dropping（对齐文献 Supp Figs. 25–26）
# 全部基于当前 study 真实 longitudinal / CLPN 结果，不照搬文献数字。
# Usage:
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase pub_figs --study-root ...
#   Rscript Blocks/54_cross_lagged_full/phases/phase_pub_figs_s4s5_f4.R --study-root ... [--no-sync]
#   可选环境变量：CROSS_LAGGED_BOOT_EDGE / CROSS_LAGGED_BOOT_CASE（默认均为 1000，对齐文献 nBoots）
#   CLI：--boot-edge / --boot-case（仅调试可下调；出版禁止 <1000）

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
root <- {
  if (basename(script_path) == "phases" &&
      grepl("54_cross_lagged", basename(dirname(script_path)), fixed = TRUE))
    normalizePath(file.path(script_path, "..", "..", ".."), winslash = "/")
  else if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run")
    normalizePath(file.path(script_path, "..", ".."), winslash = "/")
  else if (nzchar(Sys.getenv("MEDICAL_BLOCKS_ROOT", "")))
    normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT"), winslash = "/")
  else
    normalizePath(getwd(), winslash = "/")
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
study_root <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = file.path(root, "Output/16_Hip_fracture_cross-laged_40595747_allages")
)
no_sync <- FALSE
skip_boot <- FALSE
boot_edge_n <- NA_integer_
boot_case_n <- NA_integer_
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--study-root" && i < length(args)) {
    j <- i + 1L; parts <- character(0)
    while (j <= length(args) && !startsWith(args[[j]], "--")) {
      parts <- c(parts, args[[j]]); j <- j + 1L
    }
    study_root <- paste(parts, collapse = " "); i <- j
  } else if (args[[i]] %in% c("--no-sync")) {
    no_sync <- TRUE; i <- i + 1L
  } else if (args[[i]] %in% c("--skip-boot", "--no-boot")) {
    skip_boot <- TRUE; i <- i + 1L
  } else if (args[[i]] == "--boot-edge" && i < length(args)) {
    boot_edge_n <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--boot-case" && i < length(args)) {
    boot_case_n <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else i <- i + 1L
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(grid)
})
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/cross_lagged_covariate_lock.R"))
source(file.path(root, "R/cross_lagged_study_meta.R"))
source(file.path(root, "R/cross_lagged_fi_item_labels.R"))
source(file.path(root, "R/clpn_node_label_db.R"))
source(file.path(root, "R/clpn_network_plot.R"))
register_block <- function(...) invisible(NULL)
if (file.exists(file.path(root, "Blocks/54_cross_lagged_full/17block_cross_lagged_network.R"))) {
  source(file.path(root, "Blocks/54_cross_lagged_full/17block_cross_lagged_network.R"), local = FALSE)
}
if (file.exists(file.path(root, "Blocks/54_cross_lagged_full/22block_cross_lagged_network_bootstrap.R"))) {
  source(file.path(root, "Blocks/54_cross_lagged_full/22block_cross_lagged_network_bootstrap.R"), local = FALSE)
}

options(warn = 1, cli.hyperlink = FALSE)

.panel_f <- file.path(study_root, "config_long_panel.R")
.meta <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
.is_circadian <- isTRUE(.meta$kind == "circadian") || (
  file.exists(.panel_f) &&
    any(grepl("circadian_index_var|ePWV", readLines(.panel_f, warn = FALSE)))
)
if (file.exists(.panel_f)) {
  data_root <- file.path(study_root, "data")
  source(.panel_f, local = FALSE)
}
.ev_lab <- if (.is_circadian) "Circadian disorder" else "Hip fracture"
.ref_lab <- if (.is_circadian) "No disorder" else "No fracture"
.fig4_title <- if (.is_circadian) "CLPN network of circadian conditions.pdf" else
  "CLPN network of frailty index items.pdf"
.index_var <- if (!is.null(.meta$index_var)) as.character(.meta$index_var)[1L] else
  if (.is_circadian) "ePWV" else "FI"
.index_ylab <- if (.is_circadian) "ePWV" else "Frailty Index"
.index_file <- if (.is_circadian) "ePWV" else "FI"

# ── helpers ──────────────────────────────────────────────────────────────────
.sig_stars <- function(p) {
  ifelse(is.na(p), "",
         ifelse(p < 0.001, "***",
                ifelse(p < 0.01, "**",
                       ifelse(p < 0.05, "*", "ns"))))
}

.std_disease <- function(x) {
  x <- as.character(x)
  ifelse(is.na(x), NA_character_,
         ifelse(x %in% c("1", "Hip_Fracture", "Patellar_Fracture", "Fracture", "Yes", "Circadian_Disorder"),
                .ev_lab,
                ifelse(x %in% c("0", "No_Fracture", "No fracture", "Normal", "No", "No_Disorder"),
                       .ref_lab, x)))
}

.std_country <- function(x) {
  x <- as.character(x)
  dplyr::case_when(
    is.na(x) ~ NA_character_,
    grepl("China|CHARLS", x, ignore.case = TRUE) ~ "China",
    grepl("America|USA|United States|HRS", x, ignore.case = TRUE) ~
      "United States of America",
    grepl("UK|England|Britain|ELSA", x, ignore.case = TRUE) ~ "United Kingdom",
    TRUE ~ x
  )
}

.load_long <- function(db) {
  p <- file.path(study_root, paste0("phase3_long_", db), paste0("D05_long_", db, ".RData"))
  if (!file.exists(p)) stop("缺 D05: ", p)
  e <- new.env(parent = emptyenv())
  load(p, envir = e)
  d <- e$long_all
  if (is.null(d)) stop("D05 无 long_all: ", db)
  d <- as.data.frame(d)
  d$Year <- as.integer(if ("year" %in% names(d)) d$year else d$Year)
  iv <- .index_var
  if (!iv %in% names(d)) {
    stop("D05 无指标列 ", iv, ": ", db, call. = FALSE)
  }
  d$idx <- as.numeric(d[[iv]])
  if ("Disease01" %in% names(d) && any(is.finite(as.numeric(d$Disease01)))) {
    d01 <- as.numeric(d$Disease01)
    d$Disease <- ifelse(!is.finite(d01), NA_character_,
                        ifelse(d01 == 1, .ev_lab, .ref_lab))
    miss <- is.na(d$Disease)
    if (any(miss) && "Disease_Group" %in% names(d)) {
      d$Disease[miss] <- .std_disease(d$Disease_Group[miss])
    }
  } else {
    d$Disease <- .std_disease(if ("Disease_Group" %in% names(d)) d$Disease_Group else d$Disease01)
  }
  if (!"ID" %in% names(d)) d$ID <- as.character(seq_len(nrow(d)))
  d$ID <- as.character(d$ID)
  d$Country <- if ("Country" %in% names(d)) .std_country(d$Country) else
    switch(db, CHARLS = "China", ELSA = "United Kingdom", HRS = "United States of America",
           NHANES = "United States of America", db)
  d$Cohort <- db
  d$xs_only <- FALSE
  d <- d[is.finite(d$idx) & !is.na(d$Disease) & is.finite(d$Year), , drop = FALSE]
  d
}

.load_xs_index <- function(db) {
  p1 <- if (exists("cross_lagged_phase1_dir", mode = "function")) {
    cross_lagged_phase1_dir(study_root, db)
  } else {
    file.path(study_root, paste0("phase1_", db))
  }
  cdir <- file.path(p1, "checkpoints")
  cands <- c(
    file.path(cdir, "step10_multicollinearity_final.rds"),
    file.path(cdir, "step06_baseline_binary.rds"),
    file.path(cdir, "step05_imputation.rds"),
    file.path(cdir, "imputation.rds")
  )
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) stop("无 NHANES/横断面检查点: ", db, call. = FALSE)
  ck <- readRDS(hit)
  if (!is.null(ck$ctx)) ck <- ck$ctx
  d <- ck$data$imputed %||% ck$data$cleaned
  if (is.null(d) || !is.data.frame(d)) stop("横断面 imputed 为空: ", db, call. = FALSE)
  d <- as.data.frame(d)
  iv <- .index_var
  if (!iv %in% names(d)) stop("横断面无指标列 ", iv, ": ", db, call. = FALSE)
  d$idx <- as.numeric(d[[iv]])
  d$Disease <- .std_disease(d$Disease_Group)
  if (!"ID" %in% names(d)) d$ID <- as.character(seq_len(nrow(d)))
  d$ID <- as.character(d$ID)
  d$Country <- switch(db, NHANES = "United States of America",
                      CHARLS = "China", ELSA = "United Kingdom", db)
  d$Cohort <- db
  d$xs_only <- TRUE
  # 无随访：S4 一个横断面时点（调查周期合并为 NHANES）
  d$Year_lab <- db
  d$Year <- db
  d <- d[is.finite(d$idx) & !is.na(d$Disease), , drop = FALSE]
  d
}

# 文献风双柱：均值 ± SE，显著性角标
.plot_dodged_mean_bars <- function(df, xvar, title, fill_manual, xlab = NULL,
                                   ylim = NULL, ylab = NULL, outfile,
                                   width = 8, height = 5.2) {
  d <- df
  x_raw <- d[[xvar]]
  if (is.numeric(x_raw) || is.integer(x_raw)) {
    d$x <- factor(x_raw, levels = sort(unique(x_raw)))
  } else {
    d$x <- factor(as.character(x_raw), levels = unique(as.character(x_raw)))
  }
  d$Disease <- factor(d$Disease, levels = c(.ref_lab, .ev_lab))
  ylab <- ylab %||% .index_ylab
  sumd <- d %>%
    group_by(x, Disease) %>%
    summarise(
      mean = mean(idx, na.rm = TRUE),
      se = sd(idx, na.rm = TRUE) / sqrt(n()),
      n = n(),
      .groups = "drop"
    )

  ptab_rows <- list()
  for (lv in levels(d$x)) {
    sub <- d[as.character(d$x) == lv, , drop = FALSE]
    p <- tryCatch({
      if (length(unique(stats::na.omit(sub$Disease))) < 2L) NA_real_
      else stats::t.test(idx ~ Disease, data = sub)$p.value
    }, error = function(e) NA_real_)
    sc <- sumd[as.character(sumd$x) == lv, , drop = FALSE]
    y0 <- if (nrow(sc)) max(sc$mean + sc$se, na.rm = TRUE) else NA_real_
    if (!is.finite(y0)) next
    ptab_rows[[length(ptab_rows) + 1L]] <- data.frame(
      x = lv, p = p, stars = .sig_stars(p),
      y0 = y0, y_bar = y0 * 1.08, y_txt = y0 * 1.16,
      stringsAsFactors = FALSE
    )
  }
  ptab <- if (length(ptab_rows)) do.call(rbind, ptab_rows) else
    data.frame(x = character(0), p = numeric(0), stars = character(0),
               y0 = numeric(0), y_bar = numeric(0), y_txt = numeric(0))
  if (nrow(ptab)) {
    ptab$x <- factor(ptab$x, levels = levels(d$x))
    y_hi <- max(c(ptab$y_txt * 1.06), na.rm = TRUE)
  } else {
    y_hi <- max(sumd$mean + sumd$se, na.rm = TRUE) * 1.15
  }
  if (is.null(ylim) || !length(ylim)) {
    ylim <- c(0, max(y_hi, na.rm = TRUE))
    if (!isTRUE(.is_circadian)) ylim <- c(0, max(ylim[2], 0.55))
  } else if (nrow(ptab)) {
    ylim <- c(ylim[1], max(ylim[2], y_hi, na.rm = TRUE))
  }

  pd <- 0.4
  p <- ggplot(sumd, aes(x = x, y = mean, fill = Disease)) +
    geom_col(position = position_dodge(width = pd), width = 0.7, colour = NA) +
    geom_errorbar(
      aes(ymin = pmax(0, mean - se), ymax = mean + se),
      position = position_dodge(width = pd), width = 0.15, linewidth = 0.45
    )
  if (nrow(ptab) && any(nzchar(ptab$stars) & ptab$stars != "ns")) {
    keep <- !is.na(ptab$p) & is.finite(ptab$y_bar)
    if (any(keep)) {
      p <- p +
        geom_segment(
          data = ptab[keep, ],
          aes(x = as.numeric(x) - 0.18, xend = as.numeric(x) + 0.18,
              y = y_bar, yend = y_bar),
          inherit.aes = FALSE, linewidth = 0.5
        ) +
        geom_text(
          data = ptab[keep, ],
          aes(x = as.numeric(x), y = y_txt, label = stars),
          inherit.aes = FALSE, size = 4.2, fontface = "bold", vjust = 0
        )
    }
  }
  p <- p +
    scale_fill_manual(
      values = fill_manual,
      drop = FALSE,
      name = NULL,
      breaks = c(.ref_lab, .ev_lab),
      labels = c(.ref_lab, .ev_lab)
    ) +
    scale_y_continuous(limits = ylim, expand = expansion(mult = c(0, 0.02))) +
    labs(x = xlab, y = ylab, title = title) +
    theme_classic(base_size = 13) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
      axis.title = element_text(face = "bold"),
      axis.text = element_text(colour = "black"),
      legend.position = "bottom",
      legend.direction = "horizontal",
      legend.text = element_text(size = 11),
      legend.key.size = grid::unit(0.45, "cm"),
      panel.grid = element_blank()
    ) +
    guides(fill = guide_legend(nrow = 1, byrow = TRUE))

  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  dev <- if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else "pdf"
  ggsave(outfile, p, width = width, height = height, device = dev)
  invisible(list(plot = p, summary = sumd, p = ptab, path = outfile))
}

# 随访期间 ever 发生髋部骨折（incidence 设计下基线年无并发事件 → 全波共用标签）
.person_ever_disease <- function(d) {
  d <- as.data.frame(d)
  if ("Disease01" %in% names(d)) {
    ev <- tapply(as.numeric(d$Disease01), d$ID, function(z) {
      z <- z[is.finite(z)]
      if (!length(z)) 0L else as.integer(any(z == 1))
    })
  } else {
    ev <- tapply(d$Disease, d$ID, function(z) {
      as.integer(any(z %in% c(.ev_lab, "Hip fracture", "Hip_Fracture",
                              "Patellar fracture", "Patellar_Fracture",
                              "Circadian disorder", "Circadian_Disorder"), na.rm = TRUE))
    })
  }
  ids <- as.character(d$ID)
  lab <- ifelse(as.integer(ev[ids]) == 1L, .ev_lab, .ref_lab)
  lab[is.na(lab)] <- .ref_lab
  lab
}
# ── load cohorts ─────────────────────────────────────────────────────────────
cohorts <- c("CHARLS", "ELSA", "HRS")
cohorts <- cohorts[file.exists(file.path(study_root, paste0("phase3_long_", cohorts),
                                         paste0("D05_long_", cohorts, ".RData")))]
if (!length(cohorts) && !isTRUE(.is_circadian))
  stop("phase_pub_figs: 无 phase3_long_*/D05_long_*.RData")
all_long <- if (length(cohorts)) lapply(setNames(cohorts, cohorts), .load_long) else list()
# 昼夜：NHANES 无纵向，仍用横断面 ePWV 画 S4/S5
xs_s4 <- character(0)
if (isTRUE(.is_circadian)) {
  p1n <- file.path(study_root, "phase1_NHANES", "checkpoints")
  if (dir.exists(p1n)) {
    xs_s4 <- "NHANES"
    all_long[["NHANES"]] <- .load_xs_index("NHANES")
  }
}
if (!length(all_long)) stop("phase_pub_figs: 无可用队列数据")
cli::cli_alert_info("Loaded: {paste(sprintf('%s N=%d', names(all_long), vapply(all_long, nrow, 1L)), collapse='; ')}")

fig_out <- file.path(study_root, "summary_result", "figure")
tab_out <- file.path(study_root, "summary_result", "table")
dir.create(fig_out, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_out, recursive = TRUE, showWarnings = FALSE)

.year_pal <- list(
  HRS = setNames(c("#E57C23", "#F6C896"), c(.ev_lab, .ref_lab)),
  NHANES = setNames(c("#E57C23", "#F6C896"), c(.ev_lab, .ref_lab)),
  CHARLS = setNames(c("#C44E52", "#F1A7A9"), c(.ev_lab, .ref_lab)),
  ELSA = setNames(c("#3B6EA5", "#A9C5E0"), c(.ev_lab, .ref_lab))
)

.s4_name <- function(db) {
  sprintf("Figure S4-%s. Mean %s by Year and Disease.pdf", db, .index_file)
}
.s5_name <- function() {
  sprintf("Figure S5. Mean %s by Country and Disease.pdf", .index_file)
}

# =====================================================================
# Figure S4: 指标均值 by Year × Disease（各库一篇）
# 纵向库：incidence 基线无病，个体按随访 ever 入射分组。
# NHANES：无随访，用当期 Disease_Group；调查周期作横轴（无周期则一个时点）。
# =====================================================================
cli::cli_h1("Figure S4 — Mean {(.index_ylab)} by Year and Disease")
for (db in names(all_long)) {
  d <- all_long[[db]]
  xs <- isTRUE(d$xs_only[1])
  if (!isTRUE(xs)) d$Disease <- .person_ever_disease(d)
  xcol <- if ("Year_lab" %in% names(d) && isTRUE(xs)) "Year_lab" else "Year"
  fill <- .year_pal[[db]]
  if (is.null(fill)) fill <- setNames(c("#555555", "#BBBBBB"), c(.ev_lab, .ref_lab))
  out <- file.path(fig_out, .s4_name(db))
  res <- .plot_dodged_mean_bars(
    d, xvar = xcol, title = db, fill_manual = fill,
    ylab = .index_ylab,
    outfile = out, width = 7.2, height = 5.6
  )
  ph <- file.path(
    study_root,
    if (isTRUE(xs)) paste0("phase1_", db) else paste0("phase3_long_", db),
    "Figures"
  )
  dir.create(ph, recursive = TRUE, showWarnings = FALSE)
  file.copy(out, file.path(ph, paste0("FigS4_Mean_", .index_file, "_by_Year_Disease.pdf")),
            overwrite = TRUE)
  utils::write.csv(
    merge(res$summary, res$p[, c("x", "p", "stars")], by.x = "x", by.y = "x", all.x = TRUE),
    file.path(tab_out, paste0("FigureS4-", db, "_mean_", .index_file, "_by_year.csv")),
    row.names = FALSE
  )
  cli::cli_alert_success(
    "S4 {db}: ever/current event n_ids={sum(tapply(d$Disease==.ev_lab, d$ID, any))} → {out}"
  )
}

# =====================================================================
# Figure S5: 各国基线指标 × 结局（纵向=ever 入射；NHANES=当期诊断）
# =====================================================================
cli::cli_h1("Figure S5 — Mean {(.index_ylab)} by Country and Disease")
.person_baseline_ever <- function(d) {
  d <- as.data.frame(d)
  xs <- isTRUE(d$xs_only[1])
  if (!isTRUE(xs)) d$Disease <- .person_ever_disease(d)
  keep <- c("ID", "idx", "Country", "Cohort", "Disease")
  keep <- intersect(keep, names(d))
  if (isTRUE(xs)) {
    d[!duplicated(d$ID), keep, drop = FALSE]
  } else {
    y0 <- min(as.numeric(d$Year), na.rm = TRUE)
    d[as.numeric(d$Year) == y0 & !duplicated(d$ID), keep, drop = FALSE]
  }
}
pool <- do.call(rbind, lapply(all_long, function(d) {
  if (!"ID" %in% names(d)) d$ID <- seq_len(nrow(d))
  .person_baseline_ever(d)
}))
rownames(pool) <- NULL
pool$Country <- factor(
  as.character(pool$Country),
  levels = c("United States of America", "China", "United Kingdom")
)
pool$Disease <- factor(pool$Disease, levels = c(.ref_lab, .ev_lab))
pool <- pool[is.finite(pool$idx) & !is.na(pool$Country) & !is.na(pool$Disease), , drop = FALSE]
pool$Country <- droplevels(pool$Country)
cli::cli_alert_info(
  "S5 N={nrow(pool)}; by country/disease: {paste(capture.output(print(table(pool$Country, pool$Disease))), collapse=' | ')}"
)

sumc <- as.data.frame(pool %>%
  group_by(Country, Disease) %>%
  summarise(
    mean = mean(idx, na.rm = TRUE),
    se = sd(idx, na.rm = TRUE) / sqrt(n()),
    n = n(),
    .groups = "drop"
  ))
sumc$fill_id <- paste(as.character(sumc$Country), as.character(sumc$Disease), sep = " | ")

country_cols <- setNames(
  c("#E57C23", "#F6C896", "#C0392B", "#F5B7B1", "#1F4E79", "#A9C5E0"),
  c(
    paste("United States of America |", .ev_lab),
    paste("United States of America |", .ref_lab),
    paste("China |", .ev_lab),
    paste("China |", .ref_lab),
    paste("United Kingdom |", .ev_lab),
    paste("United Kingdom |", .ref_lab)
  )
)

ptab_c <- data.frame(
  Country = character(0), p = numeric(0), stars = character(0),
  y0 = numeric(0), y_bar = numeric(0), y_txt = numeric(0),
  stringsAsFactors = FALSE
)
for (co in levels(pool$Country)) {
  sub <- pool[as.character(pool$Country) == co, , drop = FALSE]
  p <- tryCatch({
    if (length(unique(sub$Disease)) < 2L) NA_real_ else
      stats::t.test(idx ~ Disease, data = sub)$p.value
  }, error = function(e) NA_real_)
  sc <- sumc[as.character(sumc$Country) == co, , drop = FALSE]
  y0 <- if (nrow(sc)) max(sc$mean + sc$se, na.rm = TRUE) else 0.3
  ptab_c <- rbind(ptab_c, data.frame(
    Country = co, p = p, stars = .sig_stars(p),
    y0 = y0, y_bar = y0 * 1.08, y_txt = y0 * 1.16,
    stringsAsFactors = FALSE
  ))
}
ptab_c$Country <- factor(ptab_c$Country, levels = levels(pool$Country))
y5 <- max(c(ptab_c$y_txt * 1.08, sumc$mean + sumc$se), na.rm = TRUE)

pd <- 0.55
p5 <- ggplot(sumc, aes(x = Country, y = mean, fill = fill_id)) +
  geom_col(position = position_dodge(width = pd), width = 0.7, colour = NA) +
  geom_errorbar(
    aes(ymin = pmax(0, mean - se), ymax = mean + se, group = Disease),
    position = position_dodge(width = pd), width = 0.15, linewidth = 0.45
  ) +
  geom_segment(
    data = ptab_c,
    aes(x = as.numeric(Country) - 0.2, xend = as.numeric(Country) + 0.2,
        y = y_bar, yend = y_bar),
    inherit.aes = FALSE, linewidth = 0.5
  ) +
  geom_text(
    data = ptab_c,
    aes(x = as.numeric(Country), y = y_txt, label = stars),
    inherit.aes = FALSE, size = 4.2, fontface = "bold", vjust = 0
  ) +
  scale_fill_manual(
    values = country_cols,
    name = NULL,
    breaks = names(country_cols),
    labels = setNames(
      c(
        paste("USA —", .ev_lab), paste("USA —", .ref_lab),
        paste("China —", .ev_lab), paste("China —", .ref_lab),
        paste("UK —", .ev_lab), paste("UK —", .ref_lab)
      ),
      names(country_cols)
    )
  ) +
  scale_x_discrete(labels = function(x) gsub("United States of America", "United States\nof America", x)) +
  scale_y_continuous(limits = c(0, y5), expand = expansion(mult = c(0, 0.02))) +
  labs(x = NULL, y = .index_ylab,
       title = sprintf("Mean %s by country (baseline / cross-section)", .index_ylab)) +
  theme_classic(base_size = 13) +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold", size = 14),
    axis.title = element_text(face = "bold"),
    axis.text = element_text(colour = "black"),
    legend.position = "bottom",
    legend.direction = "horizontal",
    legend.text = element_text(size = 9.5),
    legend.key.size = grid::unit(0.4, "cm"),
    panel.grid = element_blank()
  ) +
  guides(fill = guide_legend(nrow = 2, byrow = TRUE))

out5 <- file.path(fig_out, .s5_name())
ggsave(out5, p5, width = 8.5, height = 6.0,
       device = if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else "pdf")
utils::write.csv(
  merge(as.data.frame(sumc), ptab_c[, c("Country", "p", "stars")], by = "Country", all.x = TRUE),
  file.path(tab_out, paste0("FigureS5_mean_", .index_file, "_by_country.csv")),
  row.names = FALSE
)
dir.create(file.path(study_root, "phase3_long_Pooled/Figures"), recursive = TRUE, showWarnings = FALSE)
file.copy(out5, file.path(study_root, "phase3_long_Pooled/Figures",
                          paste0("FigS5_Mean_", .index_file, "_by_Country_Disease.pdf")),
          overwrite = TRUE)
cli::cli_alert_success("S5: {out5}")

# =====================================================================
# Figure 4: CLPN network（qgraph，短码 + 图例真名；映射库 configs/clpn_node_label_db.csv）
# =====================================================================
cli::cli_h1("Figure 4 — CLPN network (real adjacency)")

.fi_group_of <- function(stem) {
  # comorbidity / ADL / IADL / mobility / sensory
  if (stem %in% c("hibpe", "diabe", "cancre", "lunge", "psyche", "memrye", "arthre"))
    return("Comorbidity")
  if (stem %in% c("dressa", "batha", "eata", "beda", "toilta")) return("ADL")
  if (stem %in% c("mealsa", "shopa", "medsa", "moneya")) return("IADL")
  if (stem %in% c("srh", "armsa", "chaira", "climsa", "dimea", "lifta", "stoopa",
                  "walk100a", "walk10", "walk100")) return("Mobility")
  if (stem %in% c("glass", "hear")) return("Sensory")
  if (stem %in% c("Disease01", "Sarcopenia")) return("Outcome")
  "Other"
}

.plot_clpn_pub <- function(adj, stems, outfile, title) {
  plot_opts <- if (isTRUE(.is_circadian) &&
                    exists(".circadian_clpn_plot", inherits = TRUE)) {
    .circadian_clpn_plot
  } else {
    list()
  }
  do.call(clpn_plot_publication, c(
    list(
      adj = adj, stems = stems, outfile = outfile, title = title,
      disease_display = .ev_lab, root = root
    ),
    plot_opts
  ))
}

# 强制重算 CLPN（含疾病 + 库可用血脂/条目）；写出 Table S8 + Fig4
for (db in cohorts) {
  out_dir <- file.path(study_root, paste0("phase3_long_", db))
  e <- new.env(parent = emptyenv())
  load(file.path(out_dir, paste0("D05_long_", db, ".RData")), envir = e)
  # 用全量 wide，让网络块按 include_outcome/lipids 自己选节点（避免旧 wide_clpn 无 Disease）
  w <- if (!is.null(e$wide)) e$wide else e$wide_clpn
  ctx <- list(
    data = list(longitudinal_wide = w, longitudinal_wide_clpn = NULL),
    config = list(
      project = list(database = db, output_dir = out_dir),
      cross_lagged_network = if (isTRUE(.is_circadian)) {
        list(
          node_stems = c(paste0("condition", 1:7), "ePWV"),
          fi_items_only = FALSE,
          include_outcome = FALSE,
          include_lipids = FALSE,
          keep_forced_nodes = TRUE,
          max_nodes = 8L
        )
      } else {
        list(
          fi_items_only = TRUE,
          include_outcome = TRUE,
          include_lipids = TRUE,
          max_nodes = 40L
        )
      }
    )
  )
  ctx <- block_cross_lagged_network(ctx)
  adj <- ctx$results$cross_lagged_network$adjacency
  stems <- ctx$results$cross_lagged_network$stems
  # 复制出版 S8 到 summary
  s8_src <- ctx$results$cross_lagged_network$table_s8
  if (file.exists(s8_src)) {
    file.copy(s8_src, file.path(tab_out, basename(s8_src)), overwrite = TRUE)
  }
  # stem inventory note
  inv <- data.frame(
    cohort = db,
    n_nodes = length(stems),
    n_fi_items = sum(!stems %in% c("Disease01", "Sarcopenia", "sarcop",
                                   "Triglycerides", "HDL_Cholesterol", "newtg", "newhdl")),
    has_disease = any(stems %in% c("Disease01")),
    has_lipids = any(stems %in% c("Triglycerides", "HDL_Cholesterol", "newtg", "newhdl")),
    stems = paste(stems, collapse = "; "),
    labels = paste(cross_lagged_fi_item_label(stems, FALSE), collapse = "; "),
    stringsAsFactors = FALSE
  )
  inv_path <- file.path(tab_out, paste0("CLPN_node_inventory_", db, ".csv"))
  utils::write.csv(inv, inv_path, row.names = FALSE)

  out4 <- file.path(fig_out, paste0("Figure 4-", db, ". ", .fig4_title))
  .plot_clpn_pub(adj, stems, out4, title = paste0("(", LETTERS[match(db, cohorts)], ") ", db))
  file.copy(out4, file.path(out_dir, "Figures", "Fig4_CLPN_network_pub.pdf"), overwrite = TRUE)
  file.copy(out4, file.path(out_dir, "Figures", "Fig_CLPN_network.pdf"), overwrite = TRUE)
  cli::cli_alert_success(
    "Fig4 {db}: nodes={nrow(adj)} disease={any(stems=='Disease01')} nonzero={sum(adj != 0)} → {out4}"
  )

  # Figure S1 / S2：边权 bootstrap + case-dropping（文献 Supp Figs. 25–26）
  if (!isTRUE(skip_boot) && exists("block_cross_lagged_network_bootstrap", mode = "function")) {
    cli::cli_h2("Figure S1/S2 — CLPN bootstrap stability ({db})")
    n_edge <- if (is.finite(boot_edge_n)) boot_edge_n else as.integer(Sys.getenv("CROSS_LAGGED_BOOT_EDGE", "1000"))
    n_case <- if (is.finite(boot_case_n)) boot_case_n else as.integer(Sys.getenv("CROSS_LAGGED_BOOT_CASE", "1000"))
    if (!is.finite(n_edge) || n_edge < 1L) n_edge <- 1000L
    if (!is.finite(n_case) || n_case < 1L) n_case <- 1000L
    ctx$config$cross_lagged_network_bootstrap <- list(
      n_boot_edge = n_edge,
      n_boot_case = n_case,
      nfolds = 10L,
      seed = 40595747L
    )
    tryCatch({
      ctx <- block_cross_lagged_network_bootstrap(ctx)
      s1 <- ctx$results$cross_lagged_network_bootstrap$figure_s1
      s2 <- ctx$results$cross_lagged_network_bootstrap$figure_s2
      if (!is.null(s1) && file.exists(s1)) {
        file.copy(s1, file.path(fig_out, basename(s1)), overwrite = TRUE)
        file.copy(s1, file.path(out_dir, "Figures", basename(s1)), overwrite = TRUE)
      }
      if (!is.null(s2) && file.exists(s2)) {
        file.copy(s2, file.path(fig_out, basename(s2)), overwrite = TRUE)
        file.copy(s2, file.path(out_dir, "Figures", basename(s2)), overwrite = TRUE)
      }
      # 同步 bootstrap 表
      for (bn in c(
        paste0("CLPN_edge_bootstrap_", db, ".csv"),
        paste0("CLPN_case_dropping_", db, ".csv"),
        paste0("CLPN_bootstrap_", db, ".rds")
      )) {
        src <- file.path(out_dir, "Tables", bn)
        if (file.exists(src)) file.copy(src, file.path(tab_out, bn), overwrite = TRUE)
      }
    }, error = function(e) {
      cli::cli_alert_warning("CLPN bootstrap [{db}] 失败: {e$message}")
    })
  } else if (isTRUE(skip_boot)) {
    cli::cli_alert_info("跳过 CLPN bootstrap（--skip-boot）")
  }
}

# FI 构造核对表（为何均值不同、节点数如何）
.fi_src <- c(
  CHARLS = "虚弱_charls_*.csv: frailty26_total/26 (=FI)",
  ELSA = "虚弱_elsa_wave*.csv: precomputed FI (~ mean of 26 mapped items, cor≈0.999)",
  HRS = "虚弱_hrs_*.csv: precomputed FI (not simple mean of mapped 26 binaries; cor≈0.94)"
)
.fi_check <- data.frame(
  cohort = cohorts,
  fi_source = unname(.fi_src[cohorts]),
  stringsAsFactors = FALSE
)
utils::write.csv(.fi_check, file.path(tab_out, "FI_and_CLPN_construction_note.csv"), row.names = FALSE)

# README
writeLines(c(
  paste0("time=", format(Sys.time(), "%F %T")),
  "Figure S1: CLPN edge-weight nonparametric bootstrap (sample vs boot mean + 95% CI).",
  "  Aligns to literature network stability Supp Fig. 25 style.",
  "Figure S2: CLPN case-dropping stability (average edge correlation vs sampled cases %).",
  "  Aligns to literature network stability Supp Fig. 26 style.",
  "Figure S4: Mean±SE FI by survey year × ever-incident hip fracture in analytic panel (t-test stars).",
  "  Sole disease-group FI descriptive figure; baseline FI boxplot intentionally omitted.",
  "  ELSA survey years: 2004/2008/2012 (wave2/4/6).",
  "Figure S5: Mean±SE baseline FI by country × ever fracture",
  "Figure 4 / Table S8: CLPN nodes from mapping DB (configs/clpn_node_label_db.csv);",
  "  circadian = C1–C7 + ePWV (constant components kept, coef=0); hip = FI items + D1 + lipids",
  "See summary_result/table/FI_and_CLPN_construction_note.csv and CLPN_node_inventory_*.csv"
), file.path(fig_out, "README_FigS4_S5_Fig4.txt"))

cli::cli_alert_success("全部完成 → {fig_out}")
if (!isTRUE(no_sync) && exists("cross_lagged_sync_to_project_disk", mode = "function")) {
  # source study phases if needed — simple rsync via shell
}
# always try rsync summary figures to G
gdest <- Sys.getenv("CROSS_LAGGED_SYNC_ROOT", unset = "")
if (nzchar(gdest) && dir.exists(gdest)) {
  gfig <- file.path(gdest, "summary_result/figure")
  gtab <- file.path(gdest, "summary_result/table")
  dir.create(gfig, recursive = TRUE, showWarnings = FALSE)
  dir.create(gtab, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(fig_out, pattern = "^(Figure S1|Figure S2|Figure S4|Figure S5|Figure 4)", full.names = TRUE)) {
    file.copy(f, gfig, overwrite = TRUE)
  }
  for (f in list.files(tab_out, pattern = "^(FigureS(4|5)|Table S8|CLPN_|FI_and)", full.names = TRUE)) {
    file.copy(f, gtab, overwrite = TRUE)
  }
  file.copy(file.path(fig_out, "README_FigS4_S5_Fig4.txt"), gfig, overwrite = TRUE)
  # also S8 into G phase3 tables if present
  for (db in cohorts) {
    s8e <- file.path(study_root, paste0("phase3_long_", db), "Tables",
                     paste0("Table S8-", db, ". CLPN adjacency.csv"))
    if (file.exists(s8e)) {
      dir.create(file.path(gdest, paste0("phase3_long_", db), "Tables"),
                 recursive = TRUE, showWarnings = FALSE)
      file.copy(s8e, file.path(gdest, paste0("phase3_long_", db), "Tables"), overwrite = TRUE)
    }
  }
  cli::cli_alert_success("已同步 summary figure/table → {gfig}")
}
source(file.path(root, "Blocks/54_cross_lagged_full/phases/auto_collect_summary.inc.R"), local = FALSE)
