###############################################################################
#  Template — copy to configs/config_glide_sol_seoul.R and set gee$project
###############################################################################
# See configs/config_glide_sol_seoul.R for the active study config.
# Required: earthengine authenticate (no password in files).
source(file.path(
  Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = normalizePath(getwd(), winslash = "/")),
  "configs/config_glide_sol_seoul.R"
))
