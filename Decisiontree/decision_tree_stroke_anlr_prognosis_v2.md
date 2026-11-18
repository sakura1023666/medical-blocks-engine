# 分析决策树 — 缺血性卒中 ANLR × 28 天全因死亡（prognosis_v2 双库平权）

**状态：** 用户 2026-11-05 已确认 design + 本决策树口径  
**Spec：** `docs/superpowers/specs/2026-11-05-stroke-anlr-prognosis-v2-dual-design.md`  
**Plan：** `docs/superpowers/plans/2026-11-05-stroke-anlr-prognosis-v2-dual.md`

```text
研究问题
  └─ ANLR 对缺血性卒中 ICU 患者 28 天全因死亡的关联与预测价值
       │
       ├─ 地基 = 预后 prognosis_v2（对标 Hip summary_results 清单）
       ├─ 库 = MIMIC + eICU 平权；特征 = 列交集
       ├─ 人群 = Age ≥ 18
       ├─ 暴露 = ANLR = Albumin/(Neutrophil/Lymphocyte)
       ├─ 终点 = Mortality_28d / survival_time_28d
       ├─ 分位 = cascade Q→T→B；双库同 scheme 水平数
       ├─ Cox = M1 未调整 / M2 Age+Gender / M3 共享∩UV∩VIF（无 SOFA、无成分）
       ├─ 插补 = MICE m=5；推断 Rubin
       ├─ 中介 = 先 S7 相关 → 再 S8 中介(SOFA) → Fig6；同闸门
       ├─ 敏感性 S5 = 院内全因死亡
       └─ 交付 = T1–3 + S1–9 + Fig1–7（中介失败则 S7/S8/Fig6 双侧省略）
```

## 对抗阅读备注（迁移）

本题方法学包迁移自 Hip prognosis_v2（Rubin Cox、分位级联、Boruta/SHAP、RCS、ROC、相关→中介、PH）。  
完整 Q1–Q8 GLM 对抗若需补档，可对用户指定 PDF 另开；**不阻塞**已确认口径的实现（用户已确认 design）。
