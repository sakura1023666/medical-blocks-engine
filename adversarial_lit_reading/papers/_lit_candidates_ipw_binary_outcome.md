# IPW + 二分类病理反应（对标胃癌课题）文献候选

> 检索日期：2026-10-27  
> `papers/` 原有 IPW 文献（用药模型三分.pdf）为 **生存结局**，不适合无随访时间的 TRG 课题。  
> 下列为新检索推荐；请把 PDF 放入本目录后可做对抗阅读。

## 主推（病种+结局最贴）

**Jin P, et al.** Neoadjuvant chemotherapy with docetaxel, oxaliplatin, and S-1 versus oxaliplatin and S-1 for locally advanced gastric adenocarcinoma: A multicenter, real-world cohort study.  
*Int J Cancer.* 2026. PMID: **41450028**. DOI: [10.1002/ijc.70315](https://doi.org/10.1002/ijc.70315)

- 人群：局部进展期胃癌，新辅助化疗方案对比（DOS vs SOX）
- 方法：PSM + **IPTW**
- **主终点：MPR（Mandard TRG 1–2）** → 二分类病理反应 + OR
- PS 协变量：age, sex, site, cT, cN, grade, Lauren
- 次要才有 DFS/OS（你无时间数据时可只对标主终点 IPTW+OR 部分）

## 次推（暴露更像「化疗 vs 化疗+免疫」）

**Comparative Efficacy and Safety of Neoadjuvant Immunotherapy with Chemotherapy versus Chemotherapy Alone in Non-Small Cell Lung Cancer: A Propensity Score and Inverse Probability Treatment Weighting Analysis.**  
*ImmunoTargets and Therapy.* 2023. PMID: **38026088**. DOI: [10.2147/ITT.S437911](https://doi.org/10.2147/itt.s437911)  
PMC: [PMC10651418](https://pmc.ncbi.nlm.nih.gov/articles/PMC10651418/)

- 暴露：新辅助 **化疗 vs 化疗+免疫**（与你的临床问题更同构）
- 方法：PSM + **IPTW**
- 主看 **pCR / MPR**（二分类病理反应）
- 病种是 NSCLC 而非胃癌；有生存次要终点，但病理反应可独立对标

## 不推荐作本课题母版

- `用药模型三分.pdf`（Jin 2026 BCRT）：IPW + **OS/KM**，需随访时间
