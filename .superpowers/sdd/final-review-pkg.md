# Final review package — pub-digits est2/cutoff3
Plan: docs/superpowers/plans/2026-09-22-pub-digits-est2-cutoff3.md
Spec: docs/superpowers/specs/2026-09-22-pub-digits-est2-cutoff3-design.md

## Files changed (working tree vs task baselines / new files)
- NEW: tests/test_pub_digits_defaults.R
- MOD: R/utils.R (pub_digits defaults + comments + pub_format_est fallback)
- MOD: .cursor/rules/pub_digits_consistency.mdc
- MOD: configs/templates/config_incidence_dual_batch.template.R
- MOD: configs/templates/config_survival_dual_batch.template.R
- MOD: configs/templates/config_pa_mobility_cognitive.template.R
- MOD: Blocks/20_mediation/00mediation_common.R
- MOD: Blocks/20_mediation/01block_mediation_prognosis.R

## Engine defaults (current)
# 发表级小数位（全项目统一入口；config$pub_digits / options 可覆盖）
# 默认：效应量(OR/HR/RR+CI) 2 位；P 3 位（<0.001）；描述统计 2 位；切点 3 位
.pipeline_pub_digits <- function() {
  list(
    est = as.integer(getOption("medical_blocks.pub_digits.est", 2L))[1L],
    p = as.integer(getOption("medical_blocks.pub_digits.p", 3L))[1L],
    desc = as.integer(getOption("medical_blocks.pub_digits.desc", 2L))[1L],
    cutoff = as.integer(getOption("medical_blocks.pub_digits.cutoff", 3L))[1L],
    # 整数（人数 / 事件数 / 计数）千分位：TRUE=1,234；FALSE=1234（全项目单一口径）
    int_big_mark = isTRUE(getOption("medical_blocks.pub_digits.int_big_mark", TRUE))
  )
}
pub_format_est <- function(x, digits = NULL) {
  dig <- as.integer(digits %||% .pipeline_pub_digits()$est)[1L]
  if (!is.finite(dig) || dig < 0L) dig <- 2L
  # 向量必须逐元素格式化：若只处理首元并返回长度 1，赋值进 data.frame
  # 列时会整列回收成同一个数（Table S5 AUC 曾全表塌成 0.592）。
  if (length(x) != 1L) {
    return(vapply(x, function(xi) pub_format_est(xi, digits = dig),
  p <- normalizePath(file.path(ob, "prediction_by_index", probe_tag), winslash = "/", mustWork = FALSE)
  if (nzchar(p) && dir.exists(p)) {
    unlink(p, recursive = TRUE)

## Template/rule pub_digits lines
configs/config_pa_mobility_cognitive.R:29:  pub_digits = list(est = 3L, p = 3L, desc = 2L, cutoff = 4L),
configs/templates/config_incidence_dual_batch.template.R:65:  pub_digits = list(est = 2L, p = 3L, desc = 2L, cutoff = 3L, int_big_mark = TRUE),
configs/templates/config_survival_dual_batch.template.R:42:  pub_digits = list(est = 2L, p = 3L, desc = 2L, cutoff = 3L, int_big_mark = TRUE),
.cursor/rules/pub_digits_consistency.mdc:14:   - 效应量 OR / HR / CI：`est = 2`
.cursor/rules/pub_digits_consistency.mdc:35:config$pub_digits <- list(est = 2L, p = 3L, desc = 2L, cutoff = 3L, int_big_mark = TRUE)
configs/templates/config_pa_mobility_cognitive.template.R:29:  pub_digits = list(est = 2L, p = 3L, desc = 2L, cutoff = 3L, int_big_mark = TRUE),

## Mediation d_est
Blocks/20_mediation/01block_mediation_prognosis.R:97:  .path_lbl_p_below_ci <- function(est, p, lo, hi,
Blocks/20_mediation/01block_mediation_prognosis.R:98:                                     d_est = as.integer(.pipeline_pub_digits()$est)[1L]) {
Blocks/20_mediation/01block_mediation_prognosis.R:99:    L1 <- paste0(.fc(est, d_est), " (", .fp(p), ")")
Blocks/20_mediation/01block_mediation_prognosis.R:101:      c(L1, paste0("(", .fc(lo, d_est), ", ", .fc(hi, d_est), ")"))
Blocks/20_mediation/01block_mediation_prognosis.R:108:  .d_est <- as.integer(.pipeline_pub_digits()$est)[1L]
Blocks/20_mediation/01block_mediation_prognosis.R:109:  lbl_a  <- .path_lbl_p_below_ci(coef_a, p_a, ci_a_lo, ci_a_hi, .d_est)
Blocks/20_mediation/01block_mediation_prognosis.R:110:  lbl_b  <- .path_lbl_p_below_ci(coef_b, p_b, ci_b_lo, ci_b_hi, .d_est)
Blocks/20_mediation/01block_mediation_prognosis.R:111:  lbl_d  <- .path_lbl_p_below_ci(effect_total, p_total, ci_tot_lo, ci_tot_hi, .d_est)
Blocks/20_mediation/00mediation_common.R:79:  .path_lbl_p_below_ci <- function(est, p, lo, hi,
Blocks/20_mediation/00mediation_common.R:80:                                     d_est = as.integer(.pipeline_pub_digits()$est)[1L]) {
Blocks/20_mediation/00mediation_common.R:81:    L1 <- paste0(.fc(est, d_est), " (", .fp(p), ")")
Blocks/20_mediation/00mediation_common.R:83:      c(L1, paste0("(", .fc(lo, d_est), ", ", .fc(hi, d_est), ")"))
Blocks/20_mediation/00mediation_common.R:90:  .d_est <- as.integer(.pipeline_pub_digits()$est)[1L]
Blocks/20_mediation/00mediation_common.R:91:  lbl_a <- .path_lbl_p_below_ci(coef_a, p_a, ci_a_lo, ci_a_hi, .d_est)
Blocks/20_mediation/00mediation_common.R:92:  lbl_b <- .path_lbl_p_below_ci(coef_b, p_b, ci_b_lo, ci_b_hi, .d_est)
Blocks/20_mediation/00mediation_common.R:93:  lbl_d <- .path_lbl_p_below_ci(effect_total, p_total, ci_tot_lo, ci_tot_hi, .d_est)

## Minor findings rolled from task reviews
- test_result_review_guards.R L14-15 expects 4-digit P cells vs engine p=3 (pre-existing)
- Task1: tests must run from repo root
- Task4: .fc default d=3 still (path labels pass d_est explicitly)
