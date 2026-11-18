#!/usr/bin/env Rscript
# Deploy ShinyApp/ to shinyapps.io using gitignored .secrets/shinyapps_*.env
#
# Usage (repo root):
#   Rscript run/shiny/deploy_shinyapps_from_secrets.R \
#     --app-dir "/path/to/ShinyApp" \
#     --app-name "predictendometriosis" \
#     --secrets ".secrets/shinyapps_predictendometriosis.env"

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (!is.null(a) && length(a) && nzchar(as.character(a)[1L])) as.character(a)[1L] else b
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

app_dir <- get_arg("--app-dir")
app_name <- get_arg("--app-name", "predictendometriosis")
secrets <- get_arg("--secrets", ".secrets/shinyapps_predictendometriosis.env")
account <- get_arg("--account", "predictendometriosis")

if (is.null(app_dir) || !nzchar(app_dir) || !dir.exists(app_dir)) {
  stop("--app-dir required and must exist (folder containing app.R)")
}
if (!file.exists(file.path(app_dir, "app.R"))) {
  stop("app.R not found under: ", app_dir)
}

# resolve secrets relative to MEDICAL_BLOCKS_ROOT / cwd
.root_cands <- unique(c(
  Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
  getwd(),
  "/mnt/e/01block/01Block-new-Final",
  "E:/01block/01Block-new-Final"
))
.root_cands <- .root_cands[nzchar(.root_cands)]
secrets_path <- secrets
if (!file.exists(secrets_path)) {
  for (r in .root_cands) {
    cand <- file.path(r, secrets)
    if (file.exists(cand)) {
      secrets_path <- cand
      break
    }
  }
}
if (!file.exists(secrets_path)) stop("secrets file missing: ", secrets)

lines <- readLines(secrets_path, warn = FALSE)
kv <- list()
for (ln in lines) {
  ln <- trimws(ln)
  if (!nzchar(ln) || startsWith(ln, "#")) next
  if (!grepl("=", ln, fixed = TRUE)) next
  parts <- strsplit(ln, "=", fixed = TRUE)[[1L]]
  kv[[trimws(parts[[1L]])]] <- paste(parts[-1L], collapse = "=")
}
need <- c("SHINYAPPS_TOKEN", "SHINYAPPS_SECRET")
miss <- need[!vapply(need, function(k) nzchar(kv[[k]] %||% ""), logical(1))]
if (length(miss)) stop("secrets missing keys: ", paste(miss, collapse = ", "))

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("package rsconnect required")
}
acct <- kv$SHINYAPPS_ACCOUNT %||% account
rsconnect::setAccountInfo(
  name = acct,
  token = kv$SHINYAPPS_TOKEN,
  secret = kv$SHINYAPPS_SECRET
)

message("Deploying ", normalizePath(app_dir), " as appName=", app_name, " account=", acct)
rsconnect::deployApp(
  appDir = app_dir,
  appName = app_name,
  account = acct,
  server = kv$SHINYAPPS_SERVER %||% "shinyapps.io",
  launch.browser = FALSE,
  forceUpdate = TRUE
)
message("Done. Expected URL: https://", acct, ".shinyapps.io/", app_name, "/")
