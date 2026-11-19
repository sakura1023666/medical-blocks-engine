# 预后 v2 Table S4 / Fig5：连续指标无协变量 ROC（复用地图）

**踩坑**：COPD `prognosis_v2_41904528`【success】ALBI（2026-11）— 交付 S4/Fig5 用 Cox LP（index + Age/Sodium/GCS），与参考文献单指标 ROC 分裂。

## 引擎入口（新课题只调这里）

| 能力 | 文件 / 函数 |
|------|-------------|
| 拟合 + Youden + DeLong | `R/pv2_index_roc.R` → `pv2_index_roc_fit` |
| 双库曲线 | `pv2_index_roc_curve_by_db` |
| 脚注 / Fig md | `pv2_index_roc_footnotes` / `pv2_index_roc_image_md` |
| 文案审计 | `pv2_index_roc_audit_delivery_text` |
| 门控挂点 | `R/pv2_pub_p0_gate.R`（扫 S4 xlsx + Fig5 PDF/md） |
| 规则 | `.cursor/rules/prognosis_v2_pub_p0_gate.mdc` §5 |

## 已改调用方

- `run/prognosis_v2/rebuild_copd_{tables,figs}_hip.R`
- `run/prognosis_v2/_rebuild_stroke_anlr_tables_hip_layout.R`
- `run/prognosis_v2/_fix_stroke_anlr_fig4_7_hip.R`
- `run/prognosis_v2/remirror_hip_aki_pub.R`

## 禁止

- remirror / rebuild 手写 `coxph` → `predict(type="lp")` → `pROC` 占 **Table S4 / Figure 5**
- 脚注写 `Cox LP` / `linear predictor of … + Age…`
- 课题 `/tmp` 或 `work/hotfix_*` 私有 ROC 绕过引擎

## 检查

```bash
Rscript tests/test_pv2_index_roc_unadjusted.R
```
