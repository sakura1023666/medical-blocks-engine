# 发表质控报告

- 项目根：`/mnt/g/02block_result/46_CKM/累计暴露聚类_41654871`（`G:/02block_result/46_CKM/累计暴露聚类_41654871`）
- 审阅结论：**WARN**
- 是否建议交稿：条件通过（需接受本口径 N=4,983 ≠ 原文 5,248；表为 CSV 非期刊三线 xlsx；图为可发表 PDF 但排版可再抛光）
- 审阅范围：仅 【success】（`all_success` n=1：`by_unit/【success】eGDR`）；已跳过 【failed】 n=0
- routine：`incidence` + `cum_egdr_kmeans` 后缀；单指标 eGDR；文献固定 Model1–3；无 UV/VIF
- 日期：2026-09-30
- Agent：pub-qc-after-project

## 摘要
- Layer A 结构：大体 PASS（四目录 9 图齐；Fig1 md 逐步人数需补强 → WARN）
- Layer B 数字：Fig1 终步=Table1 N=4983 一致；Table2/S1 方向与文献一致（高 eGDR 保护）
- Layer C 逻辑：P0=0，P1=2，P2=2

## Layer A — 结构
| 项 | 结果 | 证据路径 |
|----|------|----------|
| 四目录 pdf/png/tiff/md | PASS | `by_unit/【success】eGDR/by_index/eGDR/Figures/` 各 9 张；tiff>0 |
| 根目录无平铺 PDF | PASS | 已清理 `Figure 3_test` |
| 主文图表键 | PASS | Fig1–3、Table1–3 均在 |
| 补充键 | PASS | Table S1–S4、Fig S1–S3 均在 |
| image_information 结构 | WARN | 有「图面说明/分析上下文」；Fig1 逐步 n 未在 md 展开（CSV 有） |
| SCI 三线 xlsx | WARN | 当前为 CSV；未走 `export_sci_table` 抛光 |
| code 包 | PASS | `by_unit/【success】eGDR/code/` 存在 |

## Layer B — 交叉数字
| 对照 | 左值 | 右值 | 结果 | 证据 |
|------|------|------|------|------|
| Fig1 终步 vs Table1 N | 4983 | 4983 | PASS | `Flowchart_attrition_CHARLS.csv` / `Table 1…csv` |
| Fig1 排除步 | 8358/1804/709/1854 | 交付文档本口径 | PASS | 与 `data/3_纳排…md` 一致 |
| Table2 Class M3 Stable_high | OR 0.30 (0.22, 0.41) | 文献方向=高 eGDR 保护 | PASS | 数值非复现靶，方向一致 |
| Table2 cum M3 | OR 0.92 (0.91, 0.94) | S1 Cox M3 HR 0.93 (0.91, 0.95) | PASS | OR/HR 同向同量级 |
| 原文终点 N | 5248 | 本口径 4983 | WARN | 交付件已声明非逐字复现 |

## Layer C — 逻辑
| ID | 级别 | 问题 | 建议 |
|----|------|------|------|
| C1 | P1 | 表为 CSV，非期刊三线 xlsx/tex | 需要交稿版式时再挂 `export_sci_table` / 外科 xlsx |
| C2 | P1 | Fig1 image_information 未写逐步 n | 可从 attrition CSV 回填 md |
| C3 | P2 | Class 语义锚定为本实现（均值+Δ），非原文标签精确复现 | Methods 脚注说明 |
| C4 | P2 | MICE 本队列近乎完整，S3/S4≈完整病例 | 脚注已写 sensitivity README |

## 下一步（给用户）
1. 主产出目录：`by_unit/【success】eGDR/by_index/eGDR/{Tables,Figures}`
2. 若要期刊三线表：指定优先 Table 1/2/3 → 再抛光
3. 飞书标记未开（本跑 `feishu$enable=FALSE`）；需要再说

## 附录 — 文献键对照
| 文献 | 本产出 | 状态 |
|------|--------|------|
| Fig.1 | Figure 1 flowchart + attrition CSV | OK |
| Fig.2A–C | Elbow / trajectory / boxplot | OK |
| Fig.3A–C | RCS 三面板 | OK |
| Table 1 | Baseline by Class | OK |
| Table 2 | Logistic Class/cont/tertile × M1–3 | OK |
| Table 3 | Class subgroup | OK |
| Table S1–S4 | Cox / Cox-MICE / logistic-MICE | OK |
| Fig.S1–S3 | Cox RCS / cum subgroup HR/OR | OK |
