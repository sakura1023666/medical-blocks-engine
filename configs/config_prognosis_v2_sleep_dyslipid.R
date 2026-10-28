# 预后 2.0 实例配置。内容与模板一致，供 run 直接 source。
# 旧 config_survival_dual_batch.R 不在此文件修改范围内。
source(
  if (file.exists("E:/01block/01Block-new-Final/configs/templates/config_prognosis_v2_sleep_dyslipid.template.R"))
    "E:/01block/01Block-new-Final/configs/templates/config_prognosis_v2_sleep_dyslipid.template.R"
  else "/mnt/e/01block/01Block-new-Final/configs/templates/config_prognosis_v2_sleep_dyslipid.template.R",
  local = FALSE
)
