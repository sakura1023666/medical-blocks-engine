###############################################################################
#  config_environment_exwas_batch.template.R
#  地基：发病（二分类 logistic）。后缀：ExWAS / 弹性网 ERS / WQS / RCS。
#  复制到课题目录后改路径。不要覆盖其他课题 config。
###############################################################################

config <- list()
config$project <- list(
  name = "environment_exwas_gastric",
  database = "NHANES",
  output_dir = "Output/environment_exwas_gastric"
)
config$exwas_gastric_assemble <- list(
  outcome_csv = "",
  raw_dir = "",
  outcome_col = "DN"
)
# ExWAS 保持不加权（文献 Methods 2.5 + 用户要求）
config$exwas_unweighted <- list(
  covariates = c("RIDAGEYR", "RIAGENDR"),
  seed_impute = 123456L,
  mice_m = 5L,
  mice_maxit = 5L
)
# ERS–结局：权重列齐全时 svyglm；弹性网拟合本身不加权（原文未写权重）
config$ers_elastic_net <- list(
  alphas = seq(0, 1, length.out = 11),
  nfolds = 5L,
  bootstrap_B = 1000L,
  seed = 2024L,
  survey_weight = "WTMEC2YR",
  survey_psu = "SDMVPSU",
  survey_strata = "SDMVSTRA"
)
config$wqs_exwas_fixed <- list(
  q = 4L,
  b = 1000L,
  validation = 0.6,
  seed = 2024L
)
# 年龄分层沿用对标文献 Figure 3 的 60 岁
config$exwas_subgroup <- list(age_cutoff = 60)
