# 轨迹预后 fcimb 交付收口复用地图（2026-11-27）

## 何时用

COPD / 任意指标走 `build_fcimb_summary_results.R` 出 `summary_results` 后，必须同一套发表收口：

- 禁下划线（表 + image_information）
- Times New Roman / Liberation Serif（含 PAMM Fig5/6/S6）
- 文献小数位：HR/CI **2** 位；P 3 位或 `<0.001`；AUC 3；人数千分位
- Methods md + 软件版本 txt
- 中期 PDF（客户默认 **天涯**，**不写日期**）
- `summary_results` 只留 Figures / Tables / Methods_* / *中期*.pdf

## 入口（引擎，勿课题 hotfix）

| 层 | 路径 |
|---|---|
| API | `R/trajectory_fcimb_delivery_finalize.R` |
| CLI | `run/trajectory_prognosis/finalize_fcimb_summary_delivery.R` |
| 自动挂点 | `build_fcimb_summary_results.R` 末尾 |
| PAMM 字体 | `Blocks/26_trajectory/30block_trajectory_pamm.R` → `.tpamm_draw_fcimb_panels` |

```bash
Rscript run/trajectory_prognosis/finalize_fcimb_summary_delivery.R \
  --dir ".../by_index/【success】WPR/summary_results" \
  --index WPR --client 天涯 --no-date --ng 4

# 只要 scrub/Methods，跳过中期：
MEDICAL_BLOCKS_SKIP_MIDTERM=1 Rscript run/trajectory_prognosis/build_fcimb_summary_results.R --index WPR --proj ...
```

## config

`configs/config_trajectory_prognosis_copd_jlcm_batch.R`：

- `trajectory_pub$midterm_client = "天涯"`
- `trajectory_pub$midterm_no_date = TRUE`
- `pub_digits`：`est=2, p=3, desc=2, p_style="nejm"`（对齐 fcimb 文献 HR 两位）

## 检查

- [ ] `pdffonts` 无 NimbusSans/Helvetica
- [ ] Layer A3 下划线 PASS；A4 Times PASS
- [ ] Methods 含 Reporting digits + WPR 公式 + ng
- [ ] 交付根白名单五件套；无 reports/content.json
- [ ] 中期封面有客户名、无「分析日期」
