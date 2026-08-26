# Review package Task 2

## Note: pre-existing in workspace; verify against brief

## incidence_dual_batch_runner.R (approx 1820-1945)
```r
3639:      incidence_batch_dedupe_prognosis_figures_dir(
3640:        file.path(index_root, dual_db_slot_path_name(config, db), "Figures"),
3641:        config
3642:      )
3643:    }
3644:    incidence_batch_dedupe_prognosis_figures_dir(file.path(index_root, "Figures"), config)
3645:  }
3646:  # 双库成对发表图 → A/B 拼图（汇总目录只留拼图；各库底稿不动）
3647:  if (!exists("dual_db_combine_paired_figures", mode = "function")) {
3648:    combine_src <- file.path(root, "R", "dual_db_combine_figures.R")
3649:    if (!file.exists(combine_src)) {
3650:      eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
3651:      if (nzchar(eng)) combine_src <- file.path(eng, "R", "dual_db_combine_figures.R")
3652:    }
3653:    if (file.exists(combine_src)) source(combine_src, local = FALSE)
3654:  }
3655:  if (exists("dual_db_combine_paired_figures", mode = "function")) {
3656:    tryCatch(
3657:      dual_db_combine_paired_figures(index_root, config),
3658:      error = function(e) {
3659:        cli::cli_alert_warning("双库拼图跳过: {e$message}")
3660:      }
3661:    )
3662:  }
3663:  # 指标根 + 各库级 Tables 均为发表汇总：禁止残留 .tex（LaTeX 只留 step*/Tables）
3664:  agg_table_dirs <- unique(c(
3665:    file.path(index_root, "Tables"),
3666:    vapply(db_seq, function(db) {
3667:      file.path(index_root, dual_db_slot_path_name(config, db), "Tables")
3668:    }, character(1L))
3669:  ))
3670:  for (td in agg_table_dirs) {
3671:    if (exists("pipeline_purge_aggregate_tex", mode = "function")) {
3672:      pipeline_purge_aggregate_tex(td, label = paste0("汇总 ", basename(dirname(td)), "/Tables"))
3673:    } else if (dir.exists(td)) {
3674:      stale_tex <- list.files(td, pattern = "\\.tex$", full.names = TRUE, ignore.case = TRUE)
3675:      if (length(stale_tex)) unlink(stale_tex)
3676:    }
3677:  }
3678:  agg_tables_tex <- file.path(index_root, "Tables")
3679:  if (dir.exists(agg_tables_tex)) {
3680:    stale_csv <- list.files(
3681:      agg_tables_tex,
3682:      pattern = "\\.csv$",
3683:      full.names = TRUE,
3684:      ignore.case = TRUE
3685:    )
3686:    stale_excl <- stale_csv[grepl(
3687:      "^(Analysis_exclusion_|Flowchart_attrition)",
3688:      basename(stale_csv),
3689:      ignore.case = TRUE
3690:    )]
3691:    if (length(stale_excl)) {
3692:      unlink(stale_excl)
3693:      cli::cli_alert_info("已清理汇总 Tables 中 {length(stale_excl)} 个非发表 csv")
3694:    }
3695:  }
3696:  incidence_batch_curate_index_pub_outputs(index_root, config, db_seq)
3697:  # 单库不走双库 S 链重排，但仍把 RCS cutoff logistic 定为 S-XX
3698:  rcs_dirs <- unique(c(
3699:    file.path(index_root, "Tables"),
3700:    vapply(db_seq, function(db) {
3701:      file.path(index_root, dual_db_slot_path_name(config, db), "Tables")
3702:    }, character(1L))
3703:  ))
3704:  for (td in rcs_dirs) {
3705:    incidence_batch_purge_aggregate_roc_tables(td)
3706:  }
3707:  agg_tables <- file.path(index_root, "Tables")
3708:  if (length(db_seq) >= 2L && exists("survival_batch_clear_stale_cox_tables", mode = "function")) {
3709:    for (db in db_seq) {
3710:      survival_batch_clear_stale_cox_tables(
3711:        file.path(index_root, dual_db_slot_path_name(config, db))
3712:      )
3713:    }
3714:    survival_batch_clear_stale_cox_tables(index_root)
3715:  }
3716:  incidence_batch_purge_aggregate_scratch_tables(agg_tables)
3717:  incidence_batch_purge_stale_main_logistic_and_subgroup_tables(agg_tables)
3718:  scheme <- incidence_batch_pub_figure_scheme(config)
3719:  if (identical(scheme, "ml_dual_standard")) {
3720:    if (!exists("incidence_batch_curate_ml_pub_tables", mode = "function")) {
3721:      source(file.path(root, "R", "ml_dual_pub_table_curate.R"), local = FALSE)
3722:    }
3723:    incidence_batch_curate_ml_pub_tables(agg_tables, config)
3724:    incidence_batch_collect_index_shiny_outputs(index_root, config, db_seq)
3725:  } else {
3726:    # 单库也按角色压 S 号，避免 step 编号（S8/S10/S11）并列残留
3727:    incidence_batch_realign_dual_supp_tables(agg_tables, config)
3728:    for (db in db_seq) {
3729:      db_tables <- file.path(
3730:        index_root, dual_db_slot_path_name(config, db), "Tables"
3731:      )
3732:      incidence_batch_realign_dual_supp_tables(db_tables, config)
3733:    }
3734:  }
3735:  for (td in rcs_dirs) {
3736:    incidence_batch_rename_rcs_tables_to_sxx(td, config)
3737:    incidence_batch_compact_supp_s_numbers(td, config)
3738:    incidence_batch_shorten_pub_table_names(td, config)
3739:  }
3740:
3741:  # 发表图四目录导出（pdf/png/tiff + image_information）
3742:  if (!exists("export_pub_figures", mode = "function")) {
3743:    exp_src <- file.path(root, "R", "pub_figure_export.R")
3744:    if (file.exists(exp_src)) source(exp_src, local = FALSE)
3745:  }
3746:  if (exists("export_pub_figures", mode = "function")) {
3747:    figs_dir <- file.path(index_root, "Figures")
3748:    meta <- list(
3749:      exposure = as.character(config$project$exposure_var %||% config$project$index_var %||% ix)[1L],
3750:      outcome = as.character(config$data$outcome_column %||% config$project$outcome %||% "")[1L],
3751:      databases = as.character(db_seq),
3752:      combined = length(db_seq) >= 2L,
3753:      grouping = as.character(
3754:        config$logistic_gate$grouping %||%
3755:          config$project$grouping %||%
3756:          ""
3757:      )[1L]
3758:    )
3759:    tryCatch(
3760:      export_pub_figures(figs_dir, meta = meta, config = config),
3761:      error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
3762:    )
3763:  }
3764:}
```

