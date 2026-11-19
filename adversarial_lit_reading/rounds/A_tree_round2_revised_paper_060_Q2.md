# AI-A Revised Decision Tree — paper_060 / Q2

revision_source: A_tree_round1 + B_attack_tree_paper_060_Q2.md

## 1. Revised Evidence Map

| evidence_id | location | evidence_summary | used_by_node |
|---|---|---|---|
| E1 | Methods 2.3(2); Results 3.2 | 人中心 LPA 亚型供下游分层/调节 | N1 |
| E2 | Methods 2.3(3) | 多症状条目入网络；回答结构关联而非传统多暴露回归族 | N2 |
| E3 | Methods 2.3(4); Table 6 | All+各亚型分别估中介；文本与表对「哪类最强」存在不一致风险 | N3,N3b |
| E4 | Methods; Table 1 note | 未见 Bonferroni/FDR；有多变量模型与 Fisher 选择意识 | N4 |
| E5 | Methods 2.2.4 | 情绪结局为预先验证合成分工具，非数据 PCA | N5 |
| E6 | Methods 2.3(3) | 报告 CS 稳定性；Profile1 CS 偏低需标局限 | N7 |
| E7 | Methods | 未见主次终点预注册声明（未报告≠证实未做） | N6 |

## 2. Mermaid（脱敏）

```mermaid
flowchart TD
  Q2["Q2 多亚型/多终点/多层暴露"]
  N1["人中心亚型: 分层兼调节"]
  N1u["分类误差是否传入下游? 原文未说明"]
  N2["网络=多症状结构; 非传统多暴露逐检替代"]
  N2b["多暴露-结局传统族: 原文主线未用该框架"]
  N3["中介: 全样本+各亚型分别报告"]
  N3b{"文本排序 vs 表内CI 是否一致?"}
  N4{"分析类型: 多变量模型 vs 逐检验排序?"}
  N4a["未报告FDR/Bonferroni"]
  N4b["仅分别报告CI: 膨胀有限但不可显著性排序"]
  N5{"终点是否预验证合成分?"}
  N5a["是: 用已验证工具"]
  N5b["否: 需PCA流程"]
  N6["主次终点预注册: Methods未见"]
  N7["网络稳定性CS; 低CS亚型降权"]
  Q2 --> N1 --> N1u --> N3 --> N3b
  Q2 --> N2 --> N2b
  Q2 --> N5
  N5 -->|是| N5a
  N5 -->|否| N5b
  N3 --> N4
  N4 -->|用于排序声明| N4a
  N4 -->|仅分报CI| N4b
  Q2 --> N6
  N2 --> N7
```

## 3. Final Answer

1) **多亚型**：LPA 亚型作分层/调节轴，网络与中介在全样本+各亚型分别报告。  
2) **多层/多症状**：网络处理症状关联结构，**不能**等同于解决传统多暴露-结局多重检验；中介仍以单一中介总分。  
3) **多重比较**：原文未报告 FDR/Bonferroni；对多变量模型与「仅分报 CI」场景，不宜从沉默直接判「有罪膨胀」；若用亚型间显著性排序则有族水平风险。  
4) **复合终点**：用预先验证合成分工具，不是数据驱动 PCA。  
5) **额外**：需警惕 Results 叙述与 Table 中介 CI 对「哪类最强」可能不一致；低 CS 亚型网络解释需降权。

## 4. Revision Log

| 批评 | 严重度 | 处理 |
|---|---|---|
| 网络≠多暴露解决方案 | 高 | 采纳 N2/N2b |
| Table6 vs 文本矛盾 | 高 | 采纳 N3b |
| 沉默→膨胀跳跃 | 高 | 采纳 N4/N4a/N4b |
| U1 高估膨胀 | 高 | 采纳限定 |
| PHQ 预验证限定 | 中 | 采纳 N5a |
| CS 低 | — | 采纳 N7 |
