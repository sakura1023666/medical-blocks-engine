#!/usr/bin/env bash
# 髋部骨折 × FI 交叉滞后：按年龄切点全量重跑，交付对齐抑郁课题 summary_result 构成
# （Figures/{pdf,png,tiff,image_information} + Tables + Methods + figure/ + 中期；含 CLPN bootstrap）
#
# 用法（仓库根）:
#   bash Blocks/54_cross_lagged_full/phases/rerun_hip_age_cut.sh 50
#   bash Blocks/54_cross_lagged_full/phases/rerun_hip_age_cut.sh 65
#
# 产出:
#   引擎: Output/16_Hip_fracture_cross-laged_40595747_age{CUT}/summary_result
#   课题盘: .../16_Hip fracture/cross-laged_40595747/summary_result（{CUT}）
set -euo pipefail

AGE_CUT="${1:?need age cut 50 or 65}"
if [[ "$AGE_CUT" != "50" && "$AGE_CUT" != "65" ]]; then
  echo "AGE_CUT must be 50 or 65" >&2
  exit 1
fi

ENGINE="${MEDICAL_BLOCKS_ROOT:-/mnt/e/01block/01Block-new-Final}"
G_SRC="/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
STUDY="$ENGINE/Output/16_Hip_fracture_cross-laged_40595747_age${AGE_CUT}"
# 全角括号，与用户要求 summary_result（50）/（65）一致
G_SUMMARY_NAME="summary_result（${AGE_CUT}）"
G_DEST="$G_SRC/$G_SUMMARY_NAME"
BACKUP="$G_SRC/data/harmonized/_backup_pre_age65"

export MEDICAL_BLOCKS_ROOT="$ENGINE"
export SMOKE_NO_FEISHU=1
export CROSS_LAGGED_STUDY_ROOT="$STUDY"
export CROSS_LAGGED_SYNC_ROOT="$G_SRC"
# 文献对齐：边权 + case-dropping 各 1000
export CROSS_LAGGED_BOOT_EDGE="${CROSS_LAGGED_BOOT_EDGE:-1000}"
export CROSS_LAGGED_BOOT_CASE="${CROSS_LAGGED_BOOT_CASE:-1000}"

cd "$ENGINE"
CL_RUN="Rscript run/cross_lagged/run_cross_lagged_frailty.R"
LOG="$STUDY/_logs/rerun_age${AGE_CUT}_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$STUDY/_logs"
exec > >(tee -a "$LOG") 2>&1

ts() { date '+%F %T'; }
step() { echo; echo "======== [$(ts)] $* ========"; }

step "0) Prepare study workspace → $STUDY"
mkdir -p "$STUDY/data/harmonized" "$STUDY/_logs"
# 配置与原始/中介数据从课题盘拷入
rsync -a --delete \
  --exclude 'phase1_*' --exclude 'phase2_*' --exclude 'phase3_*' \
  --exclude 'summary_result*' --exclude 'sensitivity' \
  --exclude '_logs*' --exclude 'rerun_*' --exclude '*.log' --exclude '*.nohup*' \
  --exclude 'data/harmonized/_backup_pre_age65' \
  "$G_SRC/" "$STUDY/" || {
  # rsync 失败时至少保证关键文件
  cp -a "$G_SRC"/config_phase*.R "$STUDY/"
  mkdir -p "$STUDY/data"
  rsync -a "$G_SRC/data/" "$STUDY/data/"
}

# 指针文件
echo "$G_SRC" > "$STUDY/CROSS_LAGGED_SYNC_ROOT"
# 重写 config 内 study_root / source 路径到本引擎目录
python3 - <<PY
from pathlib import Path
import re
study = Path("$STUDY")
old_roots = [
    "/mnt/e/01block/01Block-new-Final/Output/16_Hip_fracture_cross-laged_40595747_allages",
    "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747",
    "/mnt/g/02block_result/16_Patellar fracture/cross-laged_40595747",
]
new_root = str(study)
for p in list(study.glob("config_phase*.R")):
    t = p.read_text(encoding="utf-8")
    for old in old_roots:
        t = t.replace(old, new_root)
    # phase2 source() 必须指向本 study 的 phase1
    t = re.sub(
        r'source\("[^"]+/config_phase1_(CHARLS|ELSA|HRS)\.R"\)',
        lambda m: f'source("{new_root}/config_phase1_{m.group(1)}.R")',
        t,
    )
    p.write_text(t, encoding="utf-8")
    print("patched", p.name)
