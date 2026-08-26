### Task 2: 逐列审阅 → `_column_review.md` + disease_vars

**Files:**
- Create: `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/_column_review.md`

**Interfaces:**
- Consumes: `dabiao` 全列名
- Produces: 审阅表；`.disease_exclusion_vars` 字符向量供 Task 3 粘贴

- [ ] **Step 1: 导出列名**

```bash
Rscript -e 'load("/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/mimic/D04_dabiao.RData"); writeLines(names(dabiao), "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/_column_review_raw.txt"); cat(length(names(dabiao)), "cols\n")'
```

- [ ] **Step 2: 按子痫病理写 `_column_review.md`**

对每一列写：`列名 | 保留/排除 | 理由`。

**默认排除进 `disease_vars`（子痫/子痫前期谱系泄漏，不确定则排除）：**

- 诊断/共病：`Hypertension`（与子痫定义高度重叠）
- 糖尿病轴：`T1DM`, `T2DM`, `Diabetes`, `Glucose`, `HbA1c`
- 尿蛋白轴：`UrineProtein`, `UrineGlucose`, `AlbuminUrine`, `AlbuminCreatinine`
- 其它明显疾病诊断列若与子痫病理强相关且易泄漏，标注【边界·已排除】一并列入

**保留示例：** 人口学 `Age`/`Race`/…；通用实验室（非尿蛋白/血糖轴）；其它共病如 `COPD` 等非子痫核心标志（若审阅认为可留）。

**不进 disease_vars：** `ID`, `DN`（结局）；复合指标 `ALBI`（由成分排除处理）。

- [ ] **Step 3: 自检**

确认原始列无一遗漏；摘要打印 `disease_vars` 名单长度 ≥ 8。

---

