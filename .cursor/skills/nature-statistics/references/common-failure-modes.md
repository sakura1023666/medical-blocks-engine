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
| 森林图 CI 与 P 明显矛盾，或某分层没有交互 P 却在正文报告 | P0 | 注明 CI 与 P 的检验口径；交互未估出则正文不提 |
| 加权构成比配未加权检验，脚注未声明 | P0 | 脚注写明百分比口径与检验是否 design-based |
| 中介 Total effect CI 被写成与主表同一模型 | P0 | 说明调整集不同，两值不互串 |
| 中介 Total OR 与 Table2 最高分位 OR 不同却正文/脚注硬拗「一致」 | P0 | 脚注写同调整集下规格可不同；或重导对齐；禁止无说明硬拗（Psoriasis eGDR 0.489 vs 0.528） |
| 根 Table2 Model2 脚注协变量 ≠ step 源表 / ≠ 中介脚注（如删 Diabetes 只改脚注） | P0 | 脚注与 OR 字符串与 step 源表对齐；见 `pub_nhanes_incidence_p0_gate` |
| 主文加权分位与 S1/不加权敏感性中位数混用且不披露 | P0 | 主链锁加权；另一套脚注 unweighted |
| Methods 缺公式出处 / MICE(m,seed,结局是否入模) / new_Weight+PSU | P0 | 按实补 Methods（轨道 B 可只改文） |
| ROC 或 fig md 自曝内部算法试验（训练抬高、CV 掉下去所以不用） | P0 | 只报图面 AUC；删自曝句 |
| 图面 NE，fig md 仍抄 0.00 或 1e-07 伪 CI | P0 | md/正文以图面为准；NE 事实句 |
| 脚注写 mean (SE) or median，表内全是 median | P1 | 改单口径 |
| 结局只有列名、没有可从数据列复述的判定式 | P1 | 用现有列反推能解释的比例，写明无法解释的残余（如问卷列缺失） |
| 引用的图缺 pdf，或 image_information 有幽灵 stem | P0 | 补文件或删幽灵条目 |
| xlsx 打不开（drawing 悬空） | P0 | `pub_xlsx_strip` 后 `pub_xlsx_verify`，corrupt=0 |
| 扩展名 `.tif` 而非 `.tiff` | P1 | 统一 `.tiff` |

## Medical Blocks 预后 v2 漏检（强制；2026-10 Hip AKI）

凡审 **prognosis_v2 / Cox 文献发表根**，在上表之外另过本表。规则：`prognosis_v2_pub_p0_gate.mdc`；机器：`pv2_pub_p0_gate()`。

| 信号 | 级别 | 必做 |
|------|------|------|
| KM/Fig3 分组 ≠ cascade 锁定（binary 却 Q1–Q4） | P0 | 重导 KM；风险表 Low/High；Methods 同 scheme |
| Fig6 底边 HR ≠ Table S8 Direct（Total 冒充 Direct） | P0 | 底边改 Direct；`pdftotext` 与 S8 逐位一致 |
| Fig7 轴标 Q4 vs Q1（已锁 binary）或层上无 P-int | P0 | 轴标 High vs Low；补乘性交互 P |
| Fig RCS 仅 P-overall，与 Table 3 线性 P 看似矛盾 | P0 | 字幕改 P-linear + P-nonlinear；主推断仍 Table 3 线性 |
| Table S7 path a 方向与 S8 相反（中介→暴露） | P0 | S7 重导为暴露→中介（`pv2_s7_exposure_mediator_body`） |
| 中介脚注写 Model 3/「与 Table 2 一致」但实际 Age+Gender | P0 | 脚注改真实调整集；概念重叠如实写，禁止假 VIF 共线 |
| Boruta/SHAP 图面临床名含 `_` | P0 | `pipeline_display_label` 重导 |
| 无 cox.zph / PH 表；Methods 无取材时点或 MICE 结局入模裁决 | P0 | 补 S9 + Methods（轨道 B 可只改文） |
