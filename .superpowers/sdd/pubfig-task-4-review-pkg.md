# Review package Task 4
======= export_summary_figures.R =======
#!/usr/bin/env Rscript
# 交叉滞后 summary_result/figure：多库拼图 + 四目录发表导出
args <- commandArgs(trailingOnly = TRUE)
study_root <- as.character(args[[1L]] %||% "")[1L]
if (!nzchar(study_root) || !dir.exists(study_root)) {
  stop("need existing study_root as first argument", call. = FALSE)
}

eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(eng)) {
  cand <- normalizePath(file.path(study_root, "../.."), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "R/utils.R"))) {
    eng <- cand
  } else {
    eng <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
}

source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(eng, "R/pub_figure_export.R"), local = FALSE)
if (file.exists(file.path(eng, "R/cross_lagged_study_meta.R"))) {
  source(file.path(eng, "R/cross_lagged_study_meta.R"), local = FALSE)
}

fig <- file.path(study_root, "summary_result", "figure")
if (!dir.exists(fig)) {
  message("summary_result/figure 不存在，跳过 mosaic/export")
  quit(save = "no", status = 0)
}
dir.create(fig, recursive = TRUE, showWarnings = FALSE)

meta_g <- ""
if (exists("cross_lagged_study_meta", mode = "function")) {
  meta_g <- tryCatch(
    as.character(cross_lagged_study_meta(study_root)$grouping %||% "")[1L],
    error = function(e) ""
  )
}
if (!nzchar(meta_g)) {
  acc <- file.path(study_root, "phase3_relock_acceptance.txt")
  if (file.exists(acc)) {
    mg <- grep("^main_grouping=", readLines(acc, warn = FALSE), value = TRUE)
    if (length(mg)) meta_g <- sub("^main_grouping=", "", mg[1L])
  }
}

known_dbs <- c("CHARLS", "ELSA", "HRS", "NHANES", "CLHLS", "SHARE")
pdfs <- list.files(fig, pattern = "\\.pdf$", ignore.case = TRUE)
dbs <- character(0)
for (db in known_dbs) {
  if (any(grepl(paste0("-", db, "\\."), pdfs, ignore.case = TRUE))) {
    dbs <- c(dbs, db)
  }
}
if (exists("cross_lagged_study_meta", mode = "function")) {
  sm <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
  if (!is.null(sm)) {
    pref <- unique(c(sm$cohorts_xs %||% character(0), sm$cohorts_long %||% character(0)))
    pref <- pref[pref %in% dbs]
    dbs <- unique(c(pref, setdiff(dbs, pref)))
  }
}
dbs <- dbs[nzchar(dbs)]

cfg <- list(
  dual_db = list(
    combine_figures = list(enable = length(dbs) >= 2L, remove_singles = TRUE, dpi = 200L),
    databases = dbs,
    primary = list(name = if (length(dbs)) dbs[[1L]] else "primary"),
    secondary = list(name = if (length(dbs) >= 2L) dbs[[2L]] else "secondary"),
    tertiary = list(name = if (length(dbs) >= 3L) dbs[[3L]] else "")
  ),
  pub_figures = list(formats_dir = TRUE, dpi = 300L, write_image_information = TRUE)
)

tryCatch(
  dual_db_combine_paired_figures(study_root, cfg, figures_dir = fig),
  error = function(e) message("combine 跳过: ", conditionMessage(e))
)

tryCatch(
  export_pub_figures(
    fig,
    meta = list(
      databases = dbs,
      combined = length(dbs) >= 2L,
      grouping = meta_g
    ),
    config = cfg
  ),
  error = function(e) message("export 跳过: ", conditionMessage(e))
)

message("export_summary_figures: ", fig)

======= collect hooks =======
Blocks/54_cross_lagged_full/phases/collect_summary_result_hip.sh:512:Rscript "$ENG_ROOT/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY"
Blocks/54_cross_lagged_full/phases/collect_summary_result_circadian.sh:3:# mosaic/export 在 generic 末尾调用 export_summary_figures.R
Blocks/54_cross_lagged_full/phases/collect_summary_result.sh:16:  Rscript "$ENG_ROOT/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY"
Blocks/54_cross_lagged_full/phases/collect_summary_result_generic.sh:557:Rscript "$ENG_ROOT/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY"
--- tail Blocks/54_cross_lagged_full/phases/collect_summary_result.sh ---
   { [[ ! -f "$STUDY/config_long_panel.R" ]] || ! grep -qE "circadian_index_var" "$STUDY/config_long_panel.R" 2>/dev/null; }
then
  # 表名仍是髋部时才走旧脚本（新课题即使目录叫 allages 也用 generic）
  if ls "$STUDY"/phase1_CHARLS_allages/Tables/*Hip* >/dev/null 2>&1 ||
     ls "$STUDY"/summary_result/table/*Hip* >/dev/null 2>&1
  then
    _is_hip=1
  fi
fi

if [[ "$_is_hip" == "1" ]]; then
  bash "$HERE/collect_summary_result_hip.sh" "$STUDY"
else
  bash "$HERE/collect_summary_result_generic.sh" "$STUDY"
fi
--- tail Blocks/54_cross_lagged_full/phases/collect_summary_result_circadian.sh ---
#!/usr/bin/env bash
# Back-compat alias: circadian-specific collect is now the generic collector.
# mosaic/export 在 generic 末尾调用 export_summary_figures.R
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
bash "$HERE/collect_summary_result_generic.sh" "$@"
--- tail Blocks/54_cross_lagged_full/phases/collect_summary_result_generic.sh ---
  echo "=== figure ==="; ls -1 "$FIG" | sort
  echo; echo "=== table ==="; ls -1 "$TAB" | sort
} > "$OUT/MANIFEST.txt"

echo "Done: $OUT"
echo "figure: $(ls -1 "$FIG" | wc -l)  table: $(ls -1 "$TAB" | wc -l)"
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "MISSING ${#missing[@]} publication slots (see $OUT/MANIFEST.txt)" >&2
fi

ENG_ROOT="${MEDICAL_BLOCKS_ROOT:-}"
if [[ -z "$ENG_ROOT" ]]; then
  ENG_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fi
Rscript "$ENG_ROOT/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY"
--- tail Blocks/54_cross_lagged_full/phases/collect_summary_result_hip.sh ---
  echo "summary policy: main logistic=tertile; Change S5=auto(2y/3y+); S5.1=all two_wave; S6=corr Crude/M1/M2(M1≠M2); S7=merged longitudinal mediation only; S8=CLPN adjacency with FI item labels; S1/S2=CLPN bootstrap stability (lit Supp 25–26); S9–S17.1 sensitivity (chronic>=2 / complete-case unimputed listwise N may be <AfterMI / exclude event<=2y; competing_risk skipped); no per-DB S7; no S9 flowchart tables"
  echo "attrition: drop if baseline ID absent from ALL follow-up years; FU time = first disease year else last FU year"
  echo
  echo "=== figure ==="; ls -1 "$OUT/figure" 2>/dev/null | sort || true
  echo; echo "=== table ==="; ls -1 "$OUT/table" 2>/dev/null | sort || true
} > "$OUT/MANIFEST.txt"

echo "Done: $OUT"
echo "figure: $(ls -1 "$OUT/figure" 2>/dev/null | wc -l)  table: $(ls -1 "$OUT/table" 2>/dev/null | wc -l)"

ENG_ROOT="${MEDICAL_BLOCKS_ROOT:-}"
if [[ -z "$ENG_ROOT" ]]; then
  ENG_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fi
Rscript "$ENG_ROOT/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY"
