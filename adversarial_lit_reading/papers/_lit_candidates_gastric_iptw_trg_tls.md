# 胃癌课题文献候选（按你的 4 个问题）

> 检索日：2026-10-27  
> 数据：`51_gastric cancer/incidence_38341157`（治疗 × TRG 三级 × 组化 × TLS）  
> `papers/` 里的 `用药模型三分.pdf`（乳腺癌放疗 × 生存 IPW）**不作本课题方法母版**。  
> 下列 PDF 需你自行下载放入 `adversarial_lit_reading/papers/`，再做对抗阅读。

---

## 1. 普通化疗 vs 加免疫 → 治疗效果（TRG/pCR）

### 方法母版（IPTW + 病理反应 OR）— 必读

| 项 | 内容 |
|----|------|
| 文献 | Jin P, et al. Neoadjuvant DOS vs SOX for LAGC. **Int J Cancer** |
| PMID | **41450028** |
| DOI | [10.1002/ijc.70315](https://doi.org/10.1002/ijc.70315) |
| 为什么用 | **PSM + IPTW**；主终点 **Mandard MPR（TRG）**；报告 **OR**；PS 协变量含 age/sex/cT/cN/Lauren |
| 局限 | 比的是两种**化疗方案**，不是免疫；你只对标**方法骨架** |

### 临床问法母版（化疗+免疫 vs 单纯化疗）— 必读

| 优先级 | 文献 | PMID / 链接 | 要点 |
|--------|------|-------------|------|
| ★★★ | Zhang X, et al. Neoadjuvant PD-1 + chemo vs chemo alone. **Transl Oncol** 2023 | [36934638](https://pubmed.ncbi.nlm.nih.gov/36934638/) · [PMC10034143](https://pmc.ncbi.nlm.nih.gov/articles/PMC10034143/) | 暴露同你；结局 pCR/TRG；**开放获取** |
| ★★★ | Neoadjuvant ICI+chemo vs chemo, HER2(−) LAGC, **PSM**, *Chin Med J* 2025 | [38420853](https://pubmed.ncbi.nlm.nih.gov/38420853/) | 大样本 PSM；pCR/TRG0↑ |
| ★★ | WJSO 2025 NICT vs NCT | [40189585](https://pubmed.ncbi.nlm.nih.gov/40189585/) · [10.1186/s12957-025-03710-8](https://doi.org/10.1186/s12957-025-03710-8) | 小样本；pCR/TRG |
| ★ | Ann Oncol 3027eP 2025 | 摘要 | nICT vs nCT；TRG0 25.5% vs 7.8% |

建议：**方法读 41450028；问法读 36934638 或 38420853**。

---

## 2. 免疫组化指标有无差异

一般嵌在疗效比较文的 Table1 / 病理特征里（按治疗组比 MMR/HER2/PD-L1）。  
可直接复用上面「化疗±免疫」文的基线/病理表逻辑；不必单开一篇「组化差异」专文。

---

## 3. 治疗前组化一致性（活检 vs 手术）

| 指标 | 文献 | PMID | 要点 |
|------|------|------|------|
| **HER2** | GERCOR；*Ann Oncol* | [24114855](https://pubmed.ncbi.nlm.nih.gov/24114855/) | 配对一致率约 **94%**；NAC 后可漂移 |
| **HER2** | *Gastric Cancer* | [25512144](https://pubmed.ncbi.nlm.nih.gov/25512144/) | 最终阴阳性 **κ≈0.69**；IHC 分档 κ较低 |
| **PD-L1** | *Br J Cancer* 2019：活检能否代表全瘤 | [31285589](https://pubmed.ncbi.nlm.nih.gov/31285589/) | 一致率约 **64%**，κ≈**0.31**；建议多点活检 |
| **PD-L1** | APEROL；*Ann Oncol* 451P | 摘要 | 新辅助后一致性更差 |

你数据已有 `MMR_Concordance` / `HER2_Concordance`：表格式对标 HER2 文；PD-L1 对标 BJC/APEROL 报 κ。

---

## 4. 治疗能否增加 TLS

| 优先级 | 文献 | PMID | 要点 |
|--------|------|------|------|
| ★★★ | Neoadjuvant PD-1+chemo → 高 pCR + 抗肿瘤免疫亚群；缓解床可见 **TLS** | [36268179](https://pubmed.ncbi.nlm.nih.gov/36268179/) · OncoImmunology · [PMC9578498](https://pmc.ncbi.nlm.nih.gov/articles/PMC9578498/) | 问法接近「免疫治疗相关免疫浸润/TLS」 |
| ★★ | TLS 与胃癌预后、抗 PD-1 反应荟萃 | [38519621](https://pubmed.ncbi.nlm.nih.gov/38519621/) | 高 TLS 多与好预后相关 |
| ⚠ 反面证据 | NAC 干扰 EBV 胃癌 TLS 形成 | [42918766](https://pubmed.ncbi.nlm.nih.gov/42918766/) · Nat Commun 2026 | **化疗可能破坏 TLS**；写讨论时必提 |
| ⚠ | 肌层 TLS 与耐药/免疫抑制 | Nat Commun 相关文 | TLS 不是「越多一律越好」 |

你的分析应是：**治疗 → TLS 阳性率（IPTW 后）**，并在讨论引用「免疫化疗可能伴随 TLS/免疫浸润↑」与「单纯化疗可能干扰 TLS」两面证据。

---

## 建议你下载进 `papers/` 的最小包（4 篇）

1. **PMID 41450028** — IPTW + MPR（方法）  
2. **PMID 36934638**（PMC 开放）或 **38420853**（CMJ·PSM）— 化疗+免疫 vs 化疗 + TRG（问法）  
3. **PMID 24114855 / 25512144**（HER2）+ **31285589**（PD-L1 κ）— 一致性  
4. **PMID 36268179**（PMC 开放）— 新辅助免疫与 TLS/免疫浸润  

下好后告诉我文件名，再开对抗阅读（Q4/Q5/Q8）定分析树。
