# 肺栓塞 × 阿替普酶 IPW 双库（对齐 Jin 用药模型图/表）设计规格

> 状态：已确认（用户 2026-10-09「确认无改」）  
> 日期：2026-10-09  
> 方法学来源：Jin et al. 2026 *Breast Cancer Res Treat*（`adversarial_lit_reading/papers/用药模型三分.pdf`）  
> 产物对齐：`11_ischemic stroke/Medication_regimen_model_42118193`（Fig1–5 + S1–S4；Table1 + S1–S4）  
> 数据根：`\\192.168.68.133\02block_result\47_PE\DATA` → `/mnt/g/02block_result/47_PE/DATA`  
> 建议产出根：`/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/`（新建，不覆盖卒中旧 【success】）

## 0. 已锁定决策

| 项 | 选择 |
|----|------|
| 研究问题 | PE 患者：**阿替普酶是 vs 否** → **28 天全因死亡**（方案 A） |
| 落地路径 | **路径 1**：MIMIC / eICU **各跑一套完整 Jin IPW 链**，再对双库共有图做拼图 |
| STEPP | **保留**；横轴 = 本库 `composite_risk`（VIF→Model2→Cox LP，**不含**阿替普酶） |
| 双库拼图 | Fig1–5、Fig S1–S4 做成 **A MIMIC \| B eICU** 双栏定稿；根 `Figures/` 只留拼图 |
| 表 | Table1 / S1–S4 **分库各一套**，编号角色对齐，不硬拼宽表 |
| 地基 | **预后** + IPW 后缀；复用 `Blocks/69_ipw_diabetes_stroke_full/` + 既有 IPTW/STEPP/亚组块 |
| 复合指标 | `index.enable = FALSE`（与卒中 Jin 定稿一致，无 NLR 并行） |
| 参考文献映射 | 原文放疗 → 阿替普酶；原文 5 年 OS → 28 天生存/死亡 |

## 1. 方法学映射（Jin → 本课题）

| 维度 | 原文（Jin 2026） | 卒中参考课题 | 本课题（PE） |
|------|------------------|--------------|--------------|
| 队列 | NCDB 乳腺癌 | MIMIC 缺血性卒中 | MIMIC + eICU **肺栓塞** |
| 暴露 | 放疗 vs 未放疗 | `Diabetes_HbA1c`（HbA1c≥6.5） | ``Alteplase`（**仅处方**；敏感性可∪输液） |
| PS / IPW | 基线混杂 → IPW | 单因素(P&lt;0.10)→VIF→Model2 | **同左**（双库各自筛） |
| 主分析 | 加权 KM + IPW-Cox | 同左 | 同左 |
| STEPP | 5 年 OS × composite risk | 28 天生存 × `composite_risk` | **同左**；双库各自拟合 LP |
| 敏感性 | 多变量 Cox | Cox + 重叠权重 | 同左 |
| 库数 | 单库 | 单库 MIMIC | **双库并行 + 拼图** |

### 1.1 暴露定义（写 config 前须落盘核对）

粗算（2026-10-09）：

| 库 | PE 队列 n | 处方阳性 | 输液阳性 | 并集（拟暴露） |
|----|-----------|----------|----------|----------------|
| MIMIC | 1621 | `ymtmd`≈425 | 输液列≈73（列名导出为 dexmedetomidine，文件名=阿替普酶，**须人工确认语义**） | ≈428（~26%） |
| eICU | 1721 | `gy`≈70 | `sy`≈41 | ≈109（~6%） |

规则（待实现时写死进 config 注释）：

1. 暴露 = 住院/ICU 期间 **处方 OR 输液** 阿替普酶任一阳性。  
2. 列名以课题 `DATA` 文件为准；MIMIC 输液列若确认非阿替普酶则改用正确源，禁止静默沿用错名。  
3. eICU 暴露稀缺：照常出全套图；STEPP 窗口按 N 下调；脚注披露不稳定风险，**不删 Fig5**。

### 1.2 结局

- 时间：`surv_time_28d`（源：`hosp_survival_day` 或等价，封顶 28）  
- 事件：`surv_event_28d`（源：`death_within_hosp_28days` / 院内死亡且时间≤28）  
- 与卒中 IPW config 字段同构，双库列名经 `column_mapping` 对齐。

## 2. 发表产物清单（一个不能少）

### 2.1 每库单元内（对齐 `【success】main`）

| 键 | 文件角色（卒中示例名 → PE 改名） |
|----|----------------------------------|
| Fig1 | Flowchart of patient selection |
| Fig2 | IPW-weighted KM，28-day mortality by Alteplase |
| Fig3 | Subgroup IPTW forest |
| Fig4 | Subgroup KM by age（+ 若有 treatment forest 同号规则跟卒中） |
| Fig5 | STEPP of 28-day survival by Alteplase across composite risk |
| Fig S1 | Missing value overview |
| Fig S2 | PS distribution + SMD before/after weighting |
| Fig S3 | Unweighted KM |
| Fig S4 | Calibration + ROC at 28-day |
| Table 1 | Baseline before and after sIPTW |
| Table S1 | Uno's C-index at 28-day |
| Table S2 | Baseline before/after MI |
| Table S3 | Univariate regression |
| Table S4 | VIF (univariate screen) |
| 敏感性 | Multivariable Cox；Overlap weights（块内表，跟卒中链） |

### 2.2 双库拼图（用户已确认）

对 **Fig1–5、Fig S1–S4**：单库跑完后拼 **A=MIMIC | B=eICU**，写入课题根 `Figures/`（四目录：pdf/png/tiff/image_information）。  
单库带 `-MIMIC`/`-eICU` 后缀的图保留在 `by_unit/.../Figures/` 备查，**不**作为主文根目录定稿。

表：**不拼**；两库各自 Table1/S1–S4，角色同号。

## 3. 架构与流水线

### 3.1 目录

```text
47_PE/Medication_regimen_model_alteplase_ipw/
  data/          # 或软链 DATA/MIMIC、DATA/EICU 清洗后宽表
  config_*.R     # 可按库两份，或一份 + database 参数
  _shared/       # 每库 shared：data_clean → column_mapping
  by_unit/
    【success】main_MIMIC/   # 或 units = MIMIC / eICU
    【success】main_eICU/
  Figures/       # 仅双栏拼图定稿
  Tables/        # 分库表镜像（可选按库子目录）
  reports/       # 对抗阅读、列审阅、暴露核对、pub_qc