## configs/templates/config_incidence_dual_batch.template.R pub_figures
```r

  pub_figures = list(
    formats_dir = TRUE,
    dpi = 300L,
    tiff_compression = "lzw",
    write_image_information = TRUE
  ),

  dual_db = list(
```

## configs/templates/config_survival_dual_batch.template.R pub_figures
```r
  ),
  pub_figures = list(
    formats_dir = TRUE,
    dpi = 300L,
    tiff_compression = "lzw",
    write_image_information = TRUE
  ),
  dual_db = list(
    enable = TRUE, mirror_aggregate = TRUE,
```

## configs/templates/config_ml_dual_batch.template.R pub_figures
```r
  index = list(enable = FALSE),
  pub_figures = list(
    formats_dir = TRUE,
    dpi = 300L,
    tiff_compression = "lzw",
    write_image_information = TRUE
  ),
  dual_db = list(
    enable = TRUE,
```

## guards around L467
```r
stopifnot(file.exists(file.path(ix_root, "Figures", "Figure 2-MIMIC. RCS plot.pdf")))
stopifnot(file.exists(file.path(ix_root, "Figures", "Figure S1-MIMIC. Boxplot.pdf")))
unlink(ix_root, recursive = TRUE)

# ── 汇总 Figures：export 后顶层无散落图文件 ────────────────────────────────
if (!exists("export_pub_figures", mode = "function")) {
  source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
}
fd_exp <- tempfile("agg_figs_export_")
dir.create(fd_exp)
make_guard_pdf <- function(path) {
  grDevices::pdf(path, width = 4, height = 3, onefile = TRUE)
  plot.new()
  title("guard fig")
  grDevices::dev.off()
}
make_guard_pdf(file.path(fd_exp, "Figure 1. Flowchart.pdf"))
make_guard_pdf(file.path(fd_exp, "Figure 2. RCS plot.pdf"))
export_pub_figures(
  fd_exp,
  meta = list(
    exposure = "De_Ritis",
    outcome = "Disease_Group",
    databases = c("NHANES", "MIMIC"),
    combined = TRUE,
    grouping = "quartile"
  ),
  config = list(pub_figures = list(dpi = 72L))
)
top_after <- list.files(fd_exp, pattern = "\\.(pdf|png|tiff|tif)$", ignore.case = TRUE)
stopifnot(length(top_after) == 0L)
stopifnot(dir.exists(file.path(fd_exp, "pdf")))
stopifnot(dir.exists(file.path(fd_exp, "png")))
stopifnot(dir.exists(file.path(fd_exp, "tiff")))
stopifnot(dir.exists(file.path(fd_exp, "image_information")))
unlink(fd_exp, recursive = TRUE)

# finalize 顺序：curate 之后调用 export_pub_figures
stopifnot(grepl("incidence_batch_curate_index_pub_outputs", runner_txt))
stopifnot(grepl("export_pub_figures\\(figs_dir", runner_txt))
curate_pos <- regexpr("incidence_batch_curate_index_pub_outputs", runner_txt)[1L]
export_pos <- regexpr("export_pub_figures\\(figs_dir", runner_txt)[1L]
stopifnot(curate_pos > 0L, export_pos > 0L, export_pos > curate_pos)

# Charlson 归入 Clinical Scores，不得落到表末
```
