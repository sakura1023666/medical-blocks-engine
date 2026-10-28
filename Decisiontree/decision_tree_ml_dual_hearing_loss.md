# 分析决策树：听力损失双库 ML（发病地基 + ML 后缀）

## 地基判定
- **地基**：发病（现患 Hearing loss / Non-hearing loss）
- **后缀**：ML dual batch（`dev_internal_ext`）
- **3A**：复制白内障 `40_Cataract/ml_40395549` 实例化

## 纳排
- Age **45–69**（用户文稿 2.2）
- NHANES + CHARLS（文稿第三单中心临床样本本课题不做）
- Fig1：银屑病 eGDR **pv2** 版式

## 主/外验角色（人多为主库）
- 45–69 后 CHARLS N≈13,297 > NHANES N≈6,416
- **主库 CHARLS**（训+内验）；**外验 NHANES**（冻结特征；`db_type=nhanes`）
- 与白内障「NHANES 主」不同，因本队列人多库为 CHARLS（引擎 `ml_dual_assert_primary_larger_n`）

## 暴露
- `single_loop` × 双库共同真公式复合指标（用户授权全池；shared 后 47 个）

## 交付对标
- Tables/Figures 角色对齐 `【success】TyG_WWI`（Table1–5、S1–S12、Fig1–8 四目录；主库标签为 CHARLS）

## 门控状态
- [x] 列对齐词典 `Data/_dual_db_column_harmonize.md`
- [x] 列审阅 `Data/_column_review.md`（测听/DN → disease_vars）
- [x] PubMed 查新 `reports/pubmed_novelty_hearing_loss_composite_2026-10-21.md`
- [x] shared-only：47 可算；10 路 workers 已启动
