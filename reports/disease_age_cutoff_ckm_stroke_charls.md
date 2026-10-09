# 年龄亚组切点依据 — CKM × 卒中（CHARLS）

课题：累积/复合指标 → 新发卒中；队列 CHARLS，CKM stages。

## 结论（写 config 用）

**`subgroup$age_cutoff = 60L`**，`Age_Group = c("< 60", "≥ 60")`。

## 依据

1. **索引文献** Wang et al. Cardiovasc Diabetol 2026;25:78：亚组明确 `age (< 60 vs. ≥ 60 years)`。
2. **同设计 CHARLS×CKM×卒中/CVD 文献**（近作）亚组普遍采用 **&lt;60 / ≥60**，而非 65：
   - 累积 CHG × CKM0–3 × 卒中（CHARLS）
   - CHG 及其修饰指数 × early CKM × 卒中
   - CMI × CKM0–3 × CVD（CHARLS）
   - eGDR × CKM0–3 × 卒中相关分析
3. 本队列为中老年 CHARLS（纳入常 ≥45），60 与文献亚组可对齐，避免与索引文 Fig/Table 切点分裂。

## 不采用 65 的原因

项目全局默认 65 多用于「无病种特异文献」模板；**本病种（CKM+卒中+CHARLS）有一致的 60 依据**，按 `age_subgroup_binary` 铁律优先病种文献界值。

## config 注释草稿

```r
# 年龄切点依据：索引文 Wang 2026 及 CHARLS CKM–卒中同设计研究亚组均用 <60 vs ≥60
subgroup = list(age_cutoff = 60L, level_order = list(Age_Group = c("< 60", "\u2265 60")))
```
