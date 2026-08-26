#!/usr/bin/env Rscript
# 补全 B13–B29 工作计划字段（日期留空），同步 Excel + 飞书

script_path <- tryCatch({
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}, error = function(e) normalizePath(getwd(), winslash = "/"))
if (basename(script_path) == "feishu" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/feishu_bitable.R"))

library(readxl)
library(openxlsx)

xlsx_path <- file.path(root, "run/feishu/副本副本block套路工作计划.xlsx")
app_token <- Sys.getenv("FEISHU_WORKPLAN_APP_TOKEN", "RBjfb2iwmamW14s4WhKcS7kwnie")
table_id  <- Sys.getenv("FEISHU_WORKPLAN_TABLE_ID", "tblenCHO3ErYIpYp")
cfg <- list(
  app_id = Sys.getenv("FEISHU_APP_ID"),
  app_secret = Sys.getenv("FEISHU_APP_SECRET"),
  app_token = app_token,
  table_id = table_id
)

fill_rows <- list(
  list(
    编号 = "B13", 工作模块 = "双数据库发病加孟德尔随机化",
    研究场景 = "双库发病风险关联 + 孟德尔随机化因果推断",
    是否已做Block = "否", 优先级 = "P1-高", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "在双库发病流程基础上对接MR分析，输出IVW/MR-Egger结果、敏感性分析与因果方向判断",
    `风险/卡点` = "工具变量筛选、人群重叠、水平多效性与方向性混淆需逐项核查"
  ),
  list(
    编号 = "B14", 工作模块 = "复杂网络（心理）",
    研究场景 = "心理量表/行为指标复杂网络构建与分析",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "输出网络拓扑指标、节点中心性、社区结构与可视化图；支持 bootstrap 稳定性检验",
    `风险/卡点` = "节点/边定义、缺失值处理与网络估计稳定性"
  ),
  list(
    编号 = "B15", 工作模块 = "CDC WONDER",
    研究场景 = "CDC WONDER 公开死亡率/发病率数据获取与趋势分析",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "完成 WONDER 数据下载、编码清洗、分层率表与趋势/地图输出",
    `风险/卡点` = "抓取/API 限制、ICD 编码口径变更与地域分层一致性"
  ),
  list(
    编号 = "B16", 工作模块 = "发病轨迹（两年）",
    研究场景 = "两年随访窗口内暴露/状态轨迹与发病结局关联",
    是否已做Block = "是", 优先级 = "P1-高", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "识别2年窗口轨迹组别，关联发病/转化结局并输出轨迹图与组间比较",
    `风险/卡点` = "随访时间点不齐、流失删失与窗口边界定义"
  ),
  list(
    编号 = "B17", 工作模块 = "单数据库短时间transformer",
    研究场景 = "单库短序列时序特征 Transformer 预测建模",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "完成序列编码、Transformer 训练评估，输出 AUC/校准曲线与可复现 config",
    `风险/卡点` = "序列长度不一、算力需求与黑箱可解释性"
  ),
  list(
    编号 = "B18", 工作模块 = "发病前后比较",
    研究场景 = "以 index date 为中心的发病前后指标/暴露变化比较",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "定义 index date 与对称窗口，输出前后配对/重复测量比较与效应量",
    `风险/卡点` = "index date 定义主观性、前后窗口长度与混杂控制"
  ),
  list(
    编号 = "B19", 工作模块 = "目标模拟临床试验",
    研究场景 = "目标试验模拟（TTE）/ 观察数据 emulate RCT",
    是否已做Block = "否", 优先级 = "P1-高", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "完成 eligibility、time-zero、treatment、outcome 方案定义并可复现主效应估计",
    `风险/卡点` = "immortal time bias、方案偏离真实试验与未测量混杂"
  ),
  list(
    编号 = "B20", 工作模块 = "因果闭环（横断面研究+纵向数据分析）",
    研究场景 = "横断面关联发现 + 纵向数据验证的因果闭环分析",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "横断面→纵向两阶段结果一致报告，含路径检验与敏感性分析",
    `风险/卡点` = "两阶段样本/测量口径不一致、时序方向难确认"
  ),
  list(
    编号 = "B21", 工作模块 = "深度学习多个时间点",
    研究场景 = "多时间点重复测量数据的深度学习预测",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "多时点特征融合模型训练完成，输出时序预测性能与变量贡献/SHAP",
    `风险/卡点` = "不规则采样、缺失时点多与过拟合风险"
  ),
  list(
    编号 = "B22", 工作模块 = "竞争风险模型",
    研究场景 = "多结局竞争事件下的生存/发病分析",
    是否已做Block = "否", 优先级 = "P1-高", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "输出累积发生率、Fine-Gray/CSH 结果与竞争风险曲线",
    `风险/卡点` = "竞争事件定义、编码口径与删失处理"
  ),
  list(
    编号 = "B23", 工作模块 = "多模态融合",
    研究场景 = "临床 + 影像/文本/检验等多模态数据融合建模",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "完成模态对齐、融合模型训练与相对单模态增量价值评估",
    `风险/卡点` = "模态缺失、样本对齐与维度灾难"
  ),
  list(
    编号 = "B24", 工作模块 = "人工智能clinical summary",
    研究场景 = "LLM 生成/评估临床病例摘要与结构化总结",
    是否已做Block = "否", 优先级 = "P3-低", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "输入脱敏病例→生成 summary，输出自动/人工评测指标与失败样例",
    `风险/卡点` = "幻觉、隐私脱敏与评测标准不统一"
  ),
  list(
    编号 = "B25", 工作模块 = "结构方程",
    研究场景 = "SEM 路径分析/潜变量结构检验",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "输出路径系数、拟合指数、中介/调节分解与路径图",
    `风险/卡点` = "模型识别、样本量不足与分布假设"
  ),
  list(
    编号 = "B26", 工作模块 = "人工智能问答对",
    研究场景 = "医学 QA 数据集构建与模型微调/评测",
    是否已做Block = "否", 优先级 = "P3-低", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "完成 QA 规范、训练/评测流程与准确率/一致性报告",
    `风险/卡点` = "数据质量、版权合规与评测偏差"
  ),
  list(
    编号 = "B27", 工作模块 = "链式中介",
    研究场景 = "多步/链式中介效应估计与分解",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "输出链式 indirect effect、Bootstrap 置信区间与路径图",
    `风险/卡点` = "步骤间共线、路径顺序假设与估计稳定性"
  ),
  list(
    编号 = "B28", 工作模块 = "因果森林轨迹",
    研究场景 = "因果森林估计 CATE，结合轨迹/亚组异质性分析",
    是否已做Block = "否", 优先级 = "P2-中", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "输出 CATE、亚组/轨迹分层效应、变量重要性与稳定性检验",
    `风险/卡点` = "混杂控制、因果森林过拟合与结果可解释性"
  ),
  list(
    编号 = "B29", 工作模块 = "复杂网络的网络温度",
    研究场景 = "复杂网络温度/动态网络稳定性指标与结局关联",
    是否已做Block = "否", 优先级 = "P3-低", 状态 = "未开始", 当前阶段 = "需求确认", 负责人 = "徐彤",
    进度 = 0,
    验收标准 = "定义并计算网络温度指标，关联暴露/结局并输出可视化与敏感性分析",
    `风险/卡点` = "指标定义文献依据、时间窗口选择与网络估计波动"
  )
)

df <- read_excel(xlsx_path, sheet = "工作计划总表", skip = 2)
df <- as.data.frame(df, stringsAsFactors = FALSE)

col_map <- c(
  "研究场景", "是否已做Block", "优先级", "状态", "当前阶段", "负责人",
  "验收标准", "风险/卡点"
)

for (row in fill_rows) {
  code <- row$编号
  idx <- which(df$编号 == code)
  if (!length(idx)) {
    cli::cli_alert_warning("Excel 未找到 {code}，跳过")
    next
  }
  for (col in col_map) {
    if (col %in% names(row)) df[idx, col] <- row[[col]]
  }
  # 日期留空
  if ("计划开始" %in% names(df)) df[idx, "计划开始"] <- NA
  if ("计划完成" %in% names(df)) df[idx, "计划完成"] <- NA
  if ("剩余天数" %in% names(df)) df[idx, "剩余天数"] <- NA
}

# 写回 Excel（仅更新 B13–B29 对应行，避免覆盖表头）
wb <- loadWorkbook(xlsx_path)
start_row <- 4L  # 第3行表头，第4行起为 B01
col_names <- names(df)
for (row in fill_rows) {
  i <- which(df$编号 == row$编号)
  if (!length(i)) next
  excel_row <- start_row + i - 1L
  for (j in seq_along(col_names)) {
    col <- col_names[j]
    val <- df[i, col, drop = TRUE]
    if (length(val) != 1L) val <- val[[1L]]
    if (length(val) == 1L && is.na(val)) val <- NA
    writeData(wb, sheet = "工作计划总表", x = val, startCol = j, startRow = excel_row)
  }
}
saveWorkbook(wb, xlsx_path, overwrite = TRUE)
cli::cli_alert_success("Excel 已更新 B13–B29")

# 同步飞书
recs <- .feishu_bitable_list_records(cfg, table_id)
rec_by_code <- stats::setNames(recs, vapply(recs, function(x) x$fields$编号, character(1L)))

ok <- 0L
for (row in fill_rows) {
  code <- row$编号
  hit <- rec_by_code[[code]]
  if (is.null(hit)) {
    cli::cli_alert_warning("飞书未找到 {code}，尝试新建")
    payload <- row[names(row) %in% c("编号", col_map)]
    tryCatch({
      feishu_bitable_create_record(cfg, payload, table_id = table_id)
      ok <- ok + 1L
    }, error = function(e) cli::cli_alert_warning("{code} 新建失败: {conditionMessage(e)}"))
    next
  }
  payload <- row[names(row) %in% c("编号", col_map)]
  names(payload) <- names(payload)
  tryCatch({
    feishu_bitable_update_record(cfg, hit$record_id, payload, table_id = table_id)
    ok <- ok + 1L
  }, error = function(e) cli::cli_alert_warning("{code} 更新失败: {conditionMessage(e)}"))
}

cli::cli_rule("完成")
cat(sprintf("飞书更新: %d / %d 条\n", ok, length(fill_rows)))
