# 发表质控检查清单（C 档）

Agent 按层打勾；不适用项写 `N/A` + 一句理由。

## §0 范围（先做）

- [ ] 只枚举 `【success】*`；已统计并跳过全部 `【failed】*` 与裸名 `by_index/<INDEX>/`
- [ ] 聊天已列出「将审 success」与「failed 仅计数」
- [ ] 用户点名的指标若无 success 产物 → 跳过并记 WARN，未打开 failed 目录

## §A 结构（硬）

- [ ] 审阅根路径已确认（Windows/WSL 等价）
- [ ] 成功单元列表已列出（且仅为 success）
- [ ] `Figures/pdf|png|tiff|image_information` 存在（默认交付可仅 pdf + image_information）
- [ ] Figures 根无残留平铺 `Figure*.pdf`
- [ ] **硬门控** 交付 `Figures/pdf` 为**矢量**（`bad_pdf_raster` 空）；禁止整页 image-only「图片 PDF」。截图/Shiny 须在 `allow_raster_pdf_patterns` 白名单
- [ ] 若开启 png/tiff：每张定稿 pdf 有同 stem 的 png + tiff；tiff 体积 > 0；嵌入 DPI ≥ 600
- [ ] 每张图有对应 `image_information/*.md`
- [ ] md 含 `## 图面说明` + `## 分析上下文`；无 `## 标识` / `## 技术`
- [ ] Fig1（若有）md 含逐步 n 与排除人数
- [ ] Tables 主文/补充命名与角色一致
- [ ] 双库：同角色同 S 号（或课题约定）；无次库独有列泄漏（Gate A）
- [ ] 中介门控：未导出时无 Associations / Path diagram 残留
- [ ] 成功指标 `code/README.md` + `run.R`（发病/预后/ML dual-batch 主分析）

## §B 交叉数字

来源优先级：attrition CSV → Table xlsx/csv → `_batch_status.json` → rds 旁路元数据 → `image_information` → 图面可读标注。

- [ ] Fig1 逐步 n = attrition CSV（分库）
- [ ] Table1 总 N（或分析集）与 Fig1 终步 / status.json 一致（允许脚注说明的加权/子集）
- [ ] **硬门控** Fig1 排版目检：末主框与粉/绿分叉不重叠、文字不被截断、Exclude 不压主框、箭头完整（打开 PDF/预览；不得只靠 pdftotext）
- [ ] **硬门控** `sum(亚组表 Age Count) == analytic N`；其余分层 Count 之和同检（全分析集口径）
- [ ] **硬门控** 森林图 PDF 图面 Age/主分层 N == 亚组表 Count（须读 PDF 文本，禁止只审 collision）
- [ ] **硬门控** 交付表/图/md 无上一轮 analytic N 或旧 Age 分层 Count（legacy token）
- [ ] **硬门控** 主文图 `image_information` 无「未收获结果表」；暴露对比口径与表一致（continuous ≠ 误标 Q4 vs Q1）
- [ ] **硬门控** 主文 quartile/tertile 时 Fig3 为最高 vs 最低（全分析集）；`exposure_continuous` 须显式且图注披露
- [ ] **硬门控** NHANES ROC（Fig S*）N 与加权分析集 / Table1 一致（非插补全队列偷换分母）
- [ ] **硬门控** `summary_result/` 存在；`【success】SA_complete_case` 时其 S12/S13（或等价）已进 `summary_result/Tables`
- [ ] 切点 / Events/N / 敏感性表分母与 analytic N 同口径；旧集 → 撤出或重算
- [ ] 主效应表 OR/HR(CI) 与森林 Overall 同对比、同模型；连续亚组 OR 与 Crude/同模型连续 OR 同方向同数量级
- [ ] KM Log-rank / cutoff 与 md、源 cutoff 表一致；**分组方案 = 锁定 cascade**（见 §B4）
- [ ] RCS：**P-linear** + P-nonlinear / cutoff 与 md 一致（勿仅用 P-overall 冒充与 Table 3 线性 P 可比；见 §B4）
- [ ] 分段 Cox / Firth‡ 脚注与表内符号一致
- [ ] 双库拼图：暴露对比（最高 vs 最低）、年龄切点、N 口径一致
- [ ] ML：Table 主指标与 Fig 校准/ROC 同源（同 n、同 cutoff 规则）