```

### 3.2 主链（每库各跑一次；与卒中定稿同构）

```text
shared:  data_clean → column_mapping   (index OFF)
unit:    imputation
      → ipw_*_exposure（阿替普酶二分类；复用/改名 69 暴露块逻辑）
      → analysis_exclusion（disease_vars=PE 相关泄漏列；protect Alteplase/surv_*/composite_risk）
      → univariate_prognosis → multicollinearity_screen
      → ipw_jin_composite_risk   # Model2 → composite_risk
      → iptw_balance → iptw_association
      → flowchart → weighted KM → subgroup IPTW → treatment forest → subgroup KM
      → stepp_prognosis(index_var=composite_risk, jin_treatment)
      → cox_binary → overlap → calib-ROC → literature_targets → pub_export
      → （课题收口）dual remirror 拼图 + pub_figure 四目录
```

复用入口：

- Blocks：`69_ipw_diabetes_stroke_full/*`、`iptw_*`、`stepp_prognosis`、`subgroup_*`  
- Runner：复制 `run/ipw_diabetes_stroke/` → `run/ipw_pe_alteplase/`（或同目录加 PE config）  
- 拼图：对齐 `run/incidence/remirror_index_pub_outputs.R` 习惯，写 PE IPW remirror 或通用双栏拼接  

### 3.3 明确不做

- 不挖第三块地基；不做 TEXT/SOFT `58_medication_regimen` 文本套路。  
- 不做复合指标 batch 并行。  
- 不把 MIMIC 的 `composite_risk` 系数套到 eICU。  
- 不覆盖卒中 `Medication_regimen_model_42118193` 旧成功目录。

## 4. 写 config 前门控（不可跳）

按 `pipeline-foundation`：

1. **PDF 切块**（若无）→ **对抗阅读**至少 Q4/Q5/Q8（完整则 Q1–Q8）对 `用药模型三分.pdf`。  
2. **列名对齐词典**（MIMIC↔eICU）→ 落盘。  
3. **`review-raw-covariate-columns`** → `Data/_column_review.md` + `analysis_exclusion$disease_vars`（PE 诊断/严重度泄漏列）。  
4. **暴露核对报告**：处方/输液列语义、并集 n、双库暴露率。  
5. **28 天结局**可算性：预后 CSV / baseline 时间与死亡字段。  
6. **年龄切点**：默认 65（注释：无病种特异则默认；可后改）。  
7. 输出 **分析决策树** → 用户确认后再 `--shared-only` / workers。

## 5. 风险与缓解

| 风险 | 缓解 |
|------|------|
| eICU 暴露仅 ~6% | 全套仍产出；脚注 + STEPP 窗口缩小；必要时 Methods 写外验探索性 |
| MIMIC 输液列名可疑 | 暴露核对强制人工确认后再锁定义 |
| 双库 PS 协变量不一致 | 允许库内各自 UV→VIF；拼图脚注写明「库内筛选」 |
| 拼图轴范围不一致 | 双库共用 `xlim`/`ylim`/`forest_xlim` 策略 |

## 6. 实施顺序（确认本 spec 后）

1. 对抗阅读 + 决策树  
2. 数据组装（PE 队列 ⋈ 阿替普酶 ⋈ 预后结局）+ 列审阅  
3. 项目 config + runner（路径 1）  
4. MIMIC shared → unit；eICU shared → unit  
5. 双栏拼图 + 四目录 + 表镜像  
6. `pub-qc-after-project` + nature-statistics / nature-figure（P0 清零）

## 7. 成功标准

- [ ] 两库各自具备 Fig1–5、S1–S4、Table1、S1–S4（角色齐全）  
- [ ] 根 `Figures/` 为双栏拼图且四目录完整  
- [ ] STEPP 横轴为各库 `composite_risk`，图例为 Alteplase No/Yes  
- [ ] 未改卒中旧 【success】目录  
- [ ] `reports/pub_qc_*.md` 出具且 Nature P0 清零或用户书面接受残留  

## 8. 自检（写稿时）

- 无 TBD 占位；暴露并集规则已写死。  
- 路径 1 / STEPP / 拼图三决策与对话确认一致。  
- 范围限于 PE 阿替普酶 IPW 双库，不含 TST/发病 logistic 扩 scope。
