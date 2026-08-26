###############################################################################
#  00ip_common — 发病/预后两阶段共用（72_incidence_prognosis_two_stage）
#
#  ip_admin_censor_28: 28 天行政截尾
#    futime   = min(t, 28)
#    fustatus = 1 iff 死亡且 t ≤ 28（t 缺失或 dead 非 1 → 0）
###############################################################################

ip_admin_censor_28 <- function(t_days, dead) {
  dead <- as.integer(dead)
  dead[is.na(dead)] <- 0L
  t_days <- as.numeric(t_days)
  fustatus <- as.integer(!is.na(t_days) & dead == 1L & t_days <= 28)
  futime <- pmin(t_days, 28)
  data.frame(futime = futime, fustatus = fustatus, stringsAsFactors = FALSE)
}