PY

step "1) Restore all-ages baselines then filter Age>=${AGE_CUT}"
if [[ ! -f "$BACKUP/D04_HRS_hip_baseline.allages.RData" ]]; then
  echo "ERROR: missing backup $BACKUP" >&2
  exit 1
fi
for db in CHARLS ELSA HRS; do
  cp -a "$BACKUP/D04_${db}_hip_baseline.allages.RData" \
        "$STUDY/data/harmonized/D04_${db}_hip_baseline.RData"
done

Rscript -e '
age_cut <- as.integer("'"$AGE_CUT"'")
study <- "'"$STUDY"'"
lines <- c(
  sprintf("time=%s", format(Sys.time(), "%F %T")),
  sprintf("rule=Age >= %d", age_cut),
  sprintf("drop_if=!is.finite(Age) | Age < %d", age_cut)
)
for (db in c("CHARLS","ELSA","HRS")) {
  f <- file.path(study, "data/harmonized", sprintf("D04_%s_hip_baseline.RData", db))
  e <- new.env(parent = emptyenv())
  load(f, envir = e)
  stopifnot(exists("dabiao", envir = e))
  d <- e$dabiao
  a <- suppressWarnings(as.numeric(d$Age))
  n0 <- nrow(d)
  keep <- is.finite(a) & a >= age_cut
  d2 <- d[keep, , drop = FALSE]
  dabiao <- d2
  save(dabiao, file = f)
  a2 <- suppressWarnings(as.numeric(d2$Age))
  lines <- c(lines, sprintf(
    "%s: N_before=%d N_after=%d dropped=%d Age_range=[%.1f,%.1f] cases=%d",
    db, n0, nrow(d2), n0 - nrow(d2),
    min(a2, na.rm = TRUE), max(a2, na.rm = TRUE),
    sum(as.character(d2$Disease_Group) == "Hip_Fracture", na.rm = TRUE)
  ))
  cat(lines[length(lines)], "\n")
  stopifnot(nrow(d2) > 50L, min(a2, na.rm = TRUE) >= age_cut)
}
writeLines(lines, file.path(study, sprintf("age%d_cohort_filter.txt", age_cut)))
cat("OK age filter\n")
'

cat > "$STUDY/README_COHORT.txt" <<EOF
Cohort policy:
- Age >= ${AGE_CUT} (finite Age required)
- HRS: NO drop for missing HDL / controls (full HRS baseline then age filter)
- ELSA longitudinal years: 2004 / 2008 / 2012 / 2016 (wave2/4/6/8)
- Mediation primary: Depression (no blood-lab pilot as primary)
- Covariates Model2 = 三库 Table S4 / VIF_screen_pass 交集
- CLPN bootstrap: n_boot_edge=${CROSS_LAGGED_BOOT_EDGE}, n_boot_case=${CROSS_LAGGED_BOOT_CASE}
- Workspace: $STUDY
- Delivery folder on project disk: $G_DEST
EOF

step "2) Wipe previous phase / summary / sensitivity outputs"
cd "$STUDY"
rm -rf \
  phase1_CHARLS_allages phase1_ELSA_allages phase1_HRS_allages \
  phase1_CHARLS phase1_ELSA phase1_HRS \
  phase1_CHARLS_v2 phase1_ELSA_v2 phase1_HRS_v2 \
  phase2_Pooled phase3_post_Pooled \
  phase3_long_CHARLS phase3_long_ELSA phase3_long_HRS phase3_long_Pooled \
  summary_result sensitivity 2>/dev/null || true
rm -f \
  mediation_depression_covar_lock.rds \
  mediation_depression_covar_lock.txt \
  phase2_acceptance.txt \
  phase3_relock_acceptance.txt \
  data/harmonized/D04_Pooled_hip_postvif.RData \
  data/harmonized/D05_long_mediation_Pooled.RData 2>/dev/null || true
