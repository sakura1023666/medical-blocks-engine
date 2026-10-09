# 对标文献代码可得性与方法审阅（Chen JAD 2026 → 胆结石列线图）

日期：2026-09-30  
对标：Chen et al. *J Alzheimers Dis* 2026，DOI `10.1177/13872877261424471`（PMC13022025）  
课题：`45_Gallstone/Nomogram_41815074`（方法迁移，非原文胆结石数据）

## 1. 有没有公开代码？

**结论：没有公开分析代码仓库。**

| 来源 | 内容 |
|---|---|
| Data availability | 仅声明公共数据：**NHANES** + **CHARLS** 官网链接；无 GitHub / Zenodo / OSF |
| Methods | **R 4.3.1** + **FreeStatistics 2.1.1**（商业/平台 GUI，非可复现脚本包） |
| Supplemental（sj-docx） | 补充**表**与变量说明；**无 R/Python 源码**、无 `glmnet`/`rms`/`forestplot` 脚本 |
| 检索 | DOI / 题名 / 作者 × github：无匹配分析仓 |

因此无法「对照原文全部代码」做逐行 diff；只能按 Methods / 图注 / 补充表做**方法口径审阅**。

## 2. 原文方法骨架 vs 我们实现

| 模块 | 原文（Chen JAD） | 本课题实现 | 差异/风险 |
|---|---|---|---|
| 地基 | 发病 logistic / OR / AUC | 同（incidence + 列线图后缀） | 对齐 |
| 关联 Fig2 | 5 个中心性肥胖指数 × Model1–3 | 10 个连续结石/能量特征 × Model1–3 | 特征池不同（数据所致）；版式应对齐森林图 |
| Model1–3 | 文献事先校正集（M1 粗 / M2 人口学 / M3 全混杂） | **Age 强制 + UV 显著**（用户死规则） | **刻意偏离原文**；须在 Methods 写清 |
| Fig3 RCS | 4 knots；非线性检验 | rms `rcs`；部分特征 Model3 过拟合跳过 | 需在图注标明跳过特征 |
| 划分 | 7:3 train/val + **CHARLS 外验** | 7:3 + **仅内部 bootstrap**（用户锁定） | 外验弱于原文 |
| LASSO | λ.1se → 多因素 → 列线图 | 同；`stone_type` 近分离剔除 | 合理；须脚注 |
| Fig7–9 | train / val / **external** ROC·校准·DCA·CIC | train / val / **bootstrap** | 面板语义替换，勿再写 external |
| 软件 | R + FreeStatistics | R：`glmnet` / `rms` / `brglm2` / `forestploter` / `regplot` 等 | 工具链不同，估计应一致口径 |
| 插补 | 敏感性含 MI | 本数据无缺失，插补关闭 | OK |

## 3. Fig2 版式问题（已修）

对照当前 PNG 与原文 Fig2 观感：

| 问题 | 原因 | 处理 |
|---|---|---|
| 画布周围白边过大 | `save` 强制 `max(height=11)` ≫ `get_wh` | 改为紧贴 `get_wh×0.95` |
| 下方文字与刻度重叠 | `forest(..., footnote=)` 与 x 轴同一底部带 | **取消图内脚注**；口径写入 `Methods_fig2_footnote.txt` |
| 右侧大片空白 | `xlim` 拉到 50（线性感） | **log 轴 + xlim [0.05, 20]**；极端 CI 文字列标 `>50` |

入口：`run/gallstone_nomogram/rebuild_all_pub_figures_lit.R`（Fig2 段）。

## 4. 仍建议盯的实现点（相对原文精神）

1. **分离/准分离**：`ct_max` / `energy_j` / `pct_gt80` 等 OR≈0 或 CI 爆炸——原文 FreeStatistics 路径未见同类结石 CT 特征；我们已用 brglm2 + 显示裁剪，正文勿过度解读点估计。  
2. **Fig3 部分 RCS 跳过**：与原文「全指数出 RCS」不完全同构，汇总 Fig3 须标明缺失面板。  
3. **Age∈Model1**：工程铁律已落地；与原文「Model1=crude」不同，Methods / 决策树已改。  
4. **不可声称「复现了原文代码」**：只能声称「按 Chen 2026 发表流程图与模型层级迁移方法」。

## 5. 可公开对照的原文产物（非代码）

- 正文 PDF：`临床预测模型-列线图-10.1177_13872877261424471(1).pdf`  
- 补充 DOCX：`sj-docx-1-alz-10.1177_13872877261424471 (2).docx`  
- PMC：https://pmc.ncbi.nlm.nih.gov/articles/PMC13022025/
