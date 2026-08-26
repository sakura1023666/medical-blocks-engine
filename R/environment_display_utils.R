###############################################################################
#  environment_display_utils.R — 环境 VOC 流水线展示名（下划线→空格，AMC→AMCC）
###############################################################################

#' 单变量展示名
environment_display_label <- function(x, label_map = NULL) {
  x <- as.character(x)
  if (!length(x)) return(x)
  out <- gsub("_", " ", x, fixed = TRUE)
  out <- gsub("\\bAMC\\b", "AMCC", out, perl = TRUE)
  out <- gsub("\\bURXAMC\\b", "AMCC", out, perl = TRUE)
  if (!is.null(label_map) && length(label_map)) {
    hit <- label_map[out]
    na_hit <- is.na(hit) | !nzchar(hit)
    if (any(!na_hit)) {
      orig_names <- names(label_map)
      if (length(orig_names)) {
        by_key <- label_map[x]
        by_key <- ifelse(is.na(by_key) | !nzchar(by_key), out, by_key)
        out <- by_key
      }
    }
    for (nm in names(label_map)) {
      out[x == nm] <- as.character(label_map[[nm]])
    }
  }
  out
}

environment_default_label_map <- function(cfg = NULL) {
  cfg <- cfg %||% list()
  env <- cfg$environment %||% list()
  extra <- env$display_label_map %||% list()
  c(AMC = "AMCC", URXAMC = "AMCC", extra)
}

environment_resolve_label_map <- function(cfg, bl_map = NULL) {
  base <- environment_default_label_map(cfg)
  root <- (cfg$project %||% list())$root %||%
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  pretty <- if (exists("environment_voc_exposure_name_map", mode = "function")) {
    environment_voc_exposure_name_map()
  } else {
    character(0)
  }
  .pretty_exposure <- function(ex) {
    ex <- as.character(ex)[1L]
    if (!nzchar(ex)) return(ex)
    if (length(pretty) && ex %in% names(pretty)) {
      return(as.character(pretty[[ex]])[1L])
    }
    # 下划线化学名 → 空格（最终发表展示）
    gsub("_", " ", ex, fixed = TRUE)
  }
  if (exists("environment_load_exposure_code_df", mode = "function")) {
    code <- environment_load_exposure_code_df(cfg, root)
    if (!is.null(code) && nrow(code)) {
      abbr_col <- if ("Abbreviation" %in% names(code)) {
        "Abbreviation"
      } else if ("Labels" %in% names(code)) {
        "Labels"
      } else {
        names(code)[1L]
      }
      exp_col <- if ("Exposure" %in% names(code)) "Exposure" else NULL
      if (!is.null(exp_col)) {
        for (i in seq_len(nrow(code))) {
          ab <- as.character(code[[abbr_col]][i])
          ex <- as.character(code[[exp_col]][i])
          if (!nzchar(ab) || !nzchar(ex)) next
          # 跳过代码镜像行（Exposure==Labels），留给后续真实名/别名
          if (identical(ab, ex)) next
          disp <- .pretty_exposure(ex)
          base[[ab]] <- disp
          base[[gsub("_", " ", ab, fixed = TRUE)]] <- disp
          # 也允许用中间名（如 MHA_3_4）反查
          base[[ex]] <- disp
        }
      }
    }
  }
  # 内置别名兜底（无代码表时至少 AMCC 等可映射）
  if (length(pretty)) {
    for (nm in names(pretty)) {
      if (is.null(base[[nm]]) || !nzchar(base[[nm]] %||% "")) {
        base[[nm]] <- as.character(pretty[[nm]])[1L]
      }
    }
  }
  bl_map <- bl_map %||% character(0)
  if (length(bl_map)) {
    for (nm in names(bl_map)) base[[nm]] <- as.character(bl_map[[nm]])
  }
  base
}

#' 对 data.frame 指定列应用展示名
environment_prettify_df_cols <- function(df, cols, label_map = NULL) {
  if (is.null(df) || !is.data.frame(df) || !nrow(df)) return(df)
  for (cn in cols) {
    if (!cn %in% names(df)) next
    if (is.character(df[[cn]]) || is.factor(df[[cn]])) {
      df[[cn]] <- environment_display_label(as.character(df[[cn]]), label_map)
    }
  }
  df
}

#' 命名向量展示名（保持 names 为内部列名时可传 names(gs)）
environment_prettify_names <- function(nms, label_map = NULL) {
  if (!length(nms)) return(nms)
  old <- nms
  new <- environment_display_label(old, label_map)
  stats::setNames(old, new)
}

environment_prettify_named_vector <- function(x, label_map = NULL) {
  if (!length(x)) return(x)
  nm <- names(x)
  if (is.null(nm)) return(x)
  new_nm <- environment_display_label(nm, label_map)
  stats::setNames(as.vector(x), new_nm)
}