cd "$ENGINE"

step "3) PHASE1 CHARLS / ELSA / HRS"
for db in CHARLS ELSA HRS; do
  step "PHASE1 $db"
  Rscript run/incidence/run_incidence_single.R --config "$STUDY/config_phase1_${db}.R"
done

step "4) PHASE2 vif_pooled"
$CL_RUN --phase vif_pooled --study-root "$STUDY" --no-sync

step "5) PHASE3 post_vif"
$CL_RUN --phase post_vif --study-root "$STUDY" --no-sync

step "6) PHASE3 relock"
$CL_RUN --phase relock --study-root "$STUDY" --no-sync

step "7) PHASE3 long_figs (+pooled, sims=200)"
$CL_RUN --phase long_figs --study-root "$STUDY" --sims 200 --with-pooled --no-sync

step "8) PHASE3 subgroup"
$CL_RUN --phase subgroup --study-root "$STUDY" --no-sync

step "9) sensitivity (S9–S17)"
$CL_RUN --phase sensitivity --study-root "$STUDY" --no-sync

step "10) summary collect"
$CL_RUN --phase summary --study-root "$STUDY" --no-sync || true
bash "$ENGINE/Blocks/54_cross_lagged_full/phases/collect_summary_result.sh" "$STUDY" || true

step "11) pub_figs (Fig4 CLPN + Mean FI + CLPN bootstrap S1/S2)"
$CL_RUN --phase pub_figs --study-root "$STUDY" --no-sync

step "12) re-collect after pub_figs"
$CL_RUN --phase summary --study-root "$STUDY" --no-sync || true
bash "$ENGINE/Blocks/54_cross_lagged_full/phases/collect_summary_result.sh" "$STUDY" || true

step "13) Copy Figure2 RCS into summary_result/figure if missing"
for db in CHARLS ELSA HRS; do
  src=$(ls -1t "$STUDY/phase1_${db}_allages/Figures/Figure 2-${db}. RCS"*.pdf 2>/dev/null | head -1 || true)
  if [[ -n "${src:-}" && -f "$src" ]]; then
    mkdir -p "$STUDY/summary_result/figure"
    dest="Figure 2-${db}. RCS plot between Frailty Index and Hip Fracture.pdf"
    cp -f "$src" "$STUDY/summary_result/figure/$dest"
  fi
done
srcp="$STUDY/phase3_post_Pooled/Figures/Figure 4-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf"
if [[ -f "$srcp" ]]; then
  dest="Figure 2-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf"
  mkdir -p "$STUDY/summary_result/figure"
  cp -f "$srcp" "$STUDY/summary_result/figure/$dest"
fi

step "14) export_summary_figures → Figures/{pdf,image_information} (+png/tiff)"
Rscript "$ENGINE/Blocks/54_cross_lagged_full/phases/export_summary_figures.R" "$STUDY" || true

# 强制补齐 png/tiff 以对齐抑郁 summary_result 四目录
Rscript -e '
eng <- "'"$ENGINE"'"
study <- "'"$STUDY"'"
source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "R/pub_figure_export.R"), local = FALSE)
fig_roots <- c(
  file.path(study, "summary_result", "Figures"),
  file.path(study, "summary_result", "figure")
)
cfg <- list(pub_figures = list(
  formats_dir = TRUE, export_png = TRUE, export_tiff = TRUE,
  dpi = 600L, write_image_information = TRUE
))
for (fr in fig_roots) {
  if (!dir.exists(fr)) next
  pdfs <- list.files(fr, pattern = "\\.pdf$", full.names = TRUE)
  if (length(pdfs) && !dir.exists(file.path(fr, "pdf"))) {
    dir.create(file.path(fr, "pdf"), recursive = TRUE, showWarnings = FALSE)
    file.copy(pdfs, file.path(fr, "pdf"), overwrite = TRUE)
  }
  tryCatch(
    pub_figure_ensure_formats(fr, config = cfg),
    error = function(e) message("ensure_formats skip ", fr, ": ", conditionMessage(e))
  )
}
message("png/tiff ensure done")
'

