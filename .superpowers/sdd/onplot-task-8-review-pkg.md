--- /mnt/e/01block/01Block-new-Final/.superpowers/sdd/snap-before-task8/pub_figure_image_information.mdc	2026-08-21 09:42:52.000000000 +0800
+++ /mnt/e/01block/01Block-new-Final/.cursor/rules/pub_figure_image_information.mdc	2026-08-26 16:55:54.324379200 +0800
@@ -18,6 +18,14 @@
 4. **纳排图（Figure 1 Flowchart）必须逐步人数**：从 `Tables/Flowchart_attrition*.csv` 按库列出每步保留 n，并写「本步排除 X 人」（相邻步差额）。缺 CSV 须明示，不得空话带过。
 5. **数字来源**：只写可收获证据（attrition CSV、Table 2、cutoff CSV、`simple_ROC.rds` / `plot_cutoff.rds`、`_batch_status.json`）。禁止编造 HR/AUC/N。
 6. **Grouping** 与主文闸门一致（logistic/Cox gate）；预后结局字段如 `fustatus` 在上下文中写可读名（如「住院死亡」）并可附原字段名。
+7. **图面标注必录**：图上可见的关键数字/标注必须写入 `## 图面说明`（建议小标题「图上标注」），包括但不限于：
+   - RCS：`P-overall` / `P for overall`、`P-non-linear` / `P for nonlinear`、竖线 cutoff
+   - KM：Log-rank P、二分 cutoff
+   - Forest：Overall 与各亚组效应量(95%CI)、P for interaction
+   - ROC：AUC、CI、Youden、灵敏度/特异度（图上有则写）
+   - maxstat：图上切点
+   - Flowchart：逐步 n 与排除人数
+   数字只来自可收获产物；缺则写「未收获」；**禁止编造**。其它图种若图上有数字，同理。
 
 ## 实现入口
 
@@ -34,9 +42,13 @@
 - [ ] md 含 `## 图面说明`，**不含** `## 标识` / `## 技术`
 - [ ] Figure 1 若存在，逐步纳排人数与排除人数已写出
 - [ ] 样本量不是无故「未记录」（有 `_batch_status.json` 时应写入分库 N）
+- [ ] RCS 图 md 含 P-overall / P-non-linear 与 cutoff（图上有则写，缺则「未收获」）
+- [ ] KM 图 md 含 Log-rank P 与 cutoff（图上有则写）
+- [ ] Forest 图 md 含 Overall 与各亚组效应量(95%CI)、P for interaction（图上有则写）
 
 ## 反例（禁止）
 
 - 只有一句「Flowchart展示…逐步筛选过程」且无逐步 n
+- RCS 图上有 P-overall / P-non-linear / cutoff，md 却只有「展示非线性关系」等空话
 - 仍保留「图号 / 文件路径 / DPI / TIFF 压缩」两段
 - 课题私自再写一套 image_information 模板绕过公共函数