## §B2 交付漏检（2026-10 LS7；分母对齐后仍必做，未勾不得 PASS）

- [ ] `pdftotext`：正文/图注中的 AUC、Youden、灵敏度出现在被引用的那张 PDF 上（不挂错图号）
- [ ] Youden/灵敏度/特异度有 rds 或 summary 来源；没有则正文不写
- [ ] 横断面图轴/标题不是 Incidence（应为 Prevalence），除非设计确是发病随访
- [ ] 多面板 RCS：主叙述模型 = 图上非线性显著的那块面板；其余标稳健性
- [ ] 森林图：CI 与 P 口径已注明；交互 P 未估出的分层正文不提
- [ ] Table 1：加权百分比若配未加权检验，脚注已声明
- [ ] 中介 Total effect CI 未与主表模型 CI 互串
- [ ] 结局判定式可由数据列复述（含无法解释的残余人数）
- [ ] 引用图均有 pdf；image_information 无幽灵 stem；无裸 `.tif`
- [ ] 全部发表 xlsx `pub_xlsx_verify`：readable 且 corrupt_cells=0
- [ ] 项目说明人数与图面人数不一致时，已标明以哪份为准；未画进流程图的排除步骤已写入 Methods

## §B3 NHANES / 发病交付漏检（2026-10 银屑病 eGDR + 2026-11 cute_ran HHR；未勾不得 PASS）

规则全文：`.cursor/rules/pub_nhanes_incidence_p0_gate.mdc`。无 NHANES / 无加权发病时可整节 `N/A`。

