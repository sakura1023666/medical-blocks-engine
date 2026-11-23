# SSD LPA × 心理网络 × 平行竞争中介

- 客户：王玉贤  
- 文献方法源：Ma 2026 *Acta Psychologica*（PMID 42214160）— 对抗阅读 `paper_060`  
- 决策树：`Decisiontree/decision_tree_ssd_lpa_network_mediation.md`  
- 数据：`G:/02block_result/63_SSD/LPA_Network_Mediaton_42214160/data/201804_complete.csv`（N=699）

## 方法块落点（禁止大杂烩目录）

| 步骤 | Block |
|---|---|
| 量表计分（李克特映射） | `Blocks/02_data_clean/03block_psychometrics_scale_score.R` |
| LPA（DAS1–12） | `Blocks/83_latent_profile/01block_latent_profile_tidylpa.R` |
| CFA 区分效度 | `Blocks/62_sem_chain_mediation_full/10block_sem_cfa_discriminant.R` |
| 平行竞争中介 + 间接效应差 | `Blocks/20_mediation/14block_parallel_competing_mediation.R` |
| 按剖面分层网络 | `Blocks/50_complex_network/06block_complex_network_profile_batch.R` |
| ROC + DCA | `Blocks/13_roc/03block_clinical_threshold_dca.R` |

## 运行

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/ssd_lpa_network_mediation/run_ssd_lpa_network_mediation.R
```

冒烟（少 bootstrap）：

```bash
SSD_MED_SIMS=50 SSD_NET_BOOTS=20 SMOKE_NO_FEISHU=1 \
  "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/ssd_lpa_network_mediation/run_ssd_lpa_network_mediation.R
```

Config：`configs/study_ssd_lpa_network_mediation/config_ssd_lpa_network_mediation.R`  
（同步副本在课题 `G:/.../configs/`）

## 门控提醒

1. LPA 重扫 K；极小类 `min_class_n=80` / `min_class_prop=0.05`  
2. 剖面 n 过小 → 该层网络跳过  
3. 中介调整集预声明：age/sex/education/marriage/income/livingsite  
4. 横断面：Methods 禁止写成已证因果  
5. 主分析全样本；SSD=yes 作分层/敏感性（另开）

## 发表收口（每次必跑；已挂主入口末尾）

`run_ssd_lpa_network_mediation.R` 成功结束后自动调用 `ssd_finalize_summary_delivery()`（`R/ssd_lpa_network_mediation_pub.R`）：

- 展示层禁下划线 + Times New Roman（`pub_delivery_scrub_display`）
- 小数位锁 `ssd_pub_digits()`（对齐 Ma 2026：OR/CI/P 三位；%≤2；Entropy/AUC/ACME 三位）
- 写 `Methods_statistical_analysis.md` + `Methods_software_versions.txt`（**无日期戳**）
- `summary_results/` 白名单 prune：只留 `Figures/` `Tables/` Methods 两件套 + 中期 PDF

手工补跑：

```bash
Rscript run/ssd_lpa_network_mediation/finalize_ssd_summary_delivery.R
```

中期 PDF（客户：王玉贤；分析日期：无）在 Nature P0 清零后按 `Aiya-NB004-midterm-report` 出，再 prune 一次。
