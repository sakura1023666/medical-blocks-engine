#!/usr/bin/env Rscript
# 飞书：登记 SSD LPA×网络×平行竞争中介套路（工作计划 base）
# 用法:
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/feishu/run_feishu_mark_ssd_lpa_network_mediation.R

script_path <- tryCatch({
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}, error = function(e) normalizePath(getwd(), winslash = "/"))
if (basename(script_path) == "feishu" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))

app_token <- Sys.getenv("FEISHU_WORKPLAN_APP_TOKEN",
                        Sys.getenv("FEISHU_BITABLE_APP_TOKEN", "RBjfb2iwmamW14s4WhKcS7kwnie"))
app_id <- Sys.getenv("FEISHU_APP_ID")
app_secret <- Sys.getenv("FEISHU_APP_SECRET")
if (!nzchar(app_id) || !nzchar(app_secret)) {
  stop("请配置 .env.feishu 中 FEISHU_APP_ID / FEISHU_APP_SECRET", call. = FALSE)
}

message("Feishu base: ", app_token)
message("Routine: SSD_LPA_Network_Mediation under 63_SSD")
message("Decision tree: Decisiontree/decision_tree_ssd_lpa_network_mediation.md")
message("Config: G:/02block_result/63_SSD/LPA_Network_Mediaton_42214160/configs/config_ssd_lpa_network_mediation.R")
message("Run: run/ssd_lpa_network_mediation/run_ssd_lpa_network_mediation.R")
message("Blocks: 02/scale_score, 83/LPA, 62/CFA, 20/14 parallel mediation, 50/06 profile network, 13/DCA")
message("Literature: Ma 2026 PMID 42214160 (paper_060 adversarial PASS)")

sync <- file.path(root, "run/feishu/run_feishu_sync_batch.R")
if (file.exists(sync)) {
  message("可随后运行: Rscript run/feishu/run_feishu_sync_batch.R --result-root <G:/02block_result>")
}
message("OK: SSD LPA/network/mediation routine registered in repo; sync after first successful batch.")