- [ ] **硬门控** 根 `Table 2` Model2 脚注协变量 = `step*_logistic_*` 源表脚注 = 中介/RCS/S8/S10 脚注（同名同集）；禁止根表「删 Diabetes」等只改脚注
- [ ] **硬门控** 根 Table2 Model2 主对比 OR(CI) **字符串** = 同调整集的 step 源表（不一致 → 回写或重导）
- [ ] **硬门控** 主文/Table1/Table2 分位 = **调查加权**；S1/不加权基线/不加权 GLM 若另一套中位数或切点 → 脚注写 unweighted 且不可与 Table2 互换
- [ ] **硬门控** 中介 Total effect 与 Table2 最高分位 OR：同调整集已声明；数值不同须脚注「不必逐字相同」，禁止正文硬拗一致
- [ ] **硬门控** 中介路径图数字 = 中介表对应行；实现口径写 `svyglm`/PSU bootstrap（B、seed），勿假写未用的包
- [ ] **硬门控** Methods 含：暴露公式+定名、MICE(m/method/seed/**结局是否入预测矩阵**/complete)、权重**具体公式**（禁只写 cycle scaling；**禁** `WTMEC (or WTSAF)` 二义句与 Fig1 互斥）、Fig1 起点↔定义池桥接、RCS knots/竖线语义、终模路径（S3–S7）；S5 暴露效应消失须点名不藏
- [ ] **硬门控** 连续暴露 OR 尺度写实（per 1 unit / per SD / per IQR）；中介 Total continuous ≠ Table2 continuous 须脚注（complete#1 vs Rubin / 规格差）
- [ ] **硬门控** Path a 与实验室关联表标度差已脚注（如 path a=原生单位、S8=per 1-SD）；Fig 中介引用表号 = 实体 S 号（无重号副本）
- [ ] **硬门控** 无内容全等的 Table2≡Table3（或其它重复主表）；无 S7/S8 associations 或 S8/S9 mediation **错号双份**；横断面脚注无 `Cox/`、`KM/`；不加权敏感性脚注无 `survey-weighted svyglm`
- [ ] **硬门控** Model2 若含中介候选实验室 → Limitations/脚注方案 A 或 B；S5 空 OR → `NA (VIF-removed)`/删行
- [ ] **硬门控** 问卷结局写 MCQ 变量名链；自造复合指标无 “previously described” 伪引用；ROC 写协变量集+CI 方法+in-sample
- [ ] **硬门控** `Methods_software_versions.txt` 含实际用到的 `survey`（及 forestploter 若有森林图）；无 survival/survminer/cmprsk/glmnet 等未用包冒充
- [ ] **硬门控** H1/Methods P0 勾清后，现行 Methods 文件仍含上述关键句（防重传短稿冲掉仍报 PASS）
- [ ] **硬门控** ROC/`image_information` **无**「惩罚/GBM 训练 AUC 抬高、CV 掉下去所以图上不用」类自曝句；只报图面 AUC
- [ ] **硬门控** 亚组图面 NE ↔ fig md NE；禁止 md 残留 `0.00`+假小 CI；NE 须有图注/脚注事实句
- [ ] 描述脚注若写 mean (SE) or median / weighted count，表内须真有 mean 且分类 n 为加权计数；否则 **P0** 改单口径（weighted median (IQR)；unweighted counts with weighted percentages）——禁止清单有勾却放过
- [ ] **硬门控** 不加权敏感性 S10/S11 N = 分析集（权重剔除后）；禁止残留剔除前池（如 9,272 vs 8,732）
- [ ] **硬门控** Table1 / S10 无 `cycle`、`new_Weight` / WT* / SDMV*（不加权敏感性变量集=加权 Table1）；见 `baseline_no_survey_meta_vars`
- [ ] **硬门控** 亚组森林 CI 与 P 同源（z-CI↔z-P；禁 t-P 配 ±1.96·SE）；图 md/Methods 写明 Crude 或调整集
- [ ] **硬门控** RCS 竖线/结点若未加权，Methods+图 md 须写实；禁止与 Table1 加权中位静默混用
- [ ] **硬门控** 横断面现患：Methods/versions 禁 incidence/发病/新发；写 prevalence/cross-sectional
- [ ] **硬门控** MICE：可不插补结局值，但「结局未进预测矩阵」须 Limitations 披露衰减风险（勿与「不插补结局」混为一谈）
- [ ] 表题「with \<Disease\>」等与表内容（全队列 vs 病例）一致；复合指标成分不在 Table1 时 Methods 有剔除/硬删说明

冲突记录格式：`左侧来源 | 数值 | 右侧来源 | 数值 | 差分说明`

> 踩坑：VitalDB AKI Sodium 2026-10 — Table3/Fig3 仍 N=6037 而 Fig1=3522；规则见 `.cursor/rules/pub_qc_denominator_crosscheck.mdc`。  
> 踩坑：Psoriasis eGDR 2026-10 — Table2 无 Diabetes OR=0.528 vs 引擎含 Diabetes 0.487≈中介总效应；加权 9.39 vs 不加权 9.318；Fig3 md 抄旧伪 CI。  
> 踩坑：cute_ran HHR 2026-11 — Table3≡Table2 副本；Methods 只写 cycle scaling / 无 knots·结局入模·起点桥接；S5 NS 不披露；横断面脚注 Cox/KM；H1 已勾但重传后 Methods 变短。  
> 踩坑：COPD MCMI 2026-11 — Methods WTMEC/WTSAF 二义 vs Fig1 WTSAF；连续尺度未写；S7/S8 重号副本；M2∩中介候选未披露；S11 仍写 survey-weighted；versions 缺 survey、残留 survival。  
> 踩坑：COPD MCMI 2026-11 二轮 — Table1 脚注 mean(SE)/weighted count 与表体冲突；S10/S11=9,272；Fig3 CI×P 分裂+未标 Crude；RCS 3.19 vs 加权 3.13；versions 写 incidence；结局未进预测矩阵未入 Limitations。  
> 踩坑：COPD MCMI 2026-11 三轮 — 发病 config 挂空 `ml_batch`/`write_index_summary_results` → finalize 按 ML 删 Fig4/S1/S2；Table2 脚注残留 `KM/`；单库 A1 残留 `-NHANES`；Fig4 md 误引 Table S8。

