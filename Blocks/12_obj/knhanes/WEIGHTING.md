# KNHANES 复杂抽样设计对象构建指南（FIB-4 × 鼻窦炎加权分析线）

版本：v1.0　日期：2026-09-10
适用数据：`data/鼻窦炎/鼻窦炎/鼻窦炎disease_data_v2.csv`（2015–2023 九个年度，含设计变量）
状态：结局侧管道已实测跑通（见 §六 实测结果）；分析集定型后按 §五 重算一次即可复用全文。

---

## 一、设计变量来源与对应列

KNHANES 官方发布的全样本 .sav（本目录 hn98…HN23 共 17 个文件）**自带**全部设计变量，
无需另行下载。在 v2 结局表中的对应列：

| 设计要素 | v2 列名 | 说明 |
|---|---|---|
| 分层 strata | `kstrata`（第5列） | 各周期内部编码，**跨周期码值会复用** |
| 聚类 PSU | `psu`（第4列） | 同上 |
| 权重（主） | `wt_itvex`（第6列） | 건강설문·검진（访谈&体检）合并权重；结局来自问卷、FIB-4 来自体检，与"问卷+体检"样本口径对齐 |
| 权重（敏感性备胎） | `wt_tot`（第7列） | 问卷&体检&营养；Model2 含营养协变量（VitC、β-胡萝卜素）时另出一版对照 |
| 周期 | `cycle`（第2列） | 用于唯一化前缀与 Σn 分组 |
| 主分析过滤 | `in_main_analysis`（第14列） | TRUE = 2015–2023 九个人群口径周期；FALSE = 1998–2009 偏倚子样本（剔除，见取数检查报告 P1） |

实测覆盖：主分析 59,332 行中 `wt_itvex`/`kstrata`/`psu` **零缺失、零权重**。
`wt_tot` 覆盖 87.4%（缺者为未参加营养调查者，仅用于敏感性版本，缺失者剔除并计数）。

---

## 二、多周期合并权重的官方原则（KNHANES ≠ NHANES）

- **NHANES（CDC）**：合并 K 个两年周期 = 权重 ÷ K。前提是各周期设计规模恒定、
  设计变量由 CDC 统一编码发布。
- **KNHANES（KDCA）**：官方权重报告明文规定"통합가중치는 각 조사년도의 표본크기에 비례하도록
  산출"——合并权重**按各调查年度样本量成比例**归一：

$$W_i \;=\; wt\_itvex_i \times \frac{n_{cycle(i)}}{\sum_{c} n_c}$$

  原因：① 每个年度权重各自已代表韩国全人口，直接堆叠=总体数 9 遍，必须归一；
  ② 2016 年起年度调查，各年达成样本量有波动（本数据 4,884–7,508，最小比最大低 35%），
  "÷K 等贡献"前提不成立。
  ÷K 仅是 n 全相等时等比法的特例。
- **设计变量**：KDCA 不发布跨周期统一的 strata/PSU，**必须自行拼周期**
  （KNHANES 加权最常见事故点；照抄 NHANES 模板会静默错并不同年的同名层）。

参考出处：KDCA《제6기 표본설계 및 제5기 가중치 산출》（nih.go.kr）；
《제4기(2007-2009) 가중치 산출》；Epidemiol Health 2014 (KNHANES 2008-2012)；
20周年述评 Epidemiol Health 2021。

---

## 三、构建步骤（代码与验收标准一一对应）

```r
library(survey)

## Step 1 数据就位：一人一行，携带 4 个设计字段 ------------------------
d <- read.csv("data/鼻窦炎/鼻窦炎/鼻窦炎disease_data_v2.csv", stringsAsFactors = FALSE)
d <- d[which(d$in_main_analysis %in% TRUE), ]          # 2015–2023
d$DN <- as.numeric(d$DN)
# ✔ 验收：nrow(d)==59332（结局侧口径）；
#        sum(is.na(d$wt_itvex))==0 && sum(d$wt_itvex==0)==0；psu/kstrata 无缺失

## Step 2 合并权重：按各周期样本量等比 --------------------------------
n_cyc <- as.numeric(ave(rep(1, nrow(d)), d$cycle, FUN = sum))
d$W   <- d$wt_itvex * n_cyc / sum(n_cyc)
# ✔ 验收：W 无 NA/0；逐周期乘子 = n_cycle/59332（对照 §四 表）

## Step 3 分层与聚类全局唯一化：码值拼周期 -----------------------------
d$STRATA <- factor(paste(d$cycle, d$kstrata, sep = "_"))
d$PSU    <- factor(paste(d$cycle, d$psu,    sep = "_"))
# ✔ 验收（结局侧口径）：层数 = 241；PSU 数 = 1,716；无任何 (cycle,psu) 跨层串号

## Step 4 构建设计对象 -------------------------------------------------
options(survey.lonely.psu = "adjust")                   # 必须在 svydesign 之前设置
des <- svydesign(id = ~PSU, strata = ~STRATA, weights = ~W,
                 data = d, nest = FALSE)
# ✔ 验收：lonely PSU 行数 = 0（合并后每层≥2 PSU，实测满足）；
#        summary(des) 抽查各层权重和 > 0

## Step 5 有效性体检（三条硬指标）--------------------------------------
m    <- svymean(~DN, des)
se_iid <- sqrt(coef(m)*(1-coef(m))/nrow(d))
# ✔ ① 加权 vs 未加权患病率偏离 < 1 个百分点级（过大多为权重拼错/周期没筛净）
# ✔ ② deff = (SE_des/se_iid)^2 落在 1–4 正常带（实测 1.62）
# ✔ ③ 每层 ≥2 PSU 或已声明 adjust
saveRDS(des, "design_outcome_2015_2023.rds")            # 建一次，全程复用
```