step "15) Tables 白名单目录 + Methods"
mkdir -p "$STUDY/summary_result/Tables" \
         "$STUDY/summary_result/Figures/pdf" \
         "$STUDY/summary_result/Figures/image_information" \
         "$STUDY/summary_result/figure/pdf" \
         "$STUDY/summary_result/new"
# table → Tables
if [[ -d "$STUDY/summary_result/table" ]]; then
  find "$STUDY/summary_result/table" -maxdepth 1 -type f -name '*.xlsx' \
    -exec cp -a {} "$STUDY/summary_result/Tables/" \;
fi
# figure 扁平 pdf → figure/pdf（抑郁同构）
if [[ -d "$STUDY/summary_result/figure" ]]; then
  find "$STUDY/summary_result/figure" -maxdepth 1 -type f -name '*.pdf' \
    -exec cp -a {} "$STUDY/summary_result/figure/pdf/" \;
fi
# 若 Figures/pdf 仍空，从 figure 吸收
n_fig=$(find "$STUDY/summary_result/Figures/pdf" -maxdepth 1 -name '*.pdf' 2>/dev/null | wc -l)
if [[ "$n_fig" -lt 1 ]]; then
  find "$STUDY/summary_result/figure" -maxdepth 2 -type f -name '*.pdf' \
    -exec cp -a {} "$STUDY/summary_result/Figures/pdf/" \; || true
fi
# touch new/t 对齐抑郁占位
: > "$STUDY/summary_result/new/t"

Rscript -e '
eng <- "'"$ENGINE"'"
study <- "'"$STUDY"'"
age_cut <- as.integer("'"$AGE_CUT"'")
source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "R/cross_lagged_methods_pub.R"), local = FALSE)
source(file.path(eng, "R/pub_software_versions.R"), local = FALSE)
cfg <- list(project = list(
  analysis_group = "Hip fracture",
  disease = "Hip fracture",
  exposure = "Frailty Index",
  databases = c("CHARLS", "ELSA", "HRS")
))
lines <- cross_lagged_methods_statistical_lines(cfg)
# 年龄门控说明插在 Exposure 前
ins <- c(
  "",
  "## Cohort age restriction",
  sprintf(
    "The analytic sample was restricted to participants aged %d years or older at baseline (Age ≥ %d; non-finite ages excluded). Separate deliveries are produced for Age ≥ 50 and Age ≥ 65.",
    age_cut, age_cut
  ),
  ""
)
# 插到 "## Exposure and outcome" 之前
i <- match("## Exposure and outcome", lines)
if (!is.na(i)) lines <- c(lines[seq_len(i - 1L)], ins, lines[i:length(lines)])
md <- file.path(study, "summary_result", "Methods_statistical_analysis.md")
writeLines(lines, md)
# Software versions
sum_root <- file.path(study, "summary_result")
sv <- file.path(sum_root, "Methods_software_versions.txt")
# 若误把文件路径当目录写成了嵌套，先拆平
if (dir.exists(sv)) {
  nested <- file.path(sv, "Methods_software_versions.txt")
  if (file.exists(nested)) {
    file.copy(nested, file.path(tempdir(), "Methods_software_versions.txt"), overwrite = TRUE)
    unlink(sv, recursive = TRUE)
    file.copy(file.path(tempdir(), "Methods_software_versions.txt"), sv, overwrite = TRUE)
  } else {
    unlink(sv, recursive = TRUE)
  }
}
tryCatch({
  if (exists("pub_write_software_versions", mode = "function")) {
    # API: 第一个参数是目录（index_root），不是文件路径
    pub_write_software_versions(sum_root)
  } else {
    writeLines(c(
      paste0("R version: ", paste(R.version$major, R.version$minor, sep = ".")),
      paste0("Platform: ", R.version$platform),
      paste0("Generated: ", format(Sys.time(), "%F %T"))
    ), sv)
  }
}, error = function(e) {
  writeLines(c(
    paste0("R version: ", paste(R.version$major, R.version$minor, sep = ".")),
    paste0("Generated: ", format(Sys.time(), "%F %T")),
    paste0("note: ", conditionMessage(e))
  ), sv)
})
# append Software section to methods if helper exists
tryCatch({
  if (exists("pub_append_software_section_to_methods", mode = "function")) {
    pub_append_software_section_to_methods(md, sv)
  } else if (file.exists(sv) && !dir.exists(sv)) {
    cat("\n## Software\n\n", file = md, append = TRUE)
    cat(paste(readLines(sv, warn = FALSE), collapse = "\n"), "\n", file = md, append = TRUE)
  }
}, error = function(e) message(conditionMessage(e)))
message("Methods written: ", md)
'

