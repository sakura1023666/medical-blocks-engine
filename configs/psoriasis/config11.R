###############################################################################
#  config.R — 分析参数配置
#
#  每次做新分析，只需修改这个文件：
#    - 告诉我研究背景（疾病、Y、阳性标签）
#    - 告诉我数据路径
#    - 告诉我参数范围，我来填写具体值
#
#  参数说明见各字段注释
###############################################################################

config <- list(
  # ── 数据路径 ──────────────────────────────────────────────────────────────
  data = list(
    rawdata_path     = "Data/D04_Dabiao.RData",
    rawdata_obj      = "rt",                # RData 中的 data.frame 对象名（与 load 后一致）
    outcome_path     = NULL,
    outcome_column   = "Disease",           # 二分类结局列（与 incidence$outcome_var 一致）
    id_column        = "SEQN",              # NHANES 常用 ID；无此列请改为实际 ID 列名
    # column_mapping 后分析表可能为「ID」而 id_column 仍为「SEQN」：下列名若在插补数据中
    # 存在，则从单因素/特征选择等建模用 data 副本中整列剔除（不写回 imputation 文件）
    strip_id_columns_after_imputation = c("ID", "SEQN")
  ),


  # ── 项目信息 ──────────────────────────────────────────────────────────────
  project = list(
    name             = "Psoriasis Incidence (ALBI/RAR/SII)",
    disease          = "Psoriasis",
    database         = "Nhance",
    # database_type: "NHANES" 时启用复杂抽样加权分析；其他值（或 NULL）为普通非加权分析。
    # 识别方式：不区分大小写，含 "nhanes"/"nhance" 均视为 NHANES 加权场景。
    database_type    = "NHANES",
    # 研究类型：发病 → Logistic/OR；run_prediction.R 为发病预测流水线
    study_type       = "incidence",

    classification_mode = "binary",

    analysis_group   = "Psoriasis",
    reference_group  = "Non-Psoriasis",
      # 多分类模式（classification_mode = "multiclass" 时使用）

    #analysis_groups = c("Natural Cycle", "Hormone Replacement Therapy", "Ovulation Induction"),
    # 程序会自动对每个 analysis_group 与 reference_group 进行二分类分析
    #reference_group  = "Natural Cycle",           # 多分类阳性组列表（NULL 表示二分类）


    output_dir       = "Output_旋旋",         # 输出目录（相对项目根）
    # run_block 子目录: TRUE=step01_data_clean 形式；FALSE=仅 block 名（旧版）
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix          = "step",     # 与上项配合，如 step → step01_xxx
    # run_clean_map_impute：ctx5 之后是否跑 COX→RCS→weightcox→subgroup→mediation。
    # NULL = 仅 study_type=prognosis 时跑；incidence 默认不跑（避免多出 step07_COX）；TRUE/FALSE 强制。
    run_clean_map_survival_downstream = NULL

  ),

  # ── 第二数据库配置（双库验证模式）────────────────────────────────────────
  #
  #  enable = TRUE 时激活双库模式，两库均跑完整流程，步骤如下：
  #    1. 两库分别独立跑 data_clean → column_mapping → imputation
  #    2. 插补后对齐非人口统计学变量：若共同变量 < 8 个则报错停止
  #    3. 两库分别跑 baseline → univariate_multivariate → multicollinearity
  #    4. 共线性后对齐非人口统计学协变量：若共同协变量 < 3 个则报错停止
  #       （可在 univariate_multivariate$required_predictors 手动指定后重跑）
  #    5. 两库各自继续完整后续流程：
  #       COX → RCS → weightcox → 二次 baseline → subgroup → mediation
  #
  #  人口统计学变量（由 univariate_multivariate$demo_keywords 识别）各库独立保留，
  #  不参与跨库变量统一，保证两库都能保留自己的人口学信息。
  #
  #  注意：第二库配置由 run_clean_map_impute.R 内复制为独立 config2；若错误地原地改
  #  config$project / config$column_mapping，主库会与第二库共用同一份嵌套 list，导致
  #  output_dir、database_type 等被覆盖，出现「两库读同一份数据/同一输出目录」的假象。
  multi_db = list(
    enable         = FALSE, # TRUE = 启用双库验证模式
  # rawdata_path：相对项目根目录；run_clean_map_impute.R 会转为绝对路径。
    # 若与主库 config$data$rawdata_path 解析后指向同一文件（含符号链接），脚本会报错退出。
    rawdata_path   = "Data/D01_Dabiao_DB2.RData",    # 第二数据库原始数据路径
    unify_before_baseline = FALSE, # 若未来想恢复 baseline 前统一
    rawdata_obj    = "rt",                          # RData 中的对象名
    outcome_path   = NULL,                          # 结局单独文件路径（NULL = 同主数据）
    outcome_column = "Disease",                     # Y 所在列名（通常与第一库一致）
    id_column      = "SEQN",                  # ID 列名
    database       = "Nhance_DB2",                        # 第二数据库名称（用于文件命名）
    database_type  = "NHANES",                          # 列名映射类型（同 column_mapping$database_type）
    output_dir     = "Output_旋旋_DB2"
 # 以下为可选：仅第二库与主库不同的块参数（会与主 config 对应 list 做 modifyList 合并）
    # cox              = list(model1_covariates = c("Age", "Race"), model2_covariates = c(...)),
    # weightplot_patch = list(minprop = 0.00001),
    # weightcox_patch  = list(covariates = c("Age", "RR", ...), cutoff = 330)
  ),

  # ── NHANES 复杂抽样加权参数（仅 database_type="NHANES" 时生效）───────────────
  # block_cutoff / block_obj / block_baseline（加权版）/ block_univariate_multivariate（加权 OR）
  # / block_multicollinearity（加权 VIF）均读取此节参数。
  nhanes = list(
    # 调查权重列（个人访谈权重）；4 年数据需手动除以 2
    survey_weight    = "new_weight",       # 最终使用的权重列（已在数据清洗阶段生成）
    survey_cluster   = "SDMVPSU",          # PSU（一级抽样单元）列
    survey_strata    = "SDMVSTRA",         # 分层列
    # cutoff 块：C00_ROC 风格，基于原始指标 ROC Youden 最大点确定截断值
    cutoff_index_var = c("ALBI", "RAR", "SII"),             # 与 incidence$index_var 保持一致；NULL = 自动取 incidence$index_var
    # obj 块：C01_obj 风格，构建 svydesign 对象（含 binary / tertile / quartile 三种分组）
    # 以下列名在数据里是否存在，以数据实际为准；不存在时对应分组 svydesign 跳过
    exclude_cols     = c(
      "WTINT2YR", "WTMEC2YR", "WTINT4YR", "WTMEC4YR",
      "ID", "SEQN", "Source_File", "SDDSRVYR"
    ),
    # Age_Group 分组断点（C03 用，NULL 时从 incidence/survival 的 index_var 列自动取分位数）
    age_group_cutoffs = c(30, 45, 60),
    age_group_labels  = c("<30", "30-44", "45-59", "≥60"),

    # ── NHANES 加权 Logistic 协变量统一设置 ─────────────────────────────────
    # Model1 额外候选变量：在 logistic_model1_covariates 基础上追加（扩大 M1 搜索空间）
    logistic_m1_extra = c("Age", "Gender", "BMI", "Race", "Education",
                          "Income", "Smoking", "Hypertension", "Diabetes"),
    # TRUE：三个复合指标 NHANES 表使用统一的 Model1/Model2 协变量（联合搜索）
    unify_nhanes_covariates = TRUE
  ),

  # ── run_clean_map_impute.R 检查点（每步 ctx 自动 saveRDS，支持 --from ctx5 续跑）──
  checkpoint = list(
    enable = TRUE,           # FALSE = 不写入 checkpoints/*.rds
    dir    = "checkpoints11"   # 相对项目根；也可用绝对路径
  ),

  # ── 生存分析通用参数 ──────────────────────────────────────────────────────────
  # 发病为主分析时 survival 仍被 RCS/部分块读取；若无随访，run_prediction 可按 prediction$run_rcs 跳过 RCS
  survival = list(
    time_var   = "futime",    # 生存时间变量名
    event_var  = "fustatus",  # 事件变量名
    index_var  = "MCHC"       # 核心指标变量名
  ),

  # ── 发病分析通用参数（project$study_type = "incidence" 时使用）────────────────
  # 与 survival 并列，只写发病相关列名；亚组森林图等读此块（index 缺省时回退 logistic$index_var）
  incidence = list(
    outcome_var = "Disease",   # 二分类结局列（发病/病例）；与 project$analysis_group 对齐编码为 1
    index_var   = c("ALBI", "RAR", "SII")      # 核心连续指标，按 ctx$results$cutoff_value（或中位数）分高低组
  ),

  # ── 四分位分组表参数 ──────────────────────────────────────────────────────
  quartile = list(
    index_var = c("ALBI", "RAR", "SII")
  ),

  # ── Logistic 回归参数 ─────────────────────────────────────────────────────
  # index_var  — 复合性指标变量名（必填）
  #              Crude 模型只放这一个变量做单因素
  #              Model1/Model2 均以此变量为核心，加协变量调整
  #   示例: "NHHR" / "BMI" / "WBC_ratio"
  #
  # vif_threshold — VIF 共线性阈值（默认 4）
  #                 超过此值的变量迭代剔除，不纳入模型
  #                 被剔除变量在输出表中显示 "—"
  #
  # 人口学变量由程序自动识别（关键词匹配，不区分大小写）:
  #   age / gender / sex / race / ethnicity / education / edu /
  #   marital / marriage / income / pir / poverty /
  #   bmi / weight / height / smoke / alcohol / drink / physical / activity
  logistic = list(
    index_var     = c("ALBI", "RAR", "SII"),  # 复合性指标（必填，改为你的变量名）
    vif_threshold = 4,        # VIF 共线性阈值（建议 4，严格可用 10）
    p_threshold   = 0.05,     # Group 目标组显著性阈值
    # TRUE：除末组 OR 外，Table4「p for trend」在 Crude / Model1 / Model2 上也须 P<trend_p_threshold（过严无分位通过时可改 FALSE 或放宽 trend_p_threshold）
    require_linear_trend_significant = TRUE,
    trend_p_threshold   = NULL, # NULL 同 p_threshold；三线趋势难同时显著时可改为 0.1
    grouping_mode = "auto",   # "auto" / "manual" / "predefined"
    manual_n_groups = 2,      # grouping_mode="manual" 时生效：2/3/4
    group_var = NULL,         # grouping_mode="predefined" 时分组列名
    group_levels = NULL,      # 可选：固定分组顺序，如 c("low","mid","high")
    predefined_group_label = NULL,
    model1_covariates = character(0),  # 可选：手动指定 Model1 候选
    model2_covariates = character(0),  # 可选：手动指定 Model2 候选
    # 协变量自动搜索（使 Group 目标组 P<p_threshold）：递减全集→子集，未果且候选数>max_exhaustive 时再递增/稀疏组合
    covariate_search_strategy = "decreasing_then_increasing", # increasing | decreasing_only | decreasing_then_increasing
    covariate_max_exhaustive = 12L,   # 候选数 ≤ 此值时递减阶段枚举所有子集规模；更大则截断递减后再走递增
    covariate_decreasing_max_layers = 6L,  # 候选数 > max_exhaustive 时递减：除全集外再试 n-1… 最多几层
    covariate_max_choose_per_layer = 400L, # 单层 combn 超过此数则跳过该层（防组合爆炸）
    # 由 run_prediction 多指标统一成功时自动写入；勿在此手写 TRUE 且留空 fixed_*（会导致无调整、脚注 None）
    use_fixed_covariate_sets = FALSE,
    fixed_model1_covariates = character(0),
    fixed_model2_covariates = character(0)
  ),


  # ── 强制连续变量列表 ──────────────────────────────────────────────────────
  # 指定某些变量必须作为连续变量处理，即使其唯一值数量较少
  # 示例: c("SIRS", "Cardiovascular", "Neurologic", "Coagulation", "Hepatic", "Kidney", "Respiratory")
  force_continuous_vars = c("ALBI", "RAR", "SII"),

  # ── run_prediction.R：多指标循环 + Shiny ──────────────────────────────────
  prediction = list(
    index_vars         = c("ALBI", "RAR", "SII"),
    shiny_app_enable   = TRUE,
    run_rcs            = TRUE,
    # TRUE：亚组分析只对第一个 index_var（主指标）运行；FALSE=三个指标各出一张
    subgroup_primary_only = FALSE,
    ml_exclude_other_indices = TRUE,
    # 多指标机器学习：FALSE=多指标在 univariate/multicollinearity 前按普通协变量保留；TRUE=提前剔除
    exclude_index_vars_before_multicollinearity = FALSE,
    # feature_selection 后是否把 index_vars 从 Model1/Model2 强制移除（避免指标本身进入调整协变量）
    # FALSE：ALBI/RAR/SII 保留在 feature_selection_final，参与 ML 建模
    remove_index_vars_after_feature_selection = FALSE,
    # TRUE：单/多因素发表表（Table S2）始终包含 index_vars 各行，即使未进入 tb2/tb3 筛选
    keep_index_vars_in_regression_table = TRUE,
    # 额外强制不允许出现在 Model1/Model2 的变量（优先级最高）
    # 与 univariate_multivariate$excluded_predictors 中的实验室成分对齐（映射前后列名均列出）
    forbidden_model_predictors = c(
      "ID", "SEQN",
      "Albumin", "Bilirubin", "Total_Bilirubin",
      "platelet_count", "Platelet_Count",
      "Neutrophil_count", "Neutrophil_Count",
      "lymphocyte_count", "Lymphocytes",
      "RDW"
    ),
    # 多指标 Logistic：三指标同一套分位（写 manual）；run_prediction / run_logistic_only 在循环前写入 logistic。
    # mode=tertile|quartile|median — 三指标 Logistic **强制同一套**分位（manual_n_groups=3/4/2），run_* 在循环前写入 logistic。
    # mode=coarsest_all_crude — 取最粗一档使三指标 crude 均显著；若做不到则不覆盖（各指标走 config$logistic）。
    # mode=none / enabled=FALSE — 不统一，各指标可各自 auto 选分位。
    unified_index_logistic = list(
      enabled = TRUE,
      mode = "tertile",
      fallback_n_groups = 3L
    ),
    # 多指标 Logistic：先用 crude（目标组=最高分位组）筛掉不显著指标（不再出表）；再在保留指标上
    # 统一 manual 分位：在 try_n_groups 中选取「该分位下 crude 全体通过」的指标数最多的档，
    # 并列时按 try_n_groups 顺序优先（当前 3->2，去掉 4L 使主流程最高只选三分位，与 NHANES 加权结果对齐）。
    # 注：仅 2 组（2L）时使用 cutoff（二分时 ROC cutoff；无效则回退中位数）。
    logistic_multi_index = list(
      enabled = TRUE,
      try_n_groups = c(3L, 2L)
    ),
    # 多指标：各指标先完整跑 Logistic 选协变量，再对「最终 Model1 / Model2-only」取交集；
    # 交集为空时默认 on_empty_intersection=union_then_fixed 改为并集再固定；skip_unify 则放弃固定集。
    # 正式循环写入 logistic$fixed_*，双库默认共用主库交集（第二库仅 intersect 列名）。
    # intersect_across_databases=TRUE 时先跑第二库特征选择，再对两库各自交集取交集（更严）。
    unify_covariates_across_indices = list(
      # TRUE：各 index_vars 先各自搜索协变量，再对 Model1 / Model2-only 取交集并固定，
      #     使各指标 Table 4 脚注中 Model1/Model2 调整变量一致（默认开启）。
      enabled = TRUE,
      # 交集为空时：union_then_fixed=各指标探测结果取并集再固定；skip_unify=不固定、各指标独立搜索。
      on_empty_intersection = "union_then_fixed",
      intersect_across_databases = FALSE,
      cleanup_probe_dir = TRUE
    )
  ),


  # ── 图形与表格输出参数 ───────────────────────────────────────────────────────
  plot = list(
    font_family = "Times New Roman",  # 全部图形文字统一字体
    # PDF：WSL/Linux 下韦恩图/VennDiagram(grid) 用标准 pdf() 更不易空白；需 cairo 嵌入时可改 cairo_pdf
    pdf_device   = "pdf"             # "pdf" | "cairo_pdf"
  ),



  # ── 数据清洗参数 ──────────────────────────────────────────────────────────
  data_clean = list(
    missing_threshold = 0.4,   # 可选: 0.2 / 0.3 / 0.4
    age_filter        = NULL,
    drop_columns      = NULL  # ID列（subject_id/ID）保留至插补后再分流
  ),
  # ── 列名映射 ────────────────────────────────────────────────────────────
  # 将不同数据库的列名映射为统一的标准名称
  # 支持的数据库: MIMIC / NHANES / PUMCH / eICU / CHARLS
  column_mapping = list(
    enable = TRUE,  # 是否启用列名映射
    
    # 数据库类型（影响列名识别）
    database_type = "NHANES ", # "MIMIC" / "NHANES" / "PUMCH" / "eICU" / "CHARLS"
    # 同名指标多单位列并存时：优先 g/L 源列写入标准名，删除 g/dL 重复列（与 ALBI 公式、Table 1 一致）
    resolve_duplicate_unit_columns = TRUE,
    unit_column_prefer = list(
      Albumin = list(
        target = "Albumin",
        prefer = c(
          "Albumin_refrigerated_serum_g_L", "Albumin_g_L",
          "albumin_refrigerated_serum_g_l"
        ),
        alternate = c(
          "Albumin_refrigerated_serum_g_dL", "Albumin_g_dL",
          "Albumin_refrigerated_serum", "LBXSAL"
        ),
        gl_median_min = 15
      ),
      Globulin = list(
        target = "Globulin",
        prefer = c("Globulin_g_L", "globulin_g_l"),
        alternate = c("Globulin_g_dL"),
        gl_median_min = 15
      )
    )
  ),
  
  # ── 多重插补参数 ──────────────────────────────────────────────────────────
  imputation = list(
    method        = "cart",   # pmm / cart / rf（cart适合混合类型数据）
    m             = 5,        # 插补次数
    max_iter      = 5,        # 迭代次数
    seed          = 1234,
    run_sensitivity = FALSE,   # TRUE=运行敏感性分析循环; FALSE=仅运行一次MICE
    max_attempts  = 200,      # 敏感性分析最大尝试次数
    # MICE 仍无法推断的 NA：对人口学/吸烟/合并症等用众数填补（保留样本与权重）
    post_mice_fill = list(
      enable = TRUE,
      vars = NULL,              # NULL = default_vars + demo_keywords 列名匹配
      categorical_only = TRUE,  # 自动列表仅含 factor/character；vars 中可显式指定数值列
      default_vars = c(
        "Gender", "Race", "Education", "Marital_Status", "Income",
        "Smoking", "Alcohol_drinking", "Hypertension", "Diabetes",
        "Antihypertensive_medication", "Lipid_lowering_medication",
        "Glucose_lowering_medication"
      )
    )
  ),


   # ── 单因素和多因素分析参数 ────────────────────────────────────────
  univariate_multivariate = list(
    p_threshold   = 0.05,   # 显著性阈值
    tb2_threshold = 100,    # tb2变量数阈值（超过此值使用多因素显著变量）
    
    # step05 起始排除：不参与单/多因素、不进 tb2/tb3 候选、不进特征选择（见 pipeline_never_predictor_names）
    # 下列实验室指标映射前后列名均列出，以免列名未映射时仍进入模型
    excluded_predictors = c(
      "ID", "SEQN",
      "Weight", "Height", "weight", "height",
      "Waist_circumstance", "Waist", "Waist_circumference", "waist",
      "Micu_Code", "SIRS", "OASIS", "SOFA",
      "Albumin", "Bilirubin", "Total_Bilirubin",
      "platelet_count", "Platelet_Count",
      "Neutrophil_count", "Neutrophil_Count",
      "lymphocyte_count", "Lymphocytes",
      "RDW"
    ),

    # 必须纳入后续模型协变量（无论单因素/多因素是否显著、是否在 tb2/tb1 中）
    # 在确定 tb3 后强制并入；若变量名含人口学关键词，也会进入 Model1Factors
    # 注意：若某变量同时在 excluded_predictors 中，则不会参与单/多因素拟合，但仍会写入 Model2Factors 供下游使用
    required_predictors = character(0),##c("Age", "Gender")

    demo_keywords = c("Age", "Gender", "Sex", "Race", "ethnicity",
                       "Education", "edu", "Marital_Status", "marriage",
                       "income","Income", "pir", "poverty","Smoking",
                       "BMI", "bmi", "Alcohol",
                       "Smoke", "Alcohol_drinking", "Language"),  # 人口学（不含 Weight/Height/腰围，已排除）

    # 核心指标 index 在进入本步单/多因素回归前的尺度变换（缓解数值过大/过小、收敛问题）
    #   "none"   — 不变
    #   "log"    — log(x)，要求 x>0（含 0 或负数会报错并提示改用 log1p）
    #   "log1p"  — log(1+x)，适合含 0 的非负指标
    #   "scale"  — Z 分数 (x - mean) / sd（仅用非缺失值估计 mean/sd）
    # 注：本块核心指标来源固定为 survival$index_var（prognosis）或 logistic$index_var（incidence）
    index_transform = "none",
    # 回归范围：决定是否进行多因素分析，以及 tb3/Model2Factors 的来源
    #   "multivariate" — 单因素 + 多因素（默认）；tb3 优先取多因素显著变量 tb1，tb1 为空时降级用 tb2
    #   "univariate"   — 仅单因素；tb3 直接取单因素显著变量 tb2；发表表无 Multivariable 列
    regression_scope = "univariate"
  ),

  # ── 多重共线性检验参数 ────────────────────────────────────────────────────
  multicollinearity = list(
    vif_threshold_strict = 4,    # Model2 筛选、Table S3、NHANES 加权 VIF 发表表：均 VIF < 4
    vif_threshold_loose  = 10,   # 宽松 VIF（保留变量数 < min_vars_threshold 时放宽）
    min_vars_threshold   = 10,   # 最小变量数阈值
    # Weight/Height/腰围 已在 exclude_vars 中剔除；VIF 块仅对 BMI 做人体测量协调
    anthropometric_vif_resolution = list(
      enable = TRUE,
      vars = c("BMI"),
      prefer_drop_one_order = c("Weight", "Height")
    ),
    # 仅并入 VIF 设计矩阵（须存在于 imputed/cleaned）；不写回 Model2，除非 append=TRUE
    vif_design_extra_predictors = c("Study_site", "Batch"),
    vif_append_extra_to_model2_outputs = FALSE,
    # 无论上游如何传入，这些变量始终从 Model1/Model2 及 VIF 候选中强制剔除
    # （与 excluded_predictors 中实验室成分一致，供 pipeline_never_predictor_names 合并进特征选择排除）
    exclude_vars = c(
      "ID", "SEQN",
      "Weight", "Height", "weight", "height",
      "Waist_circumstance", "Waist", "Waist_circumference", "waist",
      "Albumin", "Bilirubin", "Total_Bilirubin",
      "platelet_count", "Platelet_Count",
      "Neutrophil_count", "Neutrophil_Count",
      "lymphocyte_count", "Lymphocytes",
      "RDW"
    ),
    # 加权 VIF 路径额外的技术性排除列（与 C05 drop_always 一致，不应参与 VIF 建模）
    weighted_vif_drop_vars = c(
      "Weight", "Height", "weight", "height",
      "Waist_circumstance", "Waist", "Waist_circumference", "waist",
      "Age_Group", "HCT", "RBC",
      "Mean_cell_hemoglobin", "Mean_Cell_Hgb_Conc", "Total_Protein"
    )
  ),

  # ── 基线表参数 ────────────────────────────────────────────────────────────
  baseline = list(
    p_threshold   = 0.05,   # 显著性阈值（用于提取显著变量）
    subgroup_vars = c("Gender", "Age", "Hypertension", "Diabetes"),
                            # 亚组分析使用的分层变量

    # Table 1 行变量筛选（在排除结局/ID/分层列之后生效）
    # include_vars — 非空时：只保留列表中出现且仍在数据中的变量，顺序与列表一致；与 exclude 同时配时先排除再按 include 取交集
    # exclude_vars — 从候选列中强制剔除（如不想出现在基线表的列名）
    include_vars  = NULL,     # 例: c("Age", "Gender", "MCHC")；NULL 或 character(0) = 不限制，用全部候选列
    # Source_File / SDDSRVYR：常含 2005-2006 等周期标签，发表表不展示；设计权重列亦排除
    exclude_vars  = c(
      "ID", "SEQN",
      "Source_File", "SDDSRVYR",
      "WTINT2YR", "WTMEC2YR", "WTINT4YR", "WTMEC4YR",
      "SDMVPSU", "SDMVSTRA",
      "new_weight", "new_Weight"
    ),

    # Table 1 / NHANES 加权 Table 1 / Table S9：首列变量展示名 + 单位（按数据列名匹配，不区分大小写）
    # 未列出的变量仍用 gtsummary 默认标签；可按实际列名增删改
    table1_label_overrides = list(
      Age = "Age (years)",
      Gender = "Gender",
      Race = "Race",
      Education = "Education",
      Marital_Status = "Marital status",
      Income = "Annual household income",
      Language = "Language",
      Smoking = "Smoking status",
      Smoke = "Smoking status",
      Alcohol_drinking = "Alcohol use",
      Alcohol = "Alcohol use",
      Weight = "Weight (kg)",
      weight = "Weight (kg)",
      Height = "Height (cm)",
      height = "Height (cm)",
      BMI = "BMI (kg/m\u00b2)",
      Waist_circumstance = "Waist circumference (cm)",
      HR = "Heart rate (beats/min)",
      RR = "Respiratory rate (breaths/min)",
      SpO2 = "SpO2 (%)",
      Temperature = "Temperature (\u00b0C)",
      NBPS = "Systolic BP (mmHg)",
      NBPD = "Diastolic BP (mmHg)",
      NBPM = "Mean arterial BP (mmHg)",
      ABPS = "Arterial systolic BP (mmHg)",
      ABPD = "Arterial diastolic BP (mmHg)",
      ABPM = "Arterial mean BP (mmHg)",
      Alanine_aminotransferase = "ALT (U/L)",
      Alanine_aminotransferase_ALT = "ALT (U/L)",
      LBXSATSI = "ALT (U/L)",
      AST = "AST (U/L)",
      WBC = "WBC (10^9/L)",
      RBC = "RBC (10^12/L)",
      Hemoglobin = "Hemoglobin (g/dL)",
      Hematocrit = "Hematocrit (%)",
      Platelet_Count = "Platelet count (10^9/L)",
      Creatinine = "Serum creatinine (mg/dL)",
      Glucose = "Glucose (mg/dL)",
      # NHANES 原始列多为「列名带单位」；下列标签与 Table 1 中位数一致（非 g/dL 误标）
      # Albumin/Globulin：g/L（43+28≈71 g/L ≈ Total protein 7.2 g/dL×10）
      Albumin = "Albumin (g/L)",
      Globulin = "Globulin (g/L)",
      Total_Protein = "Total protein (g/dL)",
      Creatinine_refrigerated_serum = "Serum creatinine (mg/dL)",
      Aspartate_aminotransferase_AST = "AST (U/L)",
      Lactate_Dehydrogenase_LDH = "LDH (U/L)",
      Total_Calcium = "Total calcium (mg/dL)",
      Bilirubin = "Total bilirubin (mg/dL)",
      Sodium = "Sodium (mmol/L)",
      Potassium = "Potassium (mmol/L)",
      Chloride = "Chloride (mmol/L)",
      Lymphocytes = "Lymphocytes (10^9/L)",
      Mononuclear_cell_count = "Mononuclear cells (10^9/L)",
      Monocyte = "Monocytes (10^9/L)",
      Neutrophil_Count = "Neutrophils (10^9/L)",
      Percentage_of_neutrophils = "Neutrophils (%)",
      MCH = "MCH (pg)",
      MCHC = "MCHC (g/dL)",
      MCV = "MCV (fL)",
      SBP = "Systolic BP (mmHg)",
      DBP = "Diastolic BP (mmHg)",
      PP = "Pulse pressure (mmHg)",
      Total_Cholesterol = "Total cholesterol (mg/dL)",
      HDL = "HDL cholesterol (mg/dL)",
      LDL = "LDL cholesterol (mg/dL)",
      Triglycerides = "Triglycerides (mg/dL)",
      BUN = "BUN (mg/dL)",
      eGFR = "eGFR (mL/min/1.73 m\u00b2)",
      Uric_Acid = "Uric acid (mg/dL)",
      CRP = "CRP (mg/L)",
      HSCRP = "High-sensitivity CRP (mg/L)",
      ALBI = "ALBI (composite index)",
      RAR = "RAR (composite index)",
      SII = "SII (composite index)",
      Micu_Code = "Insurance status",
      Hypertension = "Hypertension",
      Diabetes = "Diabetes",
      T2DM = "Type 2 diabetes",
      Age_Group = "Age group"
    ),

    # 供 weightcox 块写入 imputed_for_index_cut_baseline.RData 时用（第一步 baseline 不用）
    index_cut = list(
      level_low   = "Lower",
      level_high  = "Higher",
      strata_var  = NULL       # NULL → 列名为 paste0(survival$index_var, "_index_cut")
    )
  ),


  # ── 训练/验证集拆分 ───────────────────────────────────────────────────────
  splitting = list(
    train_ratio = 0.7,   # 训练集比例（0.6 / 0.7 / 0.8）
    seed        = 42,    # 随机种子
    stratify    = TRUE   # 是否按 Y 分层抽样（推荐 TRUE）
  ),

  # ── 特征选择（block_feature_selection）────────────────────────────────────
  # 输入: ctx$results$univar_features（须先跑 univariate_multivariate）；训练子集来自 splitting。
  #
  # 可选模型 methods（全小写，可任意组合；与 auto_methods 配合）:
  #   "lasso"          — glmnet：在 cv.glmnet 的 lambda.min 上乘 lasso_lambda_mult_* 网格，使非零系数个数接近 target 区间
  #   "boruta"         — Boruta + TentativeRoughFix
  #   "bayesian"       — caret::rfe + nbFuncs（朴素贝叶斯 RFE，需 klaR）
  #   "random_forest"  — caret::rfe + rfFuncs（需 randomForest）
  #   "bagged_trees"   — caret::rfe + treebagFuncs（需 ipred）
  #   "lvq"            — caret::train(method="lvq") + varImp 阈值 / Top-N
  #
  # auto_methods = TRUE 且 methods 为空时：按样本量 n、候选特征数 p 自动勾选若干模型（见块内规则）。
  # auto_methods = FALSE 时：必须显式给出 methods 向量（自行选择要跑的模型）。
  #
  # study_type 由 config$project$study_type 决定（与单多因素等块一致）：
  #   prognosis — LASSO 默认 Cox（lasso_use_cox=TRUE 且数据含 survival$time_var/event_var）；
  #   incidence — 结局列用 incidence$outcome_var（缺省回退 data$outcome_column），LASSO 与其它模型均为二分类。
  # 共识 + 最终特征数区间见 target_n_features_min / max（当前设为 8–50）。
  feature_selection = list(
    # 候选特征来源：model2_after_vif = VIF 后 Model2Factors（与 Table S3 一致；Table S2 仍为单因素表，不必一致）
    # intersect = 单因素显著 ∩ VIF 后 Model2；univar_only = 仅单因素 tb2
    # BMI/Weight/Height：仅在本块候选与最终特征中最多保留 1 个（单因素/VIF 块可三者并存）
    anthropometric_single = list(
      enable = TRUE,
      vars = c("BMI", "Weight", "Height"),
      max_coexistent = 1L,
      prefer_keep_one_order = c("BMI", "Weight", "Height")
    ),
    candidate_source      = "model2_after_vif",
    # FALSE：禁止从票选池补足（保证韦恩图中心与 D08 final 一致）；仅可截断至 max
    enforce_final_feature_count = FALSE,
    # VIF<4 多模型特征选择完成后，若最终特征仍 < target_n_features_min，回退单因素显著（tb2）
    fallback_univar_if_no_consensus = TRUE,
    # 交集未含 ALBI/RAR/SII 时仍强制并入 final（与韦恩图中心一致，见 force_composite_features）
    force_composite_features = TRUE,
    require_min_composites_in_auto = FALSE,
    enable                = TRUE,
    auto_methods          = TRUE,
    methods               = NULL,
    target_n_features_min = 8L,
    target_n_features_max = 50L,
    seed                  = 1234,
    cv_folds              = 10L,
    glmnet_maxit          = 20000L,
    lasso_use_cox         = FALSE,
    # LASSO lambda 路径标定目标个数：候选数 × frac 再 ceiling（例：16 候选 → 13）；非 target_n_features_max×0.75
    lasso_auto_calibrate_frac = 13 / 16,
    lasso_auto_calibrate_target_n = NULL,
    lasso_lambda_mult_min = 0,
    lasso_lambda_mult_max = 2,
    lasso_lambda_mult_n   = 60L,
    lasso_lambda_mult_grid = NULL,
    boruta_max_runs       = 100L,
    rfe_cv_number         = 10L,
    rfe_sizes             = NULL,
    # rfe_tolerance：容差百分比（%），caret::pickSizeTolerance 用。
    # 选在最优准确率 rfe_tolerance% 范围内、变量数最少的子集，避免最优点落在最末。
    # 默认 2（即准确率损失 ≤2% 时优先选变量数更少的子集）。设为 0 退回 pickSizeBest 行为。
    rfe_tolerance         = 2,
    lvq_importance_threshold = 0.53,
    lvq_top_n_fallback    = 20L,
    venn_width            = 10,
    venn_height           = 7,
    # NULL：在「交互式 R 控制台」运行时询问选哪些方法参与最终交集；Rscript/批跑不询问（请设 final_methods）。
    # TRUE/FALSE：强制开/关询问。
    prompt_final_methods  = NULL,
    # Figure S2B（LASSO 模型路径）：默认 base 图形（PDF 最稳）；改 "complexheatmap" 可接近 C03 双 Heatmap 版式。
    lasso_fig3a_engine    = "base",
    # NULL：最终方法>3 时自动取前 3 个画三元韦恩；也可例如 c("lasso","boruta","random_forest")
    overlap_plot_methods  = NULL,
    # 将共识特征写入 RDS/TXT，供 block_ml_models 或其它会话 readRDS 使用（见 R/utils.R）
    persist_final_artifacts = TRUE,
    persist_to_checkpoints  = TRUE,
    # 本块额外从候选特征剔除的列（与 univariate_multivariate$excluded_predictors 等合并）
    exclude_vars = character(0),
    # 复合指标：与 prediction$index_vars 一致，供 auto_final_methods 计数与并集补入
    composite_features     = c("ALBI", "RAR", "SII"),
    min_composite_features = 3L
  ),



  # ── 亚组分析参数（block_subgroup）──────────────────────────────────────────
  # required_subgroup_vars — 必须纳入亚组分析的变量（须在数据中存在且为因子/字符；若 min_n 过滤后仍无法保留会报错退出）
  # forbid_subgroup_vars   — 禁止纳入亚组的变量（自动识别到的分类列里也会强制剔除）
  # min_n / age_cutoff     — 子集最小样本量、Age_Group 年龄切点
  #
  # 注: 程序仍会始终排除 {index_var}_index_cut（与 exposure 高/低共线）
  # forest_xlim / forest_ticks_at / forest_arrow_length — 预后(HR)与发病(OR)森林图共用
  # glm_family — 发病亚组 TableSubgroupMultiGLM 的 family（发病结局列名见 config$incidence$outcome_var）
  #
  # 连续变量亚组（可选）:
  #   continuous_subgroup_only   — TRUE 时亚组只使用下列二分后的连续变量 +（可选）Age_Group/BMI
  #   continuous_subgroup_vars   — 要做中位数/阈值二分的连续列名，如 c("WBC", "Creatinine")
  #   continuous_subgroup_cutoffs— 命名列表指定截断，未列出的变量用样本中位数；例 list(WBC = 10, Creatinine = 1.2)
  #   continuous_subgroup_suffix — 新列名后缀，默认 "_subg"，即 WBC → WBC_subg
  #   continuous_subgroup_keep_age_bmi — continuous_subgroup_only=TRUE 时是否仍保留 Age_Group、BMI 亚组（默认 TRUE）
  subgroup = list(
    required_subgroup_vars            = character(0),
    forbid_subgroup_vars              = c("ID", "SEQN"),
    exclude_vars                      = c("ID", "SEQN"),
    min_n                             = 0.02,  # 若 0<min_n<1，按样本占比解释（2%）
    age_cutoff                        = 65,
    forest_xlim                       = c(0.2, 6),
    forest_ticks_at                   = c(0.5, 1, 2, 4, 6),
    forest_arrow_length               = NULL,
    glm_family                        = "binomial",
    continuous_subgroup_only          = FALSE,
    continuous_subgroup_vars          = character(0),
    continuous_subgroup_cutoffs       = list(),
    continuous_subgroup_suffix        = "_subg",
    continuous_subgroup_keep_age_bmi  = TRUE
  ),



  # ── 相关性分析参数 ────────────────────────────────────────────────────────
  correlation = list(
    high_cor_threshold = 0.8,  # 高相关阈值，超过此值记录到报告（0.7 / 0.8 / 0.9）
    # 不参与相关性分析的变量（大小写不敏感）
    # 特殊占位符 "Index" 会自动替换为 config$survival$index_var（或 logistic$index_var）
    exclude_vars = c(
      "ID", "SEQN",
      "futime", "fustatus", "Age", "Gender", "Race", "Language", "Marital_Status","Weight","Height","BMI","Smoke","Alcohol",
      "Micu_Code", "Insurance", "Hypertension", "Heart_Failure", "Myocardial_Infarction",
      "Malignant_Tumor", "T1DM", "T2DM", "CKD", "Acute_Renal_Failure", "Cirrhosis",
      "Hepatitis", "Tuberculosis", "Pneumonia", "Hyperlipidemia", "COPD", "SOFA",
      "APSIII", "SIRS", "SAPSII", "OASIS", "GCS", "CHARLSON", "Ventilation", "Index"
    )
  ),

  # ── RCS 参数 ──────────────────────────────────────────────────────────────
  # vars      — 要做 RCS 的连续变量列表（NULL = 自动取所有数值变量）
  #             示例: c("Age", "BMI", "NHHR")
  # nk_range  — 节点候选范围，程序用 AIC 自动选最优节点数
  #             可选: 3:5 / 3:6 / c(3,4,5)
  # ref_point — 参考值（NULL = 自动取中位数）
  #             示例: NULL / 25 / 60
  # p_nonlinear_threshold — 非线性 P 值警告阈值（默认 0.05）
  rcs = list(
    vars                    = c("MCHC"),   # 指定变量，NULL = 自动
    nk_range                = 3:5,    # 节点候选范围
    ref_point               = NULL,   # 参考值，NULL = 中位数
    p_nonlinear_threshold   = 0.05
  ),



  # ── 机器学习参数 ──────────────────────────────────────────────────────────
  ml = list(
    models         = c("Logistic", "DT", "RF", "XGBoost", "ENet", "RSVM", "KNN", "LightGBM"),
    cv_folds       = 10,   # 交叉验证折数
    tune_grid_size = 10,   # 调参网格大小
    seed           = 42
  ),

  # ── SHAP 解释图 (shap) — 须在 train_validation + ml_models 之后 ────────────
  #
  # 使用 ctx$results$ml_models 中已拟合 workflow，与训练相同的 recipe 烘焙矩阵 + shapviz。
  # ml_model="auto"：若 ml_best 为 ENet/logistic 等非树模型，TreeSHAP 改用验证集 AUC 最高的
  #   shapviz 兼容树模型（xgboost/lightgbm/rf 等，不含 catboost）；explain_linear_best 另出 ENet 系数图。
  # 发病 / 预后：仅影响输出文件名与标题中的 study 标签；SHAP 对象始终是「Group 二分类」
  #   分类器（与 ml_models 一致）。预后场景下若需解释生存结局，须另建生存模型，不在本块。
  # plots — 要绘制的子图（小写）：importance / bee / waterfall / dependence
  # combine_plots — 拼到一张总览里的子图顺序（须为 plots 的子集）；经典版式为第一行 3 格
  #   （非 dependence）、第二行 dependence（与旧 Figure 6 版式一致，dependence 多于 1 个时先拼小多格再参与下行）
  # dependence_features — 非 NULL 时：dependence 子图**仅**画这些列（烘焙后列名）；可与 dependence_features_add 合并去重
  # dependence_features_add — 主动追加：在「自动按 |SHAP| 选特征」时**优先**画这些（仍须为烘焙后列名，如 step_dummy 后的 Gender_X）；
  #   再用 n_dependence 控制**总个数**：先放入全部可用的 add，余下名额用 |SHAP| 排名补足（与 add 不重复）
  # TabPFN / TablCL_v2 无 workflow：勿设 ml_model 为 tabpfn / tablcl_v2。
  shap = list(
    enable                 = TRUE,
    ml_model               = "auto",   # "auto"=最优树模型 SHAP（非树最优时自动回退）；或显式 xgboost|rf|...
    model                  = NULL,     # 兼容旧字段：同 ml_model，ml_model 优先
    explain_on             = "train",  # "train" 或 "validation"（烘焙解释样本）
    plots                  = c("importance", "bee", "waterfall", "dependence"),
    combine                = TRUE,
    combine_plots          = c("importance", "bee", "waterfall", "dependence"),
    combine_filename       = NULL,     # NULL = Figure_SHAP_<tag>_<发病|预后>_combined.pdf
    combine_rel_heights    = c(1, 1),  # 上下两行相对高度（上行 3 格、下行 dependence）
    combine_label_size     = 10,
    combined_width         = 15,
    combined_height        = 12,
    save_individual          = TRUE,
    single_width           = 6,
    single_height          = 6,
    top_n                  = 10,
    importance_show_numbers = TRUE,
    waterfall_row_id       = 1L,       # waterfall 对应 explain_on 数据中的行号（1..n）
    dependence_features    = NULL,     # NULL = 自动（可配合 dependence_features_add）；非空 = 仅画这些 + add 去重
    dependence_features_add = NULL,    # 例: c("Age", "SOFA", "Gender_X")；须与 recipe 烘焙后列名一致
    n_dependence           = 4L,       # dependence 子图**总**个数上限：add 优先占满，剩余由 |SHAP| 自动补
    dependence_max_features = NULL,
    dependence_single_width = 6,
    dependence_single_height = 5,
    font_family            = "sans", # WSL/Linux 下避免 Times 导致 PDF 无文字；可改 NULL 用 plot 配置
    tree_pub_figure_stem   = NULL,   # NULL = Figure 6. SHAP (best tree <tag>) for <disease>.pdf
    run_nhanes_weighted    = TRUE,
    kernel_bg_n            = 50,     # fastshap 背景样本数（linear_method=fastshap 时）
    # 主模型为 ENet/Logistic（glmnet）时的解释（与 TreeSHAP 并存，不替代树模型 SHAP 回退）
    explain_linear_best    = TRUE,   # TRUE：对 ml_best 为 enet/logistic 时输出线性解释图/表
    linear_model             = "auto", # auto | enet | logistic
    linear_method            = "coefficients",  # coefficients（默认，推荐）| fastshap | auto
    linear_prefer_fastshap   = FALSE,  # linear_method=auto 时是否优先 fastshap
    linear_fastshap_nsim     = 100L,   # fastshap 模拟次数（越大越慢）
    linear_bg_n              = NULL,   # NULL = 使用 kernel_bg_n
    # 颜色统一：A/B/D 图共用同一套渐变，bar 图用 bee_color_high，保持视觉一致
    # NULL = 保持 shapviz 默认色
    bee_color_low          = "#3C5488",   # 低端色（深蓝），B 图低值 & D 图低值
    bee_color_high         = "#E64B35"    # 高端色（红橙），B 图高值 & D 图高值 & A 图 bar 色
  ),

  # ── PSM 倾向性评分匹配参数 ──────────────────────────────────────────────────
  #  treatment_var — 处理变量名
  #  covariates   — 匹配协变量
  #  method       — 匹配方法: "nearest", "optimal", "full"
  #  ratio        — 匹配比例: 1, 2, 3, 4 (1:1 到 1:4)
  #  caliper      — 卡尺宽度 (默认 0.2 SD)
  psm = list(
    treatment_var = NULL,   # 如 "Treatment", "Group"
    covariates   = NULL,   # 如 c("Age", "Gender", "BMI")
    method       = "nearest",
    ratio        = 1,      # 1:1, 1:2, 1:3, 1:4
    caliper      = 0.2
  ),



  # ── Cutoff 点图参数 (weightplot) ───────────────────────────────────────────────
  # 注: time_var/event_var/index_var 自动从 survival 配置读取
  # 注: colors 自动随机选择
  weightplot = list(
    minprop    = 0.2         # 最小比例
  ),

  # ── 分段 Cox 回归参数 (weightcox) ─────────────────────────────────────────────
  # 注: time_var/event_var/index_var 自动从 survival 配置读取
  # cutoff 优先级: 函数参数 > 本处 cutoff > ctx$results$cutoff_value(RCS) >
  #   本处 cutoff_file(存在则读首行数值) > 同次流水线 RCS 块目录下 cutoff_<index_var>.txt
  #   例: Output_guan/step07_RCS/cutoff_MCHC.txt（index 与 survival$index_var 一致）
  # 协变量优先级（见 block_weightcox）:
  #   run_block 传入的 covariates 参数 > 本处 covariates > 随机搜索成功时的抽样结果 >
  #   单因素 Cox 在全数据数值列上筛 P<0.05
  # random_covariate_search$enable=FALSE 时：若本处 covariates 非空，则固定用其做分段 Cox；为 NULL 则走显著性筛选
  weightcox = list(
    cutoff             = NULL,   # 可选，手工指定数值
    cutoff_file        = NULL,   # 可选，cutoff 文本路径（一行数字）
    min_segment_n      = 20,     # 分层后每层最少样本量
    min_segment_events = 5,      # 每层最少事件数（过少则 Cox 不稳定或无法估计）
    split_within_stratum = "mean", # 每层内将连续 index 二分为 high/low 时用 mean（旧脚本）；可选 "median"
    # 非随机模式下手填分段 Cox 协变量（须为数据中存在的列名）；NULL = 不用手动列表，改由显著性筛选
    covariates         = NULL,   # 例: c("Age", "Race", "RR", "WBC")
    # 随机抽样协变量搜索（旧脚本逻辑）：从 Model2 池中抽样，直至「高 cut 层」index(high vs low) 的 P<阈值 且 HR>1
    random_covariate_search = list(
      enable                    = FALSE,       # FALSE 时可用上方 covariates 手动指定，否则显著性筛选
      max_outer_attempts        = 1000L,
      max_inner_attempts        = 1000L,
      initial_factors_n         = 1L,        # 每次内层抽样起始抽几个协变量
      pool                      = NULL,       # NULL 使用 ctx$results$Model2Factors
      high_stratum_p_max        = 0.05,
      high_stratum_min_hr       = 1,          # exp(coef) 即 HR，与旧代码 tb[3,2]>1 一致
      split_within_stratum      = "mean",     # "mean" 或 "median"：层内将连续 index 二分为 high/low
      seed                      = NULL,
      save_sampled_csv          = TRUE,       # 是否写出抽样到的协变量 CSV
      # segmented() 用的简单 Cox：Surv ~ index + 下列变量（与旧脚本 cox_formula2 一致，可为 NULL）
      segmented_extra_covariates = NULL       # 例: c("Age", "Gender")
    )
  ),

  # ── KM 生存曲线参数 ───────────────────────────────────────────────────────────
  # 注: time_var/event_var 自动从 survival 配置读取
  # 注: continuous_var 自动从 survival$index_var 获取
  # 注: cutoff 自动从 weightplot 获取
  # 注: colors 自动从 weightplot 获取
  km = list(
    xlim           = c(0, 28),   # KM 横轴范围；NULL 时 block_KM 会用数据最大值与 28 取 min
    break_time_by  = 4,          # 横轴刻度间隔（天）；对应 survminer::ggsurvplot(break.time.by)
    xlab           = "Follow up time(d)",
    ylab           = "Survival Probability"
  ),


  # ── Cox 多模型回归参数 ───────────────────────────────────────────────────────
  # 注: time_var/event_var/index_var 自动从 survival 配置读取
  # 注: model1_covariates 自动选择基线信息
  # 注: model2_covariates 自动选择 model1 + 显著特征
  # grouping_mode:
  #   "auto"        = 自动 quartile -> tertile -> median
  #   "manual"      = 固定分组数 manual_n_groups（2/3/4）
  #   "predefined"  = 数据已有分组列：设 group_var；别名 preset/external/categorical/fixed
  # group_var       = predefined 模式下暴露/分类列名（亦可在 run_block 传 group_var）
  # group_levels    = 可选，固定因子 reference 与顺序，如 c("low","mid","high")
  # predefined_group_label = 表头子标题用语，默认 "preset categories"
  cox = list(
    vif_threshold     = 4,
    grouping_mode     = "auto",  # "auto" / "manual" / "predefined"
    group_var         = NULL,    # predefined 时必填（除非 block 参数传入）
    group_levels      = NULL,    # 可选字符向量
    predefined_group_label = NULL,
    manual_n_groups   = 2,       # grouping_mode="manual" 时生效：2/3/4
    # 手动协变量：仅在 grouping_mode="manual" 且 manual_covariates_enable=TRUE 时生效
    # model1_covariates: Model1 调整变量
    # model2_covariates: Model2 新增变量（会自动去掉与 model1 重复项）
    manual_covariates_enable = FALSE,
    model1_covariates = character(0),  # 例: c("Age", "Race")
    model2_covariates = character(0),   # 例: c("RR", "Temperature", "WBC")
    # Table 2 双导出：run_prediction.R 会改为 "characteristics"（仅分层基线表）；run_survival 单独跑 COX 时默认 "association"（仅 HR 表）；需两者则 "both"
    table2_export = "association"
  ),


  # ── 生存结局中介分析参数 (mediation_pro) ─────────────────────────────────────
  # 注: time_var/event_var 自动从 survival 配置读取
  # 注: exposure 自动从 survival$index_var 获取
  # 注: covariates 同时进入 Path a / 含 M 的 Cox / Total effect Cox；勿与本次 mediators 重复
  #     （自动筛选中介时，不要把可能入选为中介的实验室指标写进 covariates）
  mediation_pro = list(
    mediators      = NULL,     # 中介变量向量，NULL = 按块内 lm 筛选自动确定
    bootstrap_iter = 100,
    covariates     = NULL,

    # ── 双库 LM 筛选（Table S5 中 Model1 / Model2 两套调整）──────────────────
    # TRUE = 仅保留「Model1 与 Model2 下均显著（且 beta>=0）」的实验室指标交集作为中介候选
    dual_library_lm_screen         = TRUE,
    lm_screen_alpha                = 0.05,
    lm_screen_require_nonneg_beta  = TRUE,
    # 交集为空时回退为旧逻辑（仅 Model2 显著集），避免无中介可跑
    fallback_single_library_model2 = TRUE,

    # ── 自动搜索 Cox/Logistic 调整协变量（在最终中介集合上）──────────────────
    # TRUE = 从 covariate_search_pool 中枚举小组合，直至某中介 path a、b、Sobel 间接 p 均 < mediation_path_alpha
    auto_covariate_search            = TRUE,
    covariate_search_pool            = NULL,   # NULL = 使用 ctx$results$Model2Factors
    covariate_search_max_size        = 5L,     # 单次调整集最多几个协变量
    covariate_search_max_combinations = 300L,  # 搜索步数上限（防组合爆炸）
    covariate_search_bootstrap_iter  = 100L,   # 搜索阶段 bootstrap 次数（略低可加速）
    mediation_path_alpha             = 0.05,

    # ── 路径图配置 ────────────────────────────────────────────────────────
    diagram_enable = TRUE,     # TRUE = 分析完成后自动绘制中介三角路径图

    # best_mediator — 指定用于绘图的中介变量名；
    #   NULL = 自动选取 Proportion Mediated 最大的那一个
    #   例: "BilirubinTotal"
    best_mediator  = NULL
  ),

  # ── 训练/验证集划分 + 基线可比表 (train_validation) ───────────────────────────
  #
  # 须在 block_ml_models 之前运行。按 train_ratio 划分，若「训练 vs 验证」基线比较存在
  #   P ≤ p_strict 的变量，则自动换种子重划，直至全部 P > p_strict 或达到 max_resplit_iter（此时 stop）。
  # 比较变量：默认与 baseline 块一致（baseline$include_vars / exclude_vars）；或设 comparison_vars。
  # 产出：ctx$data$train / test，Data/df_train*，Tables/Table_1_Baseline_characteristics_train_val_split.xlsx+.tex
  train_validation = list(
    # FALSE 时跳过本块；若仍要跑 ml_models，须自行向 ctx$data$train、ctx$data$test 赋值。
    enable             = TRUE,
    train_ratio        = 0.7,   # 训练集占比 (0,1)；验证集占比 = 1 - train_ratio
    stratify           = TRUE,  # TRUE = 按结局 Group 分层划分（与 rsample::initial_split strata 一致）
    base_seed          = NULL,  # NULL = 使用 splitting$seed 或 imputation$seed
    max_resplit_iter   = 2000L,
    p_strict           = 0.05,  # 全部组间比较 P 须严格大于该值（不可等于）
    comparison_vars    = NULL,  # NULL = 按 baseline$include_vars / 自动候选；非空时为字符向量列名
    variable_labels    = NULL,  # 可选命名向量：列名 → 表头显示名，如 c(Age = "Age, years")
    table_title        = NULL,  # NULL = 英文默认标题；可改为论文用表题
    # ── 连续变量预处理（在划分定稿之后、写入 train/test 之前；基线可比表仍基于未变换数据）──
    # enable — TRUE 时按 default_method / by_var 对数值列变换（Group 与因子列不变）。
    # default_method — 未在 by_var 中单独指定的数值列： "none" | "log" | "log1p" | "scale" | "minmax" | "sqrt"
    #   log — 自然对数，要求训练集有限值均 >0，否则自动改 log1p（见 log_use_log1p_if_nonpositive）
    #   log1p — ln(1+x)，适合含 0 的非负偏态实验室指标
    #   scale — Z 分数：(x - mean_train) / sd_train（仅用训练集估计，验证集用同一 mean/sd）
    #   minmax — 按训练集 min/max 线性缩放到 [0,1]；验证集用同一 min/max，可选 clip 到 [0,1]
    #   sqrt — sqrt(max(x,0))，轻度压缩右偏计数类
    # by_var — 命名 list：列名 → 方法字符串，优先级高于 default_method（仅列存在且可转为数值时生效）
    # 别名：standardize / zscore → scale；normalize / min_max → minmax
    continuous_preprocess = list(
      enable                      = FALSE,
      default_method              = "none",
      by_var                      = list(
        # 例: HALP = "log1p", Energy = "minmax", Protein = "minmax"
      ),
      log_use_log1p_if_nonpositive = TRUE,
      minmax_clip_validation       = TRUE
    )
  ),

  # ── 机器学习模型参数 (ml_models) ─────────────────────────────────────────────
  #
  # 发病 / 预后均可训练（结局由 config$data$outcome_column 与 project 参考组/分析组映射为 Group）。
  # 预后场景下 ROC 见 config$roc（block_ROC，须在本块之后运行）。
  # 训练/验证集须由 train_validation 块生成（ctx$data$train / test）；划分比例见 train_validation$train_ratio。
  #
  # methods — 启用的模型列表，可选：
  #   "dt"              Decision Tree                 需要: rpart, rpart.plot
  #   "rf"              Random Forest                 需要: randomForest
  #   "xgboost"         XGBoost                       需要: xgboost
  #   "enet"            Elastic Net                   需要: glmnet
  #   "rsvm"            Radial SVM                    需要: kernlab
  #   "mlp"             Multilayer Perceptron         需要: nnet, NeuralNetTools
  #   "realmlp"         RealMLP（独立标签）            当前复用 MLP 训练流程与依赖
  #   "logistic"        Logistic Regression           内置 glm
  #   "lightgbm"        LightGBM                      需要: bonsai, lightgbm
  #   "knn"             K-Nearest Neighbors           需要: kknn
  #   "adaboost"        AdaBoost                      需要: adabag（当前实现）
  #   "catboost"        CatBoost                      需要: bonsai, catboost
  #   "tabpfn"          TabPFN                        excel 模式需 openxlsx；reticulate 模式需 reticulate + Python tabpfn
  #   "tabpfnv2"        TabPFNv2（独立标签）           复用 TabPFN 导出/读入链路
  #   "realtabpfn_2_5"  RealTabPFN-2.5（独立标签）     复用 TabPFN 导出/读入链路
  #   "tablcl_v2"       TablCL_v2                     与 TabPFN 相同 Excel 版式，后缀 _tablcl_v2（openxlsx 必读）
  #
  # ROC 约定：Reference_Group（config$project$reference_group）= 阴性/对照组 = "first" level。
  #            所有 event_level="first"，sens/spec 均以 reference 为正例计算（与各 C0x 脚本一致）。
  #
  # TabPFN：tabpfn_mode
  #   "excel"     — 读 tabpfn_data_path（与 C10_TabPFN.R 一致，外部 Python 已导出）。
  #   "reticulate"— R 用 reticulate 调用 python/block_tabpfn_ml_export.py；训练/验证行与 R 本块划分完全一致。
  #               需: pip install -r python/requirements-tabpfn.txt；R 包 reticulate。
  #
  # TablCL_v2（TabICL 导出见 python/block_tabicl_ml_export.py；Windows 推荐 python/run_tabicl_export.ps1：
  #   默认从本文件 project$reference_group / analysis_group 填 Python 的 -Ref/-Ana，与 ml_models 一致。）
  #   A) 仅 Python 出 Excel 再 R：tablcl_v2_mode="excel"，填 tablcl_v2_data_path；methods 含 tablcl_v2（methods=NULL 已含全部）。
  #      若 Excel 由本仓库上述脚本生成，tablcl_v2_skip_metric_swap=TRUE（与 R 指标约定一致）。
  #   B) R 内 reticulate：tablcl_v2_mode="reticulate"，配 tablcl_v2_reticulate$python 等；可不设 tablcl_v2_data_path；
  #      Excel 默认 ctx/Models/TabICL_reticulate_export.xlsx（keep_excel_path 可改）。
  #   tablcl_v2_skip_metric_swap — FALSE 时 R 会对 sens/spec 做一次对调（兼容旧外部导出）；读本仓库 TabICL 脚本产物请用 TRUE。
  ml_models = list(
    enable           = TRUE,

    # 启用的模型（NULL = 全部）
    methods          = NULL,   # 例: c("dt","rf","xgboost","logistic")

    # Elastic Net：mixture 固定（0.5=弹性网络；仅 grid 调 penalty）
    enet_mixture     = 0.5,

    # 交叉验证折数（原 Fold_Num）
    cv_folds         = 5L,

    # 随机种子（仅用于模型调参 / CV；训练验证划分见 train_validation$base_seed）
    seed             = 42L,

    # 样本量门控（block_ml_models 内自动按训练集规模筛模型；可按项目实际覆盖）
    limits = list(
      min_total_n = 60L,          # 训练集最低总样本建议
      min_class_n = 20L,          # 每类最低样本建议
      cv_min_class_margin = 1L,   # 自动降折时的缓冲（fold <= min_class_n - margin）
      min_train_for_heavy = 150L, # 小于该值跳过 heavy 模型
      min_train_for_mlp = 80L,    # 小于该值跳过 mlp/realmlp
      max_train_for_adaboost = 1000L,
      max_train_for_tab = 5000L
    ),

    # TabPFN 模式: "excel" | "reticulate"
    tabpfn_mode        = "reticulate",  # 用 Python reticulate 调用，无需外部 Excel

    # excel 模式：外部已生成的 Excel（NULL 且 mode=excel 则跳过 tabpfn）
    tabpfn_data_path   = NULL,   # 例: "path/to/TabPFN_results.xlsx"

    # TablCL_v2：与 TabPFN 相同列结构的 Excel（工作表 eval_tablcl_v2、predtrain_tablcl_v2 等）
    # excel：须存在该文件（可先 python/run_tabicl_export.ps1 或手工导出到此路径）。
    # 若不想事先准备 Excel，可改 tablcl_v2_mode="reticulate"（需 Python + python/requirements-tabicl.txt）。
    tablcl_v2_mode             = "reticulate",  # 使用 Python reticulate 模式（Anaconda3）
    tablcl_v2_data_path        = NULL,
    tablcl_v2_skip_metric_swap = TRUE,

    # reticulate：python/block_tabicl_ml_export.py（pip install -r python/requirements-tabicl.txt）
    tablcl_v2_reticulate = list(
      python               = "C:/ProgramData/anaconda3/python.exe",
      virtualenv           = NULL,
      condaenv             = NULL,
      project_wd           = NULL,
      script_dir             = NULL,
      device                 = NULL,   # NULL = TabICL 自动；或 "cpu" / "cuda"
      kv_cache               = FALSE,
      n_estimators           = NULL,
      checkpoint_version     = NULL,
      batch_size             = NULL,
      keep_excel_path        = NULL    # NULL = Models/TabICL_reticulate_export.xlsx
    ),

    # 若 ctx$results$feature_selection_final 为空，可指定本 RDS 路径（与 block_feature_selection 写出格式一致）
    # NULL 时自动尝试 root_output_dir / project$output_dir / checkpoints/ 下的 feature_selection_final.rds
    feature_selection_rds = NULL,

    # reticulate 模式：调用 Python（见 python/block_tabpfn_ml_export.py；数据与 R 划分后的 train/val 一致）
    tabpfn_reticulate = list(
      python                      = NULL,  # NULL = 依次试 Sys.which("python") / "python3"
      virtualenv                  = NULL,  # 可选，如 "C:/venvs/tabpfn" 或 "~/.virtualenvs/tabpfn"
      condaenv                    = NULL,  # 可选，与 virtualenv 二选一
      project_wd                  = NULL,  # NULL = getwd()（流水线请从项目根运行）
      script_dir                  = NULL,  # NULL = file.path(project_wd, "python")
      device                      = "cpu", # "cpu" / "cuda" / "auto"（传给 TabPFNClassifier）
      ignore_pretraining_limits     = FALSE, # 样本或特征超限时 TRUE 可尝试继续（慎用）
      keep_excel_path             = NULL   # NULL = 写到输出目录 Models/TabPFN_reticulate_export.xlsx
    )
  ),

  # ── ROC 曲线 (ROC) — 须在 train_validation + ml_models 之后 ─────────────────
  #
  # 使用 ctx$results$ml_models 中已拟合工作流，在「与 ml_models 相同的结局 Group 定义」下
  # 对全队列有效行 predict(type="prob")，再按训练/验证子集画 ROC。
  # study_type="incidence"：真值 = 是否分析组（阳性）；prognosis：真值 = survival$event_var（0/1）。
  # ml_model="auto"：与 ml_best_model_tag 相同（验证集 roc_auc 最高且存在于 ml_models 的模型）。
  # TabPFN / TablCL_v2 无 workflow 时请勿设 ml_model 为对应名，请改指定 rf / lightgbm 等。
  roc = list(
    enable    = TRUE,
    ml_model  = "auto",              # "auto" 或 dt|rf|xgboost|enet|rsvm|mlp|logistic|lightgbm|knn|adaboost|catboost
    datasets  = c("validation", "train"),  # 子集："train"|"validation"；可增 "all"=建模队列全部有效行
    font_family = NULL               # NULL = 使用 config$plot$font_family（宜为 Times New Roman）
  ),

  # ── ML 综合表现图/表 (performance_ml) — 须在 ml_models 之后 ────────────────
  #
  # 发病：ROC/校准/DCA 真值为 Group（分析组=1）。预后：真值为 survival$event_var（0/1），
  #   与 block_ROC 一致须能将 train/test 与 imputed 对齐。
  # 依赖扩展包（roc_calibration_dca=TRUE 时）：ROCit, plotROC, PredictABEL, dcurves
  performance_ml = list(
    enable               = TRUE,
    parallel_lines       = TRUE,   # 训练/验证平行线图（yardstick 指标）
    cv_boxplot           = TRUE,   # 五折 CV 的 ROC/Sens/Spec 箱线图 + 均值±SD+CI
    summary_tables       = TRUE,   # 宽表 → export_sci_table（训练/验证各一表）
    roc_calibration_dca = TRUE,   # 多模型 ROC、校准、DCA（训练/验证）
    combined_panel       = TRUE,   # TRUE = 自动拼 2×4 总览（与 C11 一致，需 cowplot）
    combined_filename    = NULL,   # NULL = Figure 3.ML performance combined 2x4.pdf（-数据库名 由 inject 插入）
    combined_width       = 24,     # 英寸，与 C11 ggsave 宽一致
    combined_height      = 12,
    combined_label_size = 12,      # 角标 A–H 字号
    # 组合图内图例列数：1=单列沿右下角向上排（最不挡 ROC 左上角）；模型很多时可试 2
    combined_legend_guide_ncol = 1L,
    disease_label        = NULL,   # NULL = project$disease / analysis_group
    model_display_order  = NULL,   # NULL = 按已训练模型 tag 默认显示名顺序
    model_colors         = NULL,   # NULL = 内置调色板
    font_family          = NULL,
    plot_base_size       = 9,      # ROC/校准/DCA/平行线/拼图子图统一基准字号（pt）
    dca_y_max            = NULL,   # NULL = 按 net_benefit 自动上限
    cv_boxplot_width     = 12,
    cv_boxplot_height    = 12
  ),

  # ── ML 补充表 (supplementary_ml) — 须在 ml_models 之后 ───────────────────────
  #
  # methods — 启用子任务（字符向量，不区分大小写），可选关键词：
  #   "hyperparameters" / "s2" / "hpbest"  — Table S2：Data/Hpbest.RData 超参数汇总
  #   "logloss" / "s3"                     — Table S3：训练/验证 Log-Loss（Metrics）
  #   "delong" / "s4" / "s5"               — S4 训练集、S5 验证集：pROC::roc.test DeLong
  #   "nri_idi" / "s6" / "s7"              — S6 训练、S7 验证：PredictABEL::reclassification
  # delong_method — 传给 pROC::roc.test(..., method=)，常用 "delong"
  # 预后 study_type 时：Log-loss / DeLong / NRI 使用 survival$event_var 为真值（0/1），须可对齐 imputed。
  supplementary_ml = list(
    enable          = TRUE,
    methods         = c("hyperparameters", "logloss", "delong", "nri_idi"),
    delong_method   = "delong",
    logloss_epsilon = 1e-15,
    nri_cutoff      = c(0, 0.5, 1)
  ),

  # ── 轨迹分析参数（Trajectory Analysis）────────────────────────────────────
  #
  #  支持两种建模方法，由 model_type 控制（当前已实现 GBMT，JLCM 预留）：
  #    "gbmt"  — Group-Based Multi-Trajectory Model（gbmt 包）
  #    "jlcm"  — Joint Latent Class Mixed Model（lcmm::Jointlcmm，预留）
  #
  #  流程：block_trajectory_fit → block_trajectory_plot → block_trajectory_chisq
  #
  #  若已有外部拟合结果（如 Step02_1_LCMM/ 下的 D01_long_*.RData），可跳过
  #  block_trajectory_fit，直接设 long_data_dir 指向已有文件目录，plot/chisq
  #  block 会自动从磁盘加载。
  trajectory = list(

    # ── 模型类型（当前支持 "gbmt"，JLCM 预留）─────────────────────────────
    model_type    = "gbmt",

    # ── 分析指标列表 ──────────────────────────────────────────────────────
    # 每个 Index 对应一个宽格式 RData 文件（由 rawdata_path_template 指定）
    index_vars    = c("BAR"),    # 完整示例: c("SII","AFR","ANLR","BAR","CAR","HALP","LAR")

    # ── 宽格式原始数据路径模板 ────────────────────────────────────────────
    # {Index} 占位符自动替换为 index_vars 中的每个值
    rawdata_path_template = "RawData/12_{Index}.RData",
    rawdata_obj           = "index_df",  # RData 中宽格式 data.frame 的对象名
    id_column             = "subject_id",  #####宽格式中ID列名
    non_na_col            = "non_na_count",  # 存在则在转换前自动删除

    # ── 宽格式转长格式参数（pivot_longer）────────────────────────────────
    # 时间列在宽格式 data.frame 中的列位置范围（含首尾）
    time_col_start = 2,    # 第一个时间列的列号
    time_col_end   = 29,   # 最后一个时间列的列号
    time_col_sep   = "_",  # 列名分隔符，如 "BAR_1" → 取 "_" 后的 "1" 作为 Time

    # 时间周期（x 轴上限，即最大 Wave 值）
    cycle = 28,

    # ── 轨迹类别数控制 ────────────────────────────────────────────────────
    # block_trajectory_fit  将拟合并保存此范围内所有类别数的模型
    class_range     = 2:8,

    # block_trajectory_plot 仅绘制这些类别数的图（可以是 class_range 的子集）
    class_for_plot  = 2:8,

   # block_trajectory_chisq 可以自己挑要看的结果，这个是范围，可以先全部跑一遍
    class_for_test  = 2:8,

    # ── 已有轨迹 RData 的磁盘加载路径（跳过 fit block 时使用）──────────
    # NULL  = 从 ctx$data$trajectory_long 读取（即 block_trajectory_fit 的输出）
    # 非NULL = 跳过 fit，直接从该目录加载文件（{Index} 和 {D} 占位符自动替换）
    long_data_dir               = NULL,  # 示例: "Step02_1_LCMM"
    long_data_filename_template = "D01_long_{Index}_D_{D}.RData",
    long_data_obj               = "long",  # RData 中长格式对象名

    # ── 结局变量配置（block_trajectory_chisq 使用）───────────────────────
    # 结局变量来自插补后数据（ctx$data$imputed 即 D01_AfterMI_Data.RData）
    # 若流水线中已运行 block_imputation，ctx$data$imputed 会自动传入；
    # 若单独运行 chisq block，需配置 outcome_data_path 作为兜底路径
    outcome_vars      = c("AKD", "AKD2", "AKD3"),
    outcome_data_path = "Output_xxx/step03_imputation/D02_AfterMI_Data_ID.RData",  # 兜底路径，如 "Output_xxx/step03_imputation/D01_AfterMI_Data.RData"
    outcome_data_obj  = "imputed_data_with_id",  # RData 中的对象名（block_imputation 保存时用的名称）

    # ── 图形参数（block_trajectory_plot）──────────────────────────────────
    y_q         = c(0.01, 0.99),  # y 轴分位数裁剪（去除极端值）
    plot_width  = 8,
    plot_height = 4,

    # ── 暂停阈值（所有组合 p >= threshold 时 chisq block 触发暂停）────────
    p_threshold = 0.05,

    # ── GBMT 专属参数 ──────────────────────────────────────────────────────
    gbmt = list(
      poly_degree = 3,    # 多项式阶数（原代码中的 N，传给 gbmt() 的 d 参数）
      scaling     = 0     # 标准化方式：0 = 不标准化
    ),

    # ── JLCM 专属参数（model_type = "jlcm" 时生效，当前预留）────────────
    # 依赖 lcmm 包的 Jointlcmm()，联合建模纵向轨迹与生存结局
    jlcm = list(
      survival_time_var  = NULL,  # NULL 则回退 config$survival$time_var
      survival_event_var = NULL,  # NULL 则回退 config$survival$event_var
      fixed_formula      = "Value ~ Time",
      random_formula     = "~ Time",
      maxiter            = 100,
      convB              = 1e-4,
      convL              = 1e-4,
      convG              = 1e-4
    )
  )
)

