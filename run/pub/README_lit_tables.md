# 文献 wide 版式发表表 · 复用 Runbook

> 沉淀自 17_AKI「ACAG+RAR」审稿返工（2026-09）。
> 目标：**任何双库预后 ML 课题**都能用一条命令，从 assoc checkpoint 重算并导出
> 对齐 ASCVD/SHR+GV 原文补充材料的「wide 版式」表，**不再堆课题级一次性脚本**。

## 单一来源

- 内核：`R/pub_reference_lit_tables.R`（`pub_lit_*` 函数）
- CLI：`run/pub/rebuild_lit_publication_tables.R`
- 依赖（引擎既有）：`R/ml_reference_assoc_figures.R`、`R/prognosis_reference_assoc.R`、
  `R/ml_assoc_covariate_rule.R`、`R/utils.R::sci_xlsx_single_header_booktabs`、
  `R/pub_figure_export.R::pub_figure_ensure_formats`

绘图内核（Fig1–8 / Fig S1–S5）**本就在** `ref_assoc_fig*` / `ml_ref_*`，
本模块只补「表」和「Fig S1 原文 PH β(t) 样式」这类之前散在 tmp 的逻辑。

## 一条命令（任意课题）

```bash
export MEDICAL_BLOCKS_ROOT=/path/to/engine
Rscript "$MEDICAL_BLOCKS_ROOT/run/pub/rebuild_lit_publication_tables.R" \
  --config <study>/config.R \
  --index  <A+B>            \  # 如 ACAG+RAR；有 config combos 时端点名可反查
  --index-a <A> --index-b <B> \ # 可选：显式端点
  --cutoff 4,10            \  # SOFA 分层界值
  --primary MIMIC_IV --secondary eICU \
  --glucose-threshold 70   \  # S9 敏感性阈值（本课题口径，非原文 ICU 低血糖）
  --fig-s1                 \  # 额外重画 Figure S1（原文 plot.cox.zph 双库 A/B）
  --tables t1,joint,s4,s5,ph,s9,s10,s2,s3,s11   # 默认全集，可只跑子集
```

默认写到 `by_index/【success】<INDEX>/Tables`；`--out <dir>` 可先落 staging 校验。

## 产出表（wide 版式，与原文对齐）

| 表 | 函数 | 说明 |
|---|---|---|
| Table 1（分库）| `pub_lit_style_table1` | Survivor/Non-survivor + 暴露归入末节 Exposures；No AKI/AKI 自动改写 |
| Table 2 | `pub_lit_table_joint` | 联合分组 Cox：Overall+SOFA 层，M1/M2/M3，Group1–4 + P for trend；双库 Panel A/B |
| S4 | `pub_lit_table_index_tertile` | 单指标 T1–T3 + P for trend，各层 |
| S5 | `pub_lit_table_discrimination` | AUC(95%CI)+Youden+DeLong vs 联合参考；**排除分层键 SOFA** |
| S6–S8 | `pub_lit_table_ph_layer` | 各 SOFA 层 PH（cox.zph Variable\|P）|
| S9 | joint + `pub_lit_exclude_glucose` | 排除基线 Glucose<阈值（双库 Panel）|
| S10 | joint + `pub_lit_complete_case` | complete-case 联合 Cox |
| S2 | `pub_lit_table_uni_cox` | 单因素 Cox（顺序对齐 Table1）|
| S3 | `pub_lit_table_vif` | car::vif GVIF/Df/GVIF^(1/(2Df))；**Diabetes 与 T1DM/T2DM 别名保护** |
| S11 | `pub_lit_reshape_ml_perf` | 分层五模型性能宽表：train/internal/external × 层 × LR/DT/RF/XGB/LGB |
| Fig S1 | `pub_lit_fig_ph_beta_trends_original` | 原文 plot.cox.zph β(t)（粉虚线 y=0，双库 A/B），落四目录 |

## 协变量方案（Model1–3）

CLI 自动用 `config$assoc_covariate`（含 `scheme="literature_m123"`）经
`ml_resolve_assoc_covariates` 注入 M1/M2/M3；外验库 `pub_lit_share_assoc_models`
套同一 M3。联合切点=主库 train 冻结上三分位（type-7）。

## 定稿措辞：写进课题 config，不写进引擎

引擎默认标题/脚注为**通用模板**。若某课题定稿脚注与默认不同，
把**确切措辞**放进课题 `config.R`（引擎读 `config$lit_tables`，支持 `{IA}{IB}{ILAB}{PRI}{SEC}{OUT}{GTH}` 占位替换），使**引擎输出 == 定稿**，成为单一来源：

```r
config$lit_tables <- list(
  table1 = list(footnotes = c(...)),   # 覆盖 Table1
  s3 = list(footnotes = c(...)),       # 覆盖对应表；未列的键走默认
  s9 = list(title = "Table S9. ...", footnotes = c(...))
)
config$pub_table1_spec <- list(        # S2/S3 变量名单（顺序/显示名对齐 Table1）
  list(label = "Age", col = "Age", type = "continuous"),
  list(label = "Heart Failure", col = c("Heart Failure","Heart_Failure"), type = "categorical"),
  ...)
```

已验证：17_AKI 的 `config$lit_tables` + `pub_table1_spec` 让引擎 CLI 对
Table1/2/S2/S4/S5/S6–S11 **逐格一致**（S3 仅 1e-14 浮点尾差）。

## 全清重跑接线（可选）

指标整链重跑（如 `tmp/rerun_acag_model3_full.sh`）后，第 6 步直接：

```bash
Rscript "$MEDICAL_BLOCKS_ROOT/run/pub/rebuild_lit_publication_tables.R" \
  --config "$STUDY/config.R" --index "$INDEX" --fig-s1
```

无需再跑任何课题 `tmp/rebuild_acag_*.R`（已归档 `tmp/_archive/2026-09_acag_lit/`）。

## 铁律提醒（复用别绕）

- **分层键 SOFA 不得当预测因子**（S5 默认对照已排除 SOFA）。
- **S9 按本课题可解释规则**（基线 Glucose<70），题名/脚注注明非原文 ICU 低血糖。
- 出表后跑 `pub_xlsx_verify`（readable / corrupt=0 / styles>0）；改图跑
  `pub_figure_ensure_formats` 四目录。
- 小数位统一走 `pipeline_apply_pub_digits`（3/3/2/4）。
