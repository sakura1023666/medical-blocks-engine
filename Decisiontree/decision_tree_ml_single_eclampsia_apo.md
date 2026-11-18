# 分析决策树 — 27 妊娠不良结局 · 单库 ML 发病（全可算复合指标）

- 课题根：`/mnt/g/02block_result/27_eclampsia/ml_40395549/`
- 表图角色对齐：`15_hearing_loss/.../【success】TyG_WHtR/summary_results`（单库 `summary_results`：Fig1–5 + S1；Table1–4 + S；Methods）
- 地基：**发病** + 方法后缀 **ML**（`config_ml_single_batch` / `ml_dual_batch_build`，`single_db=TRUE`，**非 NHANES 加权**）
- 数据：全部数据整合（回顾性），不用单独前瞻表

## 节点

1. **研究问题** → 复合炎症/脂代谢指标 × **妊娠不良结局**（二分类发病）  
2. **结局** → `不良妊娠结局` 总括列；Case=1（n≈864），Control=0（n≈2300）；删 1 行全缺失  
3. **暴露** → `index_mode=single_loop`，**仅可算真复合指标**（见下表）；两路 `--workers 2`  
4. **不可算 / 禁跑** → 缺成分（Glucose/TC/Albumin/Cr/WC/…）；HDL/LDL 自身透传  
5. **单位** → 血脂 mmol→mg/dL；尿酸 µmol→mg/dL；BMI 合成 Height/Weight  
6. **纳排** → 有效 ID + 非缺失结局；年龄不设上下限（范围 17–54；`<18` 保留并在 Methods 注明产科队列）  
7. **年龄亚组** → `age_cutoff=35`（高龄产妇）  
8. **插补** → m=5 cart，`fit_on=train`，`rubin_pool=TRUE`，`complete_action=1`  
9. **关联** → logistic；Model1=Age+Gender；Model2=UV→VIF→MV→VIF final  
10. **ML** → 与听力损失单库同款：关 TabPFN/mlp；LASSO 定特征；SHAP=验证集最优；指标根 `summary_results/`  
11. **中介** → `mediation_incidence`（非 NHANES 加权）；门控 `skip_export_if_ns=TRUE`  
12. **disease_vars** → 分项不良结局 + 新生儿结局/Apgar/体格 + 产后出血量 + 分娩孕周  

## 可算暴露池（拟跑）

| 指标 | 成分 | 备注 |
|------|------|------|
| NLR | NEU, LY | |
| PLR | PLT, LY | |
| SII | PLT, NEU, LY | |
| NLPR | NEU, LY, PLT | |
| PHR | PLT, HDL | |
| LHR | LY, HDL | |
| UHR | UA, HDL | |
| AIP | TG, HDL | 比值单位无关，仍统一 mg/dL |
| TG_HDL_C | TG, HDL | |
| CRI_II | LDL, HDL | |
| VLDL | TG/5 | 需 TG mg/dL |
| BMI | Weight, Height | 由孕早期 BMI 反推 |
| AIP_BMI | AIP × BMI | |

**拟跑 13 个**；`fail_policy=continue`。

## 发表产物角色（对齐参考）

| 角色 | 参考（听力 TyG_WHtR） | 本课题 |
|------|----------------------|--------|
| Fig1 | Flowchart | 同 |
| Fig2 | RCS | 同 |
| Fig3 | ML 2×4 | 同 |
| Fig4 | SHAP | 同 |
| Fig5 | 亚组森林 | 同 |
| Fig S1 | LASSO | 同 |
| Table1–4 / S* | 基线·logistic·ML·补充 | 无 survey 加权字样 |

## 待你确认（确认后立刻写 config + shared-only + workers 2）

- [ ] 结局 = 不良妊娠结局总括（不用「诊断」作结局）
- [ ] 「诊断」作协变量保留
- [ ] 暴露池 = 上表 13 个（可删可增）
- [ ] 年龄切点 35；workers=2
- [ ] 表图结构对齐听力损失 `summary_results`（单库非加权）