# ── Shiny 动态列线图（block_shiny）────────────────────────────────────────────
# enable = TRUE 时执行 ctx14（DynNomapp 或 PredictApp）
# predictors = NULL → 自动用 step13 ml_models 的训练特征（ml_feature_names）
# ml_model_tag = NULL → 自动用最优模型的 evalresult（ml_best_model_tag, 否则 catboost）
config$shiny <- list(
  enable             = TRUE,
  app_mode           = "auto",     # auto | lrm | ml — auto: logistic→DynNom，其它→PredictApp
  predictors         = NULL,       # NULL = 自动用 ml_feature_names
  predictors_from_ml = NULL,       # NULL = 优先 ml; FALSE = 强制用 Model2Factors
  ml_model_tag       = NULL,       # NULL = 自动选最优（ml_best_model_tag）
  export_app         = TRUE,       # 导出 DynNomapp/ 或 PredictApp/
  run_interactive    = FALSE,      # 本地启动 shiny::runApp（会阻塞）
  death_type         = NULL,       # ML App 标题用结局描述；NULL = 用 analysis_group
  risk_high_pct      = 70,         # ML App：≥ 此值为 high risk
  risk_low_pct       = 30,         # ML App：< 此值为 low risk
  index_var          = NULL        # ML App 侧栏标注 index 的变量名；NULL = logistic$index_var
)
