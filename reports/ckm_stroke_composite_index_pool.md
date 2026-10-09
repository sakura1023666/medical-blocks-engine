# 可算复合指标池 — CKM CHARLS 卒中发病 batch

数据列约束见 `Data/_column_review.md`。来源：`configs/indices/composite_index_vars.R` + `Blocks/00_index/01block_index.R`。  
禁止透传「组成=自身」：`HDL`/`LDL` 不进配对/主暴露池。

## A. 主文方法深度（两波累积 + k-means + logistic/RCS/亚组/敏感）

| 指标 | 两波成分 | 说明 |
|------|----------|------|
| **eGDR** | wc+htn+hba1c 两波齐全 | 索引文献完整复现；`cum` 乘子 **×3（与文献公式一致）** |

## B. 发病式并行 worker（基线复合指标 → 同套 logistic/RCS/亚组；无两波则不做 k-means 累积）

在现有 4d 列下**可算**（wave1）：

| 指标 | 所需列 | 备注 |
|------|--------|------|
| TyG | glucose1, tg1 | |
| AIP | tg1, hdl1 | |
| NHHR / TC_HDL / AC / CRI_I | tc1, hdl1 | 同源比值，建议只留 **NHHR** 防重复 |
| CRI_II | ldl1, hdl1 | |
| TG_HDL_C | tg1, hdl1 | 与 AIP 相关，可选一 |
| NHDL | tc1, hdl1 | |
| RC | tc1, hdl1, ldl1 | |
| LCI | tg,tc,ldl,hdl | |
| CHG | tc, glucose, hdl | 同领域 CHARLS CKM 卒中文献常用 |
| SHR / HGI | glucose, hba1c | HbA1c 轴；本库有 |
| HbA1c_HDL_C | hba1c, hdl | |
| METSIR | glucose, tg, bmi, hdl | |
| VAI | wc, bmi, tg, hdl, sex | |
| LAP | wc, tg, sex | |
| TyG_BMI / AIP_BMI | 用 bmi1 等价实现 | 公式原写 Weight/Height² |

## C. 本数据不可算（缺细胞计数/肝酶/身高体重独立列等）

NLR, PLR, SII, FIB4, CMI, WWI, WHtR, ALI, 多数炎症链…… → **不进池**。

## D. 建议首批 `index_vars`（待你确认）

**完整后缀（累积+k-means）**  
1. `eGDR`

**基线发病并行（精选、去高度共线重复）**  
2. `TyG`  
3. `AIP`  
4. `CHG`  
5. `NHHR`  
6. `VAI`  
7. `LAP`  
8. `METSIR`  
9. `SHR`  
10. `CMI` — **暂缓**（缺 Height）  
11. `TyG_BMI` — 可选

> 若要求「文献完整深度」仅对 eGDR 强制 Fig2 k-means；其余指标出 Table2/RCS/亚组/敏感性（基线），并在决策树注明深度差。

## E. 查新

多指标单暴露 loop（非双复合组合 job）→ 按发病 batch 惯例；若改为 `combo_loop` 双复合，须另做 PubMed 双组合查新后再锁 `index_combos`。
