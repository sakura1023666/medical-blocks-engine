# 本题唯一路径与角色开关。所有 pv2_*.R / literature / redraw 先 source 本文件。
# 旧三库平权结果已归档，不再写入 prognosis_v2_41904528。

.pv2_win_or_mnt <- function(g_path) {
  m <- sub("^G:/", "/mnt/g/", g_path)
  # Prefer the mount that actually holds analysis artifacts.
  # On some Linux hosts G:/ is a shallow stub (e.g. only empty summary_results);
  # /mnt/g is the real drive with checkpoints / Tables.
  .has_artifacts <- function(root) {
    if (!dir.exists(root)) return(FALSE)
    any(file.exists(c(
      file.path(root, "summary_results", "checkpoints", "imputed_dbs.rds"),
      file.path(root, "summary_results", "Tables"),
      file.path(root, "logs")
    )))
  }
  if (.has_artifacts(m)) return(m)
  if (.has_artifacts(g_path)) return(g_path)
  if (dir.exists(m) || dir.exists(dirname(m))) return(m)
  if (dir.exists(g_path) || dir.exists(dirname(g_path))) return(g_path)
  g_path
}

pv2_data_root <- .pv2_win_or_mnt("G:/02block_result/49_Dyslipidemia/prognosis_41904528/data")
pv2_project_root <- .pv2_win_or_mnt("G:/02block_result/49_Dyslipidemia/prognosis_v2_mainval_41904528")
pv2_out_root <- file.path(pv2_project_root, "summary_results")
pv2_tab_dir <- file.path(pv2_out_root, "Tables")
pv2_fig_dir <- file.path(pv2_out_root, "Figures", "pdf")
pv2_ckpt_dir <- file.path(pv2_out_root, "checkpoints")

# 主库定协变量与扩展分析；CHARLS 只做验证
pv2_primary_dbs <- c("NHANES", "SHHS")
pv2_validation_dbs <- c("CHARLS")
pv2_all_dbs <- c("NHANES", "CHARLS", "SHHS")

pv2_ensure_dirs <- function() {
  for (d in c(pv2_tab_dir, pv2_fig_dir, pv2_ckpt_dir,
              file.path(pv2_out_root, "Figures", "png"),
              file.path(pv2_out_root, "Figures", "tiff"),
              file.path(pv2_out_root, "Figures", "image_information"),
              file.path(pv2_out_root, "reports"))) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(pv2_out_root)
}

pv2_role_label <- function(db) {
  if (db %in% pv2_primary_dbs) "Primary"
  else if (db %in% pv2_validation_dbs) "Validation"
  else "Other"
}

# 分析中间件（rds/笔记）放 checkpoints；Tables 只留发表 xlsx。
# 查找顺序：checkpoints → Tables（兼容旧落盘）
pv2_artifact <- function(name, must_exist = TRUE) {
  name <- as.character(name)[1L]
  cands <- c(file.path(pv2_ckpt_dir, name), file.path(pv2_tab_dir, name))
  hit <- cands[file.exists(cands)]
  if (!length(hit)) {
    if (isTRUE(must_exist)) stop("缺少中间文件: ", name, "（已查 checkpoints 与 Tables）")
    return(NA_character_)
  }
  hit[[1L]]
}

pv2_artifact_save <- function(obj, name) {
  pv2_ensure_dirs()
  path <- file.path(pv2_ckpt_dir, name)
  if (grepl("\\.rds$", name, ignore.case = TRUE)) {
    saveRDS(obj, path)
  } else if (is.character(obj)) {
    writeLines(obj, path)
  } else {
    stop("pv2_artifact_save: unsupported object for ", name)
  }
  invisible(path)
}

# 睡眠五分组（互斥）：含 <5 h 与 5-6 h（合起来即 <6 h 信息）
# Cox 参考水平放第一：7-8
pv2_sleep_levels_cox <- c("7-8", "<5", "5-6", "6-7", ">=9")
pv2_sleep_levels_display <- c("<5", "5-6", "6-7", "7-8", ">=9")
pv2_sleep_labels <- c(
  "<5" = "<5 h", "5-6" = "5-6 h", "6-7" = "6-7 h", "7-8" = "7-8 h", ">=9" = ">=9 h"
)

pv2_sleep_group5 <- function(hours, ref_first = TRUE) {
  h <- suppressWarnings(as.numeric(hours))
  g <- ifelse(!is.finite(h), NA_character_,
              ifelse(h < 5, "<5",
                     ifelse(h < 6, "5-6",
                            ifelse(h < 7, "6-7",
                                   ifelse(h < 9, "7-8", ">=9")))))
  lev <- if (isTRUE(ref_first)) pv2_sleep_levels_cox else pv2_sleep_levels_display
  factor(g, levels = lev)
}

pv2_sleep_ord <- function(g) {
  match(as.character(g), pv2_sleep_levels_display)
}

pv2_apply_sleep_group5 <- function(dbs) {
  out <- dbs
  for (nm in names(out)) {
    d <- as.data.frame(out[[nm]])
    d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
    out[[nm]] <- d
  }
  out
}