顺序固定不可调换：**过滤 → 合并权重 → 唯一化设计变量 → 设 lonely 策略 → 建对象 → 体检**。

---

## 四、合并权重乘子速查（结局侧口径，Σn = 59,332）

| cycle | 年份 | n | 乘子 n/Σn | 等效"除以" |
|---|---|---|---|---|
| HN15 | 2015 | 6,454 | 0.1088 | 9.19 |
| HN16 | 2016 | 7,508 | 0.1266 | 7.90 |
| HN17 | 2017 | 7,358 | 0.1240 | 8.06 |
| HN18 | 2018 | 7,390 | 0.1246 | 8.03 |
| HN19 | 2019 | 7,346 | 0.1238 | 8.08 |
| HN20 | 2020 | 6,595 | 0.1112 | 9.00 |
| HN21 | 2021 | 6,387 | 0.1077 | 9.29 |
| HN22 | 2022 | 4,884 | 0.0823 | 12.15 |
| HN23 | 2023 | 5,410 | 0.0912 | 10.97 |

年份以各 .sav 内嵌 `year` 变量确证。**本表仅为速查/核对用，代码一律用 Step 2 的 `ave()` 自动算，
分析集定型后数字会变，不要手填。**

---

## 五、两个必须重跑的时点

1. **分析集定型后**（baseline/zb 按 (ID, cycle) 重建、暴露与协变量过滤完成）：
   在定型样本上原样重跑 Step 1–5——Σn 换成分析集逐周期人数（预期 N≈44–46k）。
   代码一字不改，只有数字变。Methods 写明 "proportional to each survey year's sample
   size **in the analytic dataset**"。
2. **任何子集分析**（删男性敏感性、亚组）：**不要**重新构造权重常数——
   用 `subset(des, Gender=="Female")` 从同一对象切，survey 包会自动按子集重估。
   只有样本的"入组资格"变了（如新增缺失过滤）才需回 Step 1。

---

## 六、结局侧实测结果（2026-09-10 跑通）

| 指标 | 数值 |
|---|---|
| 主分析行数 / 病例 | 59,332 / 4,118 |
| 层 / PSU / lonely PSU | 241 / 1,716 / 0 |
| 未加权患病率 | 6.941% |
| **加权患病率** | **7.210%**（95%CI 6.945–7.475） |
| SE（设计线性化） | 0.135% |
| **deff** | **1.62** → 旧未加权线 SE 低估约 27%，CI 过窄、P 虚高 |

产物：`design_outcome_2015_2023.rds`（位于数据目录，加载即用）。

---

## 七、下游使用纪律（防错清单）

- [ ] 一切推断走 `design=des`：`svyglm(Disease ~ FIB4 + covars, design=des, family=quasibinomial)`；
- [ ] **永不**把 W 塞进 glm/lrm 的 `weights=` 参数（设计方差会丢失，等于白加权）；
- [ ] Table 1：连续 `svyby(~x, ~Disease, svymean)` + `svyvar`（口径 Mean±SE，不再是 SD）；
      分类 `svychisq`（Rao-Scott）；
- [ ] RCS 分位切点用 `svyquantile(~FIB4, des, c(.25,.5,.75))` 重算；
- [ ] XGBoost/SHAP 维持未加权，Methods 标注"变量重要性探索，不承担全国推断"；
- [ ] 中介分析维持未加权 + "探索性"标注；如审稿坚持再加 IPW-MSM；
- [ ] 敏感性双对照：wt_itvex（主） vs wt_tot（营养口径）；再附"未加权 vs 加权 vs ÷9"三列放 S8；
- [ ] 结果报告 deff；权重极值（min/max、Top1% 权重占比）写入补充材料。

---

## 八、Methods 建议句（可直接改用）

> KNHANES employed a multi-stage stratified cluster probability design. Analyses used data
> from nine consecutive annual survey waves (2015–2023). Because the outcome (physician-diagnosed
> sinusitis) came from the health interview and the exposure (FIB-4 indices from AST/ALT/platelets)
> from the health examination, the interview–examination combined weight (wt_itvex) of each survey
> year was used. Pooled weights were constructed following KDCA guidelines in proportion to each
> survey year's sample size in the analytic dataset: W = wt_itvex × n_year / Σ n_year. Strata and
> PSUs were re-defined with a survey-year prefix to ensure global uniqueness across waves
> (241 strata, 1,716 PSUs, no lonely strata). Standard errors were estimated by Taylor series
> linearization (`survey` package, R; design effect for the prevalence estimate = 1.62).
> The interview–examination–nutrition combined weight (wt_tot) served as a sensitivity analysis
> for models including dietary covariates.

**Limitations 呼应句**：合并九年年度数据跨越问卷与设计调整；早于 2015 的周期因 DJ6_dg
仅对耳鼻喉检查子样本施测（阳性率 71–100%）被整体剔除，泛化窗口限于 2015–2023。

---

## 九、遗留事项

| 事项 | 状态 |
|---|---|
| 结局侧设计对象 | ✅ 建成并验证（design_outcome_2015_2023.rds） |
| baseline/zb 按 (ID,cycle) 重建 | ⬜ 加权主分析唯一前置工程 |
| KDCA codebook 确认早周期 8 含义 | ⬜ 写 rebuttal 用（现有文件证据已支持"未施测"解释） |
| 旧 D05（47,734）处置 | 归档，仅作旧稿数字溯源，不进新分析 |
