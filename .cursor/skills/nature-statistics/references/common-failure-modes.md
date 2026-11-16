# Common statistical failure modes

## Contents

- [P0: likely to undermine the result](#p0-likely-to-undermine-the-result)
- [P1: important reporting or interpretation risk](#p1-important-reporting-or-interpretation-risk)
- [P2: clarity and presentation risk](#p2-clarity-and-presentation-risk)


Use this file to identify reviewer-risk patterns. Do not accuse the authors; state the risk and the fix.

## P0: likely to undermine the result

### Pseudoreplication

Signal:
- `n` is reported as cells, images, fields, spectra, droplets, reads, technical wells, or repeated readings.
- The independent experimental unit is likely animal, patient, culture, donor, batch, plot, device, or experiment.

Risk:
- The test may overstate precision and produce artificially small p values.

Fix:
- Analyse independent units, aggregate technical subsamples, or use a hierarchical / mixed-effects model when justified.
- Show subsample-level spread visually without treating every subsample as independent.

### Uncorrected multiple comparisons

Signal:
- Many genes, proteins, time points, panels, groups, pairwise contrasts, or exploratory endpoints are tested.
- The manuscript reports selected significant comparisons only.

Risk:
- False-positive rate is inflated or the comparison family is unclear.

Fix:
- Define the family of tests and use an appropriate correction or distinguish prespecified primary comparisons from exploratory analyses.

### Wrong interaction inference

Signal:
- Authors say two effects differ because one comparison is significant and the other is not.

Risk:
- Difference in significance is not evidence of a significant difference between effects.

Fix:
- Test the interaction or directly compare effect sizes.

### Analysis unit mismatch

Signal:
- Design is paired, matched, blocked, longitudinal, nested, or repeated-measures, but analysis uses independent tests.

Risk:
- Dependence structure is ignored.

Fix:
- Use paired tests, repeated-measures analysis, mixed-effects models, blocking, or cluster-robust methods as appropriate.

## P1: important reporting or interpretation risk

### Significance-only conclusion

Signal:
- Result is described mainly by stars or p thresholds.

Risk:
- Readers cannot judge magnitude, uncertainty, or practical importance.

Fix:
- Add effect estimates, confidence/credible intervals, raw distributions, and exact p values where possible.

### Small-sample overclaim

Signal:
- Very small `n`, unstable estimates, or no uncertainty interval, but strong language.

Risk:
- Effect size and direction may be imprecise.

Fix:
- Use cautious wording and report the limitation directly.

### Normality or equal-variance assumption not supportable

Signal:
- Parametric tests are used on small or skewed samples with no rationale.

Risk:
- Assumptions may be unverifiable or violated.

Fix:
- Add assumption checks, use robust/nonparametric alternatives, or describe the limitation.

### Outlier handling is unclear

Signal:
- Points disappear, exclusions are mentioned vaguely, or outlier tests are named without prespecified rules.

Risk:
- Post-hoc exclusion may bias results.

Fix:
- State exclusion criteria, timing, number removed, and whether conclusions are robust to inclusion.

### Correlation or regression overclaim

Signal:
- Association is written as mechanism, prediction, or causality without design support.

Risk:
- Confounding, non-independence, and model extrapolation may be ignored.

Fix:
- Reword as association unless experimental or causal identification supports stronger claims.

## P2: clarity and presentation risk

### Error bars are undefined

Fix:
- State s.d., s.e.m., confidence interval, interquartile range, or other convention.

### `n` varies across panels but is not panel-specific

Fix:
- Give panel-specific `n` and define what `n` represents.

### Star notation is not defined

Fix:
- Define thresholds, correction status, and exact p values if available.

### Software is missing

Fix:
- Add software/package and version if supplied by the user.

### `ns` hides the result

Fix:
- Provide exact p value or state the reporting threshold and avoid interpreting lack of significance as proof of no effect.

## Medical Blocks 交付漏检（强制；2026-10 LS7×Hp）

凡审 `02block_result` / Medical Blocks 发表根，**即使分母、亚组 N、ROC n 已对齐，也必须逐条过下面清单**。未逐条打勾不得写 PASS。窄 PASS（只核 analytic N）等于未审。

| 信号 | 级别 | 必做 |
|------|------|------|
| 项目说明人数 ≠ 图面人数（如 8,882 vs 8,822） | P1 | 以图/attrition 为底账，Methods 标明哪份是笔误 |
| 纳排有年龄门、血清学模棱带等，流程图未单独成框 | P1 | Methods 仍须单列这些步骤，不得假装图上已有 |
| 横断面图轴/标题写 Incidence | P0 | 改 Prevalence，或正文明确这是现患率 |
| 多面板 RCS：正文锚定的模型与显著非线性面板不一致 | P0 | 主叙述跟显著面板（如实报），其余作稳健性 |
| Methods/图注里的 AUC、Youden、灵敏度写在错误图号上 | P0 | `pdftotext` 核对数字落在哪张 PDF；引用改到那张图 |
| Youden/灵敏度/特异度没有任何 rds、summary 或图面来源 | P0 | 有脚本输出才写入；否则正文不写 |
| 森林图 CI 与 P 明显矛盾（如 CI 下限>1 但 p>0.05），或某分层没有交互 P 却在正文报告 | P0 | CI 与 P 必须同源临界值（z-CI 配 z-P；禁 survey t-P 配 ±1.96·SE）；交互未估出则正文不提 |
| 亚组森林未注明 Crude vs Model 2（或 adjust_covariates） | P0 | 图 md / Methods 写实调整集；OR 量级≈crude 时不得暗示已调 Model 2 |
| 不加权敏感性 S10/S11 人数=权重剔除前池（如 9,272）而非分析集（如 8,732） | P0 | 敏感性与 Fig1/Table1 分析集同分母（`pipeline_align_survey_analytic_rows`）；或脚注写明基数差 |
| RCS 竖线/结点中位与 Table1 加权中位不同源却无说明 | P0 | Methods/图注写 knots=unweighted P10/P50/P90（或实况）；禁止正文用加权 3.13 却图上 3.19 不解释 |
| MICE 结局「不插补」与「不进预测矩阵」混淆；后者未入 Limitations | P0 | 写清：可不插补结局值，但协变量插补未纳入结局作预测须 Limitations 披露衰减风险 |
| 横断面现患却 Methods/versions 写 incidence/发病/新发 | P0 | 全链 prevalence / cross-sectional；禁流行病学概念混用 |
| 加权构成比配未加权检验，脚注未声明 | P0 | 脚注写明百分比口径与检验是否 design-based |
| 中介 Total effect CI 被写成与主表同一模型 | P0 | 说明调整集不同，两值不互串 |
| 中介 Total OR 与 Table2 最高分位 OR 不同却正文/脚注硬拗「一致」 | P0 | 脚注写同调整集下规格可不同；或重导对齐；禁止无说明硬拗（Psoriasis eGDR 0.489 vs 0.528） |
| 根 Table2 Model2 脚注协变量 ≠ step 源表 / ≠ 中介脚注（如删 Diabetes 只改脚注） | P0 | 脚注与 OR 字符串与 step 源表对齐；见 `pub_nhanes_incidence_p0_gate` |
| 主文加权分位与 S1/不加权敏感性中位数混用且不披露 | P0 | 主链锁加权；另一套脚注 unweighted |
| Methods 缺公式出处 / MICE(m,seed,结局是否入模) / new_Weight+PSU | P0 | 按实补 Methods（轨道 B 可只改文） |
| Methods 权重只写 “cycle scaling”、无 `WTMEC*/C`；或无 Fig1 起点↔定义池桥接；或无 RCS knots/竖线语义 | P0 | 写实公式与桥接（cute_ran HHR 2026-11） |
| Methods 写 `WTMEC2YR (or WTSAF2YR…)` 二义句，与 Fig1/日志实际 WTSAF（或 WTMEC）互斥 | P0 | 按指标实况只写一种 `new_Weight=WTxxx/C`（COPD MCMI 2026-11） |
| 连续暴露 OR 未标明 per unit/SD/IQR；中介 Total continuous 与 Table2 continuous 差无脚注 | P0 | 写尺度 + complete#1 vs Rubin/规格差说明 |
| Path a 与实验室关联 β 标度不同却无脚注；或 Fig 中介引用错 S 号/重号双份 associations·mediation | P0 | 脚注标度；删重号副本；Fig md=实体表号 |
| Model2 含中介候选实验室却 Limitations/脚注不披露 | P0 | 方案 A 写实或方案 B 重导 |
| MICE 只写 “followed study defaults”，不写结局是否入预测矩阵 | P0 | 按脚本写实入/不入 |
| 问卷结局只写 “MCQ items” 无变量名链；自造指标伪引用 previously described | P0 | MCQ 名+规则；操作性定义+近邻文献 |
| 不加权敏感性脚注仍写 survey-weighted svyglm；横断面脚注残留 KM | P0 | 外科改脚注 |
| S5 等全协变量表 OR 真空（VIF 已剔）无 NA/脚注 | P0/P1 | `NA (VIF-removed)` 或删行 |
| ROC 缺协变量集 / CI 方法 / in-sample 说明 | P0 | Fig md + Methods 写实 |
| `Methods_software_versions.txt` 缺 survey/forestploter，或残留未用 survival/cmprsk/glmnet | P0 | 清单与本分析实体对齐 |
| 交付根 Table3 与 Table2 逐格相同（仅表题编号不同） | P0 | 删重复主表；中期连续编号与叙事对齐，勿用副本圆谎 |
| 横断面课题脚注残留 Cox/KM；或中介比例为正仍留 negative-proportion 模板句 | P0/P1 | 外科改脚注；见 `pub_nhanes_incidence_p0_gate` §6–7 |
| 发病 config 挂空 `ml_batch` / 仅 `write_index_summary_results` → finalize 删箱线/ROC/中介图 | P0 | 删空 ml_batch；清图必须传 config 且仅 ML scheme 删 S2/箱线（COPD MCMI 三轮） |
| 单库交付表 A1 残留 `-NHANES` 与文件名不一致 | P0 | `pub_sync_xlsx_a1_titles_to_filenames` |
| 中介路径图 md 引用 Table S8（实为关联表）而数字来自 S9 | P0 | md/图注表号=实体中介表号 |
| H1/Methods P0 已勾，但现行 Methods 被重传短稿冲掉仍报 PASS | P0 | 勾清前 `rg` 现行 Methods；重传后重检 |
| S5 全模型暴露 NS、缩减 Model2 显著却 Methods 不披露 | P0 | 点名 + Limitations 承认筛选 |
| ROC 或 fig md 自曝内部算法试验（训练抬高、CV 掉下去所以不用） | P0 | 只报图面 AUC；删自曝句 |
| 图面 NE，fig md 仍抄 0.00 或 1e-07 伪 CI | P0 | md/正文以图面为准；NE 事实句 |
| 脚注写 mean (SE) or median / weighted count，表内全是 median 且分类 n 相加=未加权 N | P0 | 脚注改为 weighted median (IQR) + unweighted counts with weighted percentages（零数值改动） |
| 结局只有列名、没有可从数据列复述的判定式 | P1 | 用现有列反推能解释的比例，写明无法解释的残余（如问卷列缺失） |
| 引用的图缺 pdf，或 image_information 有幽灵 stem | P0 | 补文件或删幽灵条目 |
| xlsx 打不开（drawing 悬空） | P0 | `pub_xlsx_strip` 后 `pub_xlsx_verify`，corrupt=0 |
| 扩展名 `.tif` 而非 `.tiff` | P1 | 统一 `.tiff` |
| P / DeLong / NRI / IDI / AUC 单元格裸 `0` 或 `0.000` | P0 | `<0.001`（或参照 `Ref`）；见 `pub_digits_consistency`；QC：`pub_qc_scan_table_digits` |
| 同一课题 P 有的 2 位有的 3 位（未统一 `p_style=fixed`） | P0/P1 | 固定 3 位；仅期刊书面要求时用 nejm 可变位 |
| 描述统计强制 `90.000` / 整数写三位尾零 | P1 | `desc_trim=TRUE` |
| Fig1 PDF 图底长脚注/图注（Methods 段落上图） | P0/P1 | 删图面脚注；细则进 Methods（`attrition_consort_flowchart`） |
| Fig1 排版：末主框与底部分叉叠框、文字截断、Exclude 压主框、箭头断裂 | P0 | 打开 PDF/预览目检；重导 `attrition_draw_pdf`（须预留分叉带宽）；见 nature-figure §6（UA_CR 2026-11） |
| 结局标签生死线：Fig1/封面写 28-day death，Table1/TRIPOD 写 In-hospital death（或反之），且事件数同源 | P0 | 先核 y 定义（ICU 入院锚定 28 天 vs 无限期院内）；表/TRIPOD/Methods/图全链统一；发表面禁止内部字段名（如 `fustatus`）（SA-AKI TCF 2026-11） |
| 双库分析单位粒度矛盾：一侧患者级、一侧 stay 级，Fig1 文案却写成同类「ICU stay」排除 | P0 | Fig1+Methods 按真实粒度改写；先实核 stay ID 是否唯一 / 是否 ICU-first；仅当真多 stay 入样才写 cluster-robust Limitations（SA-AKI TCF 2026-11） |
| Fig1 排除框标签与真实剔除原因不同类（如「结局不可链接」实为「baseline 不可链接」） | P0 | 一句话定义写入 Methods；图面标签=实核原因（SA-AKI TCF 2026-11） |
| ML/TCF Methods 软件清单缺 Python 主链版本，或残留未用的 survival/cmprsk/mediation 预后模板包 | P0 | `Methods_software_versions.txt` 写实 R+Python；踢未用包（SA-AKI TCF 2026-11） |
| 熵筛选/RSCV/TOPSIS α 的拟合数据集未分步写明；笼统 “development” 掩盖 α 用了内验集 | P0 | Methods 逐步骤写 train vs internal validation；披露 α 用内验后该 holdout 非纯 untouched（SA-AKI TCF 2026-11） |
| `complete_action=1` / `logistic_mi` 只挂占位名，未写实现载体（R mice 方法映射）与操作层语义 | P0/P1 | Methods 写实 mice token + complete#1 用途；TCF 分类器指标是否 Rubin 须诚实 |

## Medical Blocks 预后 v2 漏检（强制；2026-10 Hip AKI）

凡审 **prognosis_v2 / Cox 文献发表根**，在通用交付漏检之外另过本表。规则：`prognosis_v2_pub_p0_gate.mdc`；机器：`pv2_pub_p0_gate()`。

| 信号 | 级别 | 必做 |
|------|------|------|
| KM/Fig3 分组 ≠ cascade 锁定（binary 却 Q1–Q4） | P0 | 重导 KM；风险表 Low/High；Methods 同 scheme |
| Fig6 底边 HR ≠ Table S8 Direct（Total 冒充 Direct） | P0 | 底边改 Direct；`pdftotext` 与 S8 逐位一致 |
| Fig7 轴标 Q4 vs Q1（已锁 binary）或层上无 P-int | P0 | 轴标 High vs Low；补乘性交互 P |
| Fig RCS 仅 P-overall，与 Table 3 线性 P 看似矛盾 | P0 | 字幕改 P-linear + P-nonlinear；主推断仍 Table 3 线性 |
| Table S7 path a 方向与 S8 相反（中介→暴露） | P0 | S7 重导为暴露→中介 |
| 中介脚注写 Model 3/「与 Table 2 一致」但实际 Age+Gender | P0 | 脚注改真实调整集；概念重叠如实写，禁止假 VIF 共线 |
| Boruta/SHAP 图面临床名含 `_` | P0 | `pipeline_display_label` 重导 |
| 无 cox.zph / PH 表；Methods 无取材时点或 MICE 结局入模裁决 | P0 | 补 PH 表 + Methods |
| 项目信息列明 ESRD/透析/姑息/ICU≥2 等，但 Fig1 仅画 Age/暴露缺失；且未核首框 N 是否已是排除后人群 | P0 | 实核 D02/提取表：已执行→Methods 写「先诊断码+排除码+停留时长提取，再 Fig1」；未执行→重导 Fig1 或码表层解释，禁止假装已排除（Stroke ANLR 14d 2026-11） |
| 交付无最终 ICD 纳入/排除码表（含语义），或码表含非目标病种残留（如 346.6x/G43.6x 偏头痛无梗死、SAH） | P0 | 作者确认执行码表；Methods 定义段+C5 引文；可疑码不得 silently 交差（Stroke ANLR 14d 2026-11） |
| 暴露「不可计算」剔除占比 &gt;40% 却 Methods/Limitations 不承认选择偏倚 | P0/P1 | 写明不可计算=成分未化验；Limitations 组A 承认方向；可选基线对比列入待补清单（Stroke ANLR 14d 2026-11） |
| 敏感性脚注写 “primary 28-day locked grouping” 而主分析为其它 landmark（7/14/90/365） | P0 | 脚注 landmark 必须跟主文；禁模板残留（Stroke ANLR 14d 2026-11） |
| 同一表连续 per-1-SD HR≈1 而最高分位 HR 强偏离，却无 RCS/非线性说明、也未复算尺度 | P0 | 回代码核 per-SD vs per-unit；若成立写 RCS 佐证；若 bug 重跑或正文只引分位行并登记待确认（Stroke ANLR 14d 2026-11） |
| Fig7 Overall ≠ Table 3 Model1 同对比（差 0.001 亦查；Rubin vs complete#1） | P0 | Numbers_Master 锁单一出处并统一三处（Stroke ANLR 14d 2026-11） |
| Methods 只写 “Boruta/SHAP screening” 无 confirmed 清单规则、SHAP 实现/包、ntree/seed、Model3 交集规则 | P0 | 补可复述方法句 + 最终协变量名单（Stroke ANLR 14d 2026-11） |
| Methods 未声明 RCS 结点数与位置（如 3 knots @ P10/P50/P90 或 ns 内结点百分位） | P0 | 按代码写实 knots（Stroke ANLR 14d 2026-11） |

## Medical Blocks 交叉滞后 / FI 暴露交付漏检（强制；2026-11 depression×HTN×FI）

凡审 **cross-lagged / frailty index / 抑郁人群×共病结局** 发表根，在通用交付漏检之外另过本表。踩坑课题：`22_depression/cross-laged_40595747`。

| 信号 | 级别 | 必做 |
|------|------|------|
| 连续 FI（0–1 尺度）Table2 OR 每 1 单位 ≫10（如 HRS~50）却无 per-unit 口径说明，正文/摘要把巨大连续 OR 当 headline | P0 | 连续行标注 per 1.0-unit + 观测域外推说明；headline 用四分位+trend；脚注/Numbers_Master 登记派生 per-0.1（=OR^0.1）；禁把 per-unit 巨 OR 当主文唯一效应量（depression HTN FI 2026-11） |
| Pooled Table2 脚注写 “Crude Model was adjusted by: Country” 与分库 “non-adjusted” 并存，Crude 名不副实 | P0 | 列头改 Crude† / Model 0；脚注写 country-only；正文写 pooled additionally adjusted for country |
| Methods 写 m=5 / 多重插补却主推断未 Rubin，又暗示已池化；或完全不写 first completed | P0 | Methods 写实 first completed + 结局/暴露不入插补；Limitations 一条（CI 可能偏窄）；待补 Rubin 可列清单，禁空转硬改数据层冒充已池化 |
| Change / Mean-FI 表列名 HR 但无模型族/时间尺度脚注（不知 Cox 还是 logistic） | P0 | 脚注必须含 coxph + Surv(time, event) 或明确 OR/logistic；survey years、design（two_wave/three_plus）、调整集；引擎 `cross_lagged_change_logistic` 注记已强制 Model= 句 |
| CES-D 入组脚本非对称计分（ELSA 反向 x−1 混量纲、缺失置 0）Methods/字典不写实 | P0/P1 | 变量字典 + Methods 逐字写实阈值与缺失规则；重算 DN 须作者裁决，禁 silently 改人群 |
| Methods 写 CLPN “and Age when included” 但交付 S8 邻接矩阵无 Age 节点 | P0 | 按实体裁掉 Age 句；FI 条目数/波次以 S8 表头与 phase meta 可核为准 |
| 抑郁人群课题 FI 含 CES-D 量表条目却无排除说明；或 Psychiatric disease 与 CES-D 混为一谈 | P0 | 核 frailty 成分；CES-D 仅入组；psyche≠CES-D；结局 hibpe 必须剔出分析 FI/CLPN 缺陷节点 |
| 参数（RCS knots、亚组模型、CLPN 波次、FI 条目数）Methods 有写但项目内无表/图/字典可核 | P0/P1 | 每个参数必须能指到交付 xlsx/PDF/meta/Numbers_Master；否则改写为“见图面/见表头”或删无法核的句 |

