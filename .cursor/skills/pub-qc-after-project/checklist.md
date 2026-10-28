# 发表质控检查清单（C 档）

Agent 按层打勾；不适用项写 `N/A` + 一句理由。

## §0 范围（先做）

- [ ] 只枚举 `【success】*`；已统计并跳过全部 `【failed】*` 与裸名 `by_index/<INDEX>/`
- [ ] 聊天已列出「将审 success」与「failed 仅计数」
- [ ] 用户点名的指标若无 success 产物 → 跳过并记 WARN，未打开 failed 目录

## §A 结构（硬）

- [ ] 审阅根路径已确认（Windows/WSL 等价）
- [ ] 成功单元列表已列出（且仅为 success）
- [ ] `Figures/pdf|png|tiff|image_information` 存在
- [ ] Figures 根无残留平铺 `Figure*.pdf`
- [ ] 每张定稿 pdf 有同 stem 的 png + tiff
- [ ] tiff 体积 > 0（过小视为缺失）
- [ ] 定稿 png/tiff 嵌入 DPI ≥ 600（全项目；Nature Layer D 必检）
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

## §B3 NHANES / 发病交付漏检（2026-10 银屑病 eGDR；未勾不得 PASS）

规则全文：`.cursor/rules/pub_nhanes_incidence_p0_gate.mdc`。无 NHANES / 无加权发病时可整节 `N/A`。

- [ ] **硬门控** 根 `Table 2` Model2 脚注协变量 = `step*_logistic_*` 源表脚注 = 中介/RCS/S8/S10 脚注（同名同集）；禁止根表「删 Diabetes」等只改脚注
- [ ] **硬门控** 根 Table2 Model2 主对比 OR(CI) **字符串** = 同调整集的 step 源表（不一致 → 回写或重导）
- [ ] **硬门控** 主文/Table1/Table2 分位 = **调查加权**；S1/不加权基线/不加权 GLM 若另一套中位数或切点 → 脚注写 unweighted 且不可与 Table2 互换
- [ ] **硬门控** 中介 Total effect 与 Table2 最高分位 OR：同调整集已声明；数值不同须脚注「不必逐字相同」，禁止正文硬拗一致
- [ ] **硬门控** 中介路径图数字 = 中介表对应行；实现口径写 `svyglm`/PSU bootstrap（B、seed），勿假写未用的包
- [ ] **硬门控** Methods 含：暴露公式+出处、MICE(m/method/seed/结局是否入模/complete)、`new_Weight`+层/PSU、终模路径（S3–S7 或等价）；S5 暴露效应消失须点名不藏
- [ ] **硬门控** ROC/`image_information` **无**「惩罚/GBM 训练 AUC 抬高、CV 掉下去所以图上不用」类自曝句；只报图面 AUC
- [ ] **硬门控** 亚组图面 NE ↔ fig md NE；禁止 md 残留 `0.00`+假小 CI；NE 须有图注/脚注事实句
- [ ] 描述脚注若写 mean (SE) or median，表内须真有 mean；否则改单口径（median only）
- [ ] 表题「with \<Disease\>」等与表内容（全队列 vs 病例）一致

冲突记录格式：`左侧来源 | 数值 | 右侧来源 | 数值 | 差分说明`

> 踩坑：VitalDB AKI Sodium 2026-10 — Table3/Fig3 仍 N=6037 而 Fig1=3522；规则见 `.cursor/rules/pub_qc_denominator_crosscheck.mdc`。  
> 踩坑：Psoriasis eGDR 2026-10 — Table2 无 Diabetes OR=0.528 vs 引擎含 Diabetes 0.487≈中介总效应；加权 9.39 vs 不加权 9.318；Fig3 md 抄旧伪 CI。

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
- [ ] 收尾已跑 `pv2_pub_p0_gate()` 或等价 `pdftotext` 核验；失败不得 PASS

> 踩坑：Hip AKI 2026-10 — Fig3 四分位 vs 锁 binary；Fig6 Total≠S8 Direct；Fig7 无 P-int / Q4vsQ1；Fig4 仅 P-overall；Fig2 下划线；S7 反向；无 PH/取材时点/MICE 裁决。

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
