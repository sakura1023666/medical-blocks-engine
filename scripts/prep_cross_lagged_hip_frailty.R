#!/usr/bin/env Rscript
# scripts/prep_cross_lagged_hip_frailty.R
suppressPackageStartupMessages({
  library(dplyr)
})

study_root <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
if (!dir.exists(study_root))
  study_root <- "G:/02block_result/16_Hip fracture/cross-laged_40595747"
raw <- file.path(study_root, "data")
out <- file.path(raw, "harmonized")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

load_df <- function(path, obj = NULL) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  if (is.null(obj)) {
    nms <- ls(e)
    if (length(nms) != 1L) stop("期望单对象: ", path, " 有 ", paste(nms, collapse = ","))
    obj <- nms[[1L]]
  }
  as.data.frame(e[[obj]])
}

recode_outcome <- function(x) {
  ifelse(is.na(x), NA_character_,
         ifelse(as.character(x) %in% c("1", "Hip_Fracture", "Patellar_Fracture"), "Hip_Fracture",
                ifelse(as.character(x) %in% c("0", "No_Fracture"), "No_Fracture", NA_character_)))
}

to_id <- function(x) as.character(as.vector(x))

fi_p <- function(fi, y) {
  ok <- !is.na(fi) & !is.na(y)
  if (sum(ok) < 10L) return(NA_real_)
  tryCatch(wilcox.test(fi[ok] ~ factor(y[ok]))$p.value, error = function(e) NA_real_)
}

prep_frailty <- function(path, id_col = "ID", n_items = NULL) {
  fr <- read.csv(path, check.names = FALSE)
  if (!id_col %in% names(fr)) stop("虚弱文件缺少 ID 列: ", id_col, " in ", path)
  fr$ID <- to_id(fr[[id_col]])
  if (!"FI" %in% names(fr)) {
    total_col <- if (!is.null(n_items) && n_items == 27L) "frailty27_total" else "frailty26_total"
    if (!total_col %in% names(fr))
      stop("虚弱文件缺少 FI 或 ", total_col, ": ", path)
    fr$FI <- fr[[total_col]] / n_items
  }
  fr[, c("ID", "FI"), drop = FALSE]
}

qc_row <- function(cohort, dabiao) {
  n_event <- sum(dabiao$Disease_Group == "Hip_Fracture", na.rm = TRUE)
  p_val <- fi_p(dabiao$FI, dabiao$Disease_Group)
  note <- if (!is.na(p_val) && p_val >= 0.05) "FI_NS_WARN" else ""
  data.frame(
    cohort = cohort,
    n = nrow(dabiao),
    n_event = n_event,
    fi_mean = mean(dabiao$FI, na.rm = TRUE),
    fi_median = median(dabiao$FI, na.rm = TRUE),
    frailty_prev = mean(dabiao$Frailty, na.rm = TRUE),
    fi_p_vs_outcome = p_val,
    note = note,
    stringsAsFactors = FALSE
  )
}

merge_cohort <- function(bl, fr, outc) {
  outc$Disease_Group <- recode_outcome(outc$Disease_Group)
  dabiao <- bl %>%
    inner_join(fr, by = "ID") %>%
    inner_join(outc[, c("ID", "Disease_Group")], by = "ID")
  dabiao <- dabiao[!is.na(dabiao$FI) & !is.na(dabiao$Disease_Group), ]
  dabiao$Frailty <- as.integer(dabiao$FI >= 0.25)
  dabiao
}

# --- CHARLS 2011 ---
bl <- load_df(file.path(raw, "CHARLS", "D01_baseline_CHARLS_2011_0729.RData"), "baseline")
bl$ID <- to_id(bl$ID)
fr <- prep_frailty(file.path(raw, "CHARLS", "虚弱_charls_2011.csv"), id_col = "ID", n_items = 26L)
outc <- load_df(file.path(raw, "CHARLS", "D03_result_CHARLS_2011.RData"))
names(outc)[names(outc) == setdiff(names(outc), "Disease_Group")[1]] <- "ID"
outc$ID <- to_id(outc$ID)
dabiao_charls <- merge_cohort(bl, fr, outc)
dabiao <- dabiao_charls
save(dabiao, file = file.path(out, "D04_CHARLS_hip_baseline.RData"))

# --- ELSA wave2 ---
bl <- load_df(file.path(raw, "ELSA", "D01_baseline_ELSA2_2004_0729.RData"), "baseline")
bl$ID <- to_id(bl$ID)
fr <- prep_frailty(file.path(raw, "ELSA", "虚弱_elsa_wave2.csv"), id_col = "idauniq", n_items = 27L)
outc <- load_df(file.path(raw, "ELSA", "D03_result_ELSA2.RData"))
names(outc)[names(outc) == setdiff(names(outc), "Disease_Group")[1]] <- "ID"
outc$ID <- to_id(outc$ID)
dabiao_elsa <- merge_cohort(bl, fr, outc)
dabiao <- dabiao_elsa
save(dabiao, file = file.path(out, "D04_ELSA_hip_baseline.RData"))

# --- HRS 2012 ---
bl <- load_df(file.path(raw, "HRS", "D01_baseline_HRS_2012_0729.RData"), "baseline")
bl$ID <- to_id(bl$ID)
fr <- prep_frailty(file.path(raw, "HRS", "虚弱_hrs_2012.csv"), id_col = "hhidpn", n_items = 26L)
outc <- load_df(file.path(raw, "HRS", "D03_result_HRS12.RData"))
names(outc)[names(outc) == setdiff(names(outc), "Disease_Group")[1]] <- "ID"
outc$ID <- to_id(outc$ID)
dabiao_hrs <- merge_cohort(bl, fr, outc)
dabiao <- dabiao_hrs
save(dabiao, file = file.path(out, "D04_HRS_hip_baseline.RData"))

# --- prep_qc.csv ---
qc <- rbind(
  qc_row("CHARLS", dabiao_charls),
  qc_row("ELSA", dabiao_elsa),
  qc_row("HRS", dabiao_hrs)
)
write.csv(qc, file.path(out, "prep_qc.csv"), row.names = FALSE)

message("Wrote harmonized baseline RData + prep_qc.csv to ", out)
print(qc)
