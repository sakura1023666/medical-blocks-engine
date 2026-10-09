###############################################################################
#  config_glide_sol_seoul.R — GLIDE-SOL 首尔 100m CPU smoke（可选 GEE 域输入）
#  文献: Zonato et al. 2026 GMD (GLIDE-SOL)
#  禁止在本文件写入 GEE 密码；仅 project id + enable 开关
###############################################################################

.root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = normalizePath(getwd(), winslash = "/"))
# 结果目录：\\192.168.68.133\02block_result\09_HF\j\GLIDE_SOL_Seoul_100m
.j_out <- "/mnt/g/02block_result/09_HF/j/GLIDE_SOL_Seoul_100m"
.out <- file.path(.root, "Output/GLIDE_SOL_Seoul_100m")  # 本机可写兜底
if (dir.exists("/mnt/g/02block_result/09_HF/j")) {
  tryCatch({
    dir.create(.j_out, recursive = TRUE, showWarnings = FALSE)
    # 探测可写：真正试写文件（9p/SMB 上 file.access 常误报可写）
    .probe <- file.path(.j_out, ".write_probe")
    .writable <- FALSE
    tryCatch({
      writeLines("ok", .probe)
      unlink(.probe)
      .writable <- TRUE
    }, error = function(e) invisible(NULL))
    if (isTRUE(.writable)) .out <- .j_out
  }, error = function(e) invisible(NULL))
}
# 强制覆盖：GLIDE_SOL_OUT=E 用引擎 Output；=J 或默认优先 j
if (identical(toupper(Sys.getenv("GLIDE_SOL_OUT", "")), "E")) {
  .out <- file.path(.root, "Output/GLIDE_SOL_Seoul_100m")
}

config <- list(
  project = list(
    root = .root,
    name = "GLIDE_SOL_Seoul_100m",
    study_type = "environment_model",
    disease = "urban_heat_UTCI",
    database = "Seoul_100m",
    output_dir = .out,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = FALSE
  ),
  data = list(
    # 本套路由 Python 生成域/强迫；占位以满足 runner 约定
    rawdata_path = NULL,
    rawdata_obj = NULL,
    outcome_column = NULL,
    id_column = NULL
  ),
  glide_sol = list(
    city = "Seoul",
    res_m = 100,
    n_hours = 168L,          # 7 days
    n_stations = 0L,         # 0 = 目录 29 站全收（框须盖住全部）
    seed = 42L,
    backend = "cpu_diagnostic",
    hires_m = 10,            # Fig3: Open Buildings + ETH @ 10 m
    # ---- 诊断参数（auto 协议：统一公式、逐城自适应；勿再手调）----
    # params_mode="auto"：引擎从本城站点观测闭式解 wind_alpha_open 与 uhi_amp
    #   （风：ln(obs_Vcan/V10)~ln C 最小二乘；UHI：夜间 Ta 偏差对 (1-SVF) 回归），
    #   冠层场始终保论文满幅 alpha=1（形态在），仅站点比较用开阔桅杆口径。
    # 首尔 auto 实测（2024-08，29 站）：alpha_open≈0、uhi_amp≈0 —— ERA5 对首尔
    #   本无 Dortmund 式风/夜温冷偏差，模块自动退让；换城市自动重解。
    # "paper"=全用论文默认；"manual"=用下方手填值（仅敏感性分析用）。
    params_mode = "auto",
    wind_alpha = 1.0,        # 冠层场指数（auto 模式不改动此值）
    uhi_amp = 2.2,           # auto 模式下由夜间回归覆盖
    tmrt_a = 0.015,          # Tmrt 短波系数（跨城固定，保可比性）
    tmrt_b = 2.0,            # Tmrt 长波损失（跨城固定）
    # 29 个首尔 KMA ASOS/AWS 外包络；论文案例为 Dortmund，首尔用气象厅实站
    bbox = list(
      west = 126.78,
      south = 37.46,
      east = 127.17,
      north = 37.67
    ),
    gee = list(
      enable = TRUE,           # 授权已成功；跑域输入时需代理可达 Google
      project = ""             # 可留空；若 Initialize 要求项目再填 GCP Project ID
    )
  ),
  feishu = list(enable = FALSE)
)

pipeline <- list(
  name = "glide_sol_seoul_100m",
  blocks = c(
    "glide_domain_inputs",     # 先域：WorldCover→Fig2 四类 + GHSL/ETH 高度
    "glide_fetch_stations",    # KMA 实站表 + Open-Meteo 观测
    "glide_wind_coeff",
    "glide_city_morphology",   # 全城 2 m Overture 足迹 + 12 向 C（Fig.2/3/4 全城口径）
    "glide_meteo_forcing",
    "glide_solweig_run",
    "glide_station_extract",
    "glide_validate_metrics",
    "glide_figures_all",
    "glide_appendix_tables",
    "glide_pub_finalize"
  ),
  checkpoint = list(
    enable = TRUE,
    dir = file.path(config$project$output_dir, "checkpoints")
  )
)
