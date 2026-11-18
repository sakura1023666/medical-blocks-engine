# 复用地图：预后 v2 发表宽表 / 分位级联 / 交付白名单（2026-10-23）

来源课题：Hip arthroplasty + AKI（MIMIC-IV，SIRI/PIV，365 天全因死亡）对标 Jin/TyG 补充表。

## 下次新课题怎么用（不要抄 Hip 私有脚本）

1. **分位**：config 开 `quantile_scheme_cascade`（`pass_rule="all"`）；全文跟锁定 scheme。
2. **主表宽表 / 敏感性改终点**：`source("R/pv2_literature_pub_tables.R")`  
   - `pv2_cox_wide_m123_body` + `pv2_write_cox_wide_xlsx`  
   - 敏感性：`pv2_censor_at_days(d, 90)` 后再跑宽表（勿默认「排除早期死亡」除非课题需要）。
3. **S6/S7/S8**：同一文件 `pv2_s6_before_after_body` / `pv2_s7_exposure_mediator_body` / `pv2_s8_mediation_body`；S7/S8 协变量 = Table 3。
4. **方法学 + 软件版本 + 白名单**：  
   `Rscript run/pub/finalize_delivery_root.R --dir <summary_results> --study-type prognosis_v2 ...`  
   中期 PDF 写出后再 `--prune-only`。
5. **Nature 质控**：`run_pub_qc_after_project.R` + Agent Layer D；P0 清零后出中期。
6. **P0 防复发门控（2026-10-26）**：`R/pv2_pub_p0_gate.R` + 规则 `prognosis_v2_pub_p0_gate.mdc`；详见 `docs/reuse/2026-10-26-prognosis-v2-hip-aki-p0-gate-reuse-map.md`。

## 引擎文件（权威）

| 文件 | 作用 |
|------|------|
| `R/quantile_scheme_cascade.R` | 分位级联闸门 |
| `R/pv2_literature_pub_tables.R` | 文献宽表 / S6–S8 / 改终点 |
| `R/pub_prognosis_v2_methods.R` | Methods 正文模板 |
| `run/pub/finalize_delivery_root.R` | Methods + 软件版本 + prune |
| `run/prognosis_v2/pv2_mi_cox.R` | Rubin Cox |
| `R/pub_figure_export.R` | 四目录 / image_information |

## 课题薄封装（仅 Hip 路径）

`run/prognosis_v2/remirror_hip_aki_pub.R` 与 `_rebuild_*_hip_aki.R`、`_refresh_image_info_hip_aki.R` —— 只含本题路径/指标名；算法在引擎。

## 已归档（勿复活）

`run/prognosis_v2/_archive_oneoff_20261023/`

## 反例

- 在结果目录写 `hotfix_*.R` 当长期方案  
- S7/S8 仍用 Age-only / Crude 与 Table3 分裂  
- 交付根留下 `content.json` / `reports/` / `_report_dump.md`  
- 新课题继续 `sys.source("_apply_quantile_cascade_hip_aki.R")`