step "16) midterm PDF"
$CL_RUN --phase midterm --study-root "$STUDY" --no-sync || true

step "17) Deliver to project disk: $G_DEST"
mkdir -p "$G_DEST"
# 完整 summary_result 镜像（含 figure/table/Figures/Tables/Methods/中期）
rsync -a --delete "$STUDY/summary_result/" "$G_DEST/" || \
  cp -a "$STUDY/summary_result/." "$G_DEST/"

# 记录
cat > "$G_DEST/MANIFEST_AGE.txt" <<EOF
age_cut=${AGE_CUT}
engine_study=$STUDY
synced_at=$(ts)
boot_edge=${CROSS_LAGGED_BOOT_EDGE}
boot_case=${CROSS_LAGGED_BOOT_CASE}
log=$LOG
EOF

step "18) Inventory vs depression layout + hip slot counts"
Rscript -e '
dep <- "/mnt/g/02block_result/22_depression/cross-laged_40595747/summary_result"
hip <- "'"$G_DEST"'"
need_dirs <- c("Figures", "Tables", "figure", "new")
need_files <- c("Methods_statistical_analysis.md", "Methods_software_versions.txt")
miss <- character(0)
for (d in need_dirs) if (!dir.exists(file.path(hip, d))) miss <- c(miss, paste0("dir:", d))
for (f in need_files) if (!file.exists(file.path(hip, f))) miss <- c(miss, paste0("file:", f))
for (sub in c("pdf", "png", "tiff", "image_information")) {
  if (!dir.exists(file.path(hip, "Figures", sub))) miss <- c(miss, paste0("Figures/", sub))
}
n_tab <- length(list.files(file.path(hip, "Tables"), pattern = "\\.xlsx$"))
n_fig <- length(list.files(file.path(hip, "Figures", "pdf"), pattern = "\\.pdf$"))
n_mid <- length(list.files(hip, pattern = "中期|midterm", ignore.case = TRUE))
boot_ok <- any(grepl("CLPN edge weight bootstrap", list.files(file.path(hip, "figure"), recursive = TRUE))) ||
  any(grepl("CLPN edge weight bootstrap", list.files(file.path(hip, "Figures"), recursive = TRUE)))
cat(sprintf("Tables xlsx=%d  Figures/pdf=%d  midterm=%d  bootstrap_fig=%s\n",
            n_tab, n_fig, n_mid, boot_ok))
if (length(miss)) {
  cat("MISSING layout pieces:\n", paste(miss, collapse = "\n"), "\n")
} else {
  cat("OK: depression-like top-level layout present\n")
}
# depression top-level names for reference
cat("dep top:", paste(list.files(dep), collapse = " | "), "\n")
cat("hip top:", paste(list.files(hip), collapse = " | "), "\n")
writeLines(c(
  sprintf("tables=%d", n_tab),
  sprintf("figures_pdf=%d", n_fig),
  sprintf("midterm=%d", n_mid),
  sprintf("bootstrap=%s", boot_ok),
  sprintf("missing=%s", if (length(miss)) paste(miss, collapse = ";") else "none")
), file.path(hip, "MANIFEST_COUNT.txt"))
'

step "DONE Age>=${AGE_CUT}"
echo "Log: $LOG"
echo "Engine: $STUDY/summary_result"
echo "G disk: $G_DEST"
ls -la "$G_DEST" | head -30