- [ ] **硬门控** 纯发病课题 config **无**空 `ml_batch`；`summary_results` 图含应有的箱线/ROC/中介（非 ML 不得 omit）
- [ ] **硬门控** 横断面主表脚注无 `KM/` / `Cox`
- [ ] **硬门控** 单库表 A1 无 `-NHANES`/`-CHARLS`；与文件名同号
- [ ] **硬门控** 中介路径图 image_information 引用表号 = 交付中介表（通常 S9）

## §B4 预后 v2 / Cox 文献发表漏检（2026-10 Hip AKI；未勾不得 PASS）

规则全文：`.cursor/rules/prognosis_v2_pub_p0_gate.mdc`。机器半边：`R/pv2_pub_p0_gate.R` → `pv2_pub_p0_gate(summary_root, locked_scheme=…)`。无预后 Cox / 无 prognosis_v2 时可整节 `N/A`。

- [ ] **硬门控** KM（Fig3）分组 = `quantile_scheme_cascade` 锁定 scheme（binary → 仅 Low/High；禁止 Q1–Q4 残留）
- [ ] **硬门控** 亚组（Fig7）轴标 = 锁定对比（binary → `High vs Low`，勿 `Q4 vs Q1`）；层上有 `P-int`
- [ ] **硬门控** 中介路径图（Fig6）底边 = **Direct** effect，HR 字符串 ∈ Table S8；禁止 Total 冒充 Direct
- [ ] **硬门控** Table S7 path a = 暴露 → 中介，与 S8 同向（禁止 `index ~ OASIS` 反写）
- [ ] **硬门控** 中介脚注协变量 = 实际拟合集；若只用 Age+Gender 须写 Model 2 + 概念重叠理由；禁止假称 Model 3 /「与 Table 2 一致」；禁止把概念重叠写成假 VIF 共线
- [ ] **硬门控** Fig RCS 字幕含 **P-linear** + **P-nonlinear**（对齐 Table 3 线性）；禁止只报多 df **P-overall** 当与 Table 3 可比
- [ ] **硬门控** Boruta/SHAP 等展示层无临床特征下划线（`pipeline_display_label`）
- [ ] **硬门控** Methods：暴露取材时点、MICE（m + 结局/暴露是否入模）、`cox.zph` + PH 表（如 S9）、分位锁定结果
- [ ] **硬门控** Fig1 首框 N 与项目信息排除链一致：若 ESRD/透析/姑息/ICU≥2 等已在提取层执行，Methods 须写「先诊断码+排除码+停留时长，再 Fig1」；若未执行，不得假装已排除（须重导 Fig1 或码表层解释）
- [ ] **硬门控** 疾病定义有最终 ICD 纳入/排除码表（含语义）；无表或含非目标病种残留码 → P0 / AUTHOR_INPUT
- [ ] **硬门控** 暴露不可计算占比 &gt;40% 时 Methods/Limitations 承认选择偏倚（不可计算=成分未化验）
- [ ] **硬门控** 敏感性表脚注 landmark（如 “primary X-day locked grouping”）= 主文 landmark；禁 28-day 模板残留于 14d 交付
- [ ] **硬门控** Fig7 Overall HR 字符串 = Table 3 Model1 同对比（Numbers_Master 单一出处；禁 Rubin vs complete#1 静默差 0.001）
- [ ] **硬门控** Methods 含 Boruta/SHAP 可复述参数（confirmed 规则、包/实现、ntree/seed、Model3 交集）与 RCS 结点数/位置
- [ ] **硬门控** Table S4 / Figure 5 = **连续指标 alone、unadjusted**（`R/pv2_index_roc.R`）；禁止 Cox LP / Age+GCS/Sodium 等协变量 ROC 占用 S4/Fig5
- [ ] 同一表连续 per-1-SD 与分位方向强度相悖时：已复算尺度或已用 RCS 非线性写实
- [ ] 收尾已跑 `pv2_pub_p0_gate()` 或等价 `pdftotext` 核验；失败不得 PASS

> 踩坑：Hip AKI 2026-10 — Fig3 四分位 vs 锁 binary；Fig6 Total≠S8 Direct；Fig7 无 P-int / Q4vsQ1；Fig4 仅 P-overall；Fig2 下划线；S7 反向；无 PH/取材时点/MICE 裁决。  
> 踩坑：Stroke ANLR 14d 2026-11 — Fig1 与项目信息排除链不一致；ICD 码表缺口；暴露缺失&gt;40% 未写入 Limitations；S5 脚注 28-day 残留；S5 连续 vs 分位相悖未说明；Fig7 Overall 0.256≠Table3 0.255；Boruta/SHAP/RCS knots 未入 Methods。  
> 踩坑：COPD ALBI 2026-11 — Table S4 / Fig5 写成 ALBI+Age+Sodium+GCS 的 Cox LP，参考文献要求单指标无协变量 ROC。

## §B5 发表数字格式（强制；2026-11 pneumonia DeLong；未勾不得 PASS）

规则全文：`.cursor/rules/pub_digits_consistency.mdc`。机器半边：`R/pub_qc_table_digits.R` → `pub_qc_scan_table_digits`（已挂 `pub_qc_run_after_project` Layer A2）。

- [ ] **硬门控** P / DeLong 矩阵 / 任意 P 列：无裸 `0`、`0.000`；极小值一律 `<0.001`；默认固定 3 位（`p_style=fixed`）
- [ ] **硬门控** AUC / Acc / Sens / Spec / F1 / Log-Loss / NRI / IDI：固定 3 位；\|x\|&lt;0.001 → `<0.001`；参照模型 NRI/IDI → `Ref`
- [ ] **硬门控** OR/HR/CI：固定 3 位（含尾随 0）；描述统计 `desc_trim`（整数无 `.000`）
- [ ] 超参表允许 `0.000237` 等有效数字，**不得**误改成 `<0.001`
- [ ] Fig1 PDF **无图底脚注/图注**（细则进 Methods / image_information）
- [ ] 结构 QC 报告 Layer A2 = PASS；FAIL → 当场走 `pub_normalize_pub_df` / 重导，不得 PASS

> 踩坑：肺炎 Ln_NLPR 2026-11 — DeLong S8 成片裸 `0`；NRI `0.000`；Fig1 图底 Analytic rule 脚注。

## §B6 ML / TCF 预测发表漏检（强制；2026-11 SA-AKI multi-algorithm fusion；未勾不得 PASS）

规则：`.cursor/rules/ml_tcf_pub_reuse.mdc`；nature-statistics `common-failure-modes.md` Medical Blocks 交付漏检表同步行。

- [ ] **硬门控** 结局标签全稿一致：Fig1 / 中期封面 / Table1 / TRIPOD(S13) / Methods 同一套（28-day all-cause **或** in-hospital）；禁止事件数相同却两套标签；发表面无 `fustatus` 等内部字段名
- [ ] **硬门控** 分析单位粒度：MIMIC 患者级 vs eICU（patientunitstayid / ICU-first）已在 Fig1 + Methods 写实；先实核 stay ID 是否唯一——仅当真有同患者多 stay 入样才要求 cluster-robust / Limitations，禁止假残留
- [ ] **硬门控** Fig1 各排除框 = 实核剔除原因（「结局不可链接」≠「baseline 不可链接」）；Methods 有一句话定义
- [ ] **硬门控** 数据集用途链：熵筛选 / RSCV = train；TOPSIS α = internal-validation metrics（若如此）；禁止笼统 development-set weights 掩盖泄漏面
- [ ] **硬门控** `Methods_software_versions.txt` 含 Python + sklearn/XGBoost/LightGBM/SHAP/imblearn/pandas/numpy（TCF 主链）；无未用 survival/cmprsk/mediation 等预后模板残留
- [ ] Methods 写实 `logistic_mi` 实现载体（R mice 方法映射）与 `complete_action=1` 操作层语义；分类器是否 Rubin 诚实披露
- [ ] train_ratio / Fig1 划分比例与 Table1 列头 n 一致（80/20 vs 70/30 不得混用）

> 踩坑：SA-AKI TCF ALLVARS 2026-11 — Table1/S13「In-hospital death (fustatus)」vs Fig1「death within 28 days」；Fig1 MIMIC 写成 stay 级结局不可链接、实为 subject 去重；eICU 1207=baseline 不可链接未入 Methods；软件清单无 Python；TOPSIS α 用内验却 Methods 写 development-set。



## §B7 数据库池化 / BlendedLoS 漏检（强制；2026-11 ULN-triple；未勾不得 PASS）

规则：nature-statistics `common-failure-modes.md`「Medical Blocks 数据库池化 / BlendedLoS 漏检」；Methods 引擎 `R/pub_dbpool_methods.R`。

- [ ] **硬门控** 数据溯源口径唯一：Methods / Data Availability / Fig1 md 写「harmonized extract following BlendedICU v0.3.2 protocol」(B) 或明确官方包(A)；与 seed 974 / upstream README 一致；禁混用
- [ ] **硬门控** Figure 2（及 S 训练规模图）末点 ≠ Table 3 / S4/S6/S8 MIMIC Generalization；脚注与 image_information 有「禁止对读」
- [ ] **硬门控** Table S1：MOESM1 经验界写实；N clipped=post-norm；PLT/尿量下界抬中位有母方案句；葡萄糖单位混杂披露
- [ ] **硬门控** TPC 选型句（对齐母方案）+ Table S2 描述性 equal-n；CI 覆盖写实
- [ ] Methods 含超参要点、单次 seed 跑、特征/DROP_TS、equal-n 规则；缺项标 AUTHOR_INPUT
- [ ] Table 2 AUPRC Baseline = 预测 stay 框患病率，非 Table 1 三库池化死亡率

> 踩坑：50_Cirrhosis ULN-triple 2026-11 — Methods 写 BlendedICU extract 与配方#13 自建映射冲突；Fig2 n=3547 AUROC 0.736 vs Table3 Gen 0.83；S1 “physiological” vs MOESM1 怪界；AUPRC Baseline≠Table1。


## §C 逻辑通顺（Agent）

- [ ] 暴露/结局命名在表题、图题、md 上下文一致（疾病显示名，非裸列名泄漏）
- [ ] 参照组方向正确（Q1/T1/非暴露为 Ref）
- [ ] 亚组：二分类年龄；非旧 Q1+Q4 子集冒充全人群（除非 config 显式）
- [ ] 补充表编号连续、无错位角色
- [ ] 脚注解释了权重、分母、‡、NE
- [ ] 无明显「阴性当阳性」表述残留
- [ ] P0/P1/P2 已分级（P0=阻断交稿）

## 套路专项（按需）

### 轨迹
- [ ] 类别数 ng、最小类占比与 Table2/健康 guard 脚注一致
- [ ] 潜类别 KM / dynpred 类别标签与轨迹图一致（双库若独立拟合，勿误写迁移验证）

### IPW
- [ ] 加权前后 SMD / Table1 角色齐全
- [ ] 暴露定义（如 HbA1c 阈值）与硬排除不进 PS 一致

### TST
- [ ] Table2 Day5 与 Table3 / S6 字符串级对齐；脚注含 test n 与对照分数可得 n
