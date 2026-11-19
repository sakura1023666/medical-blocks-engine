# PubMed / 文献查重：COPD × JLCM+PAMM 轨迹 × 28 天院内死亡

日期：2026-11-19  
课题：`55_COPD/Prognosis_Trajectory_v2_42558177`  
方法口径：ICU 复合指标纵向轨迹 + Joint latent class mixed model（JLCM）+ PAMM；MIMIC 发现 → eICU 外验；结局 = 28-day in-hospital mortality  

## 判定规则（方法 × 指标 × 结局）

须**三者同时命中**才算「已发表、勿再跑」：

1. **方法**：JLCM / joint latent class 对**该复合指标**的日级/ICU 内轨迹（非单点 Cox/logistic）  
2. **指标**：本批 dual_safe 中的具体复合指标名（NLR、SII、HALP…）  
3. **结局**：COPD（或 ICU COPD）人群的 28 天 / 院内死亡  

仅静态基线 NLR/SII 与死亡关联、或 JLCM 用在体温/血红蛋白/血小板/FEV1 上 → **不算同构**，可跑。

## 对标方法论文（非指标撞车）

| 文献 | 暴露轨迹 | 人群 | 与本课题关系 |
|---|---|---|---|
| Frontiers CIMB fcimb-16-1871653 | **体温** | 脓毒症 MIMIC→eICU | **方法模板**（JLCM+PAMM+28d），非 COPD 复合指标 |
| Burn Trauma 2024 platelet JLCM | 血小板计数 | 脓毒症 MIMIC/eICU | 方法近邻，指标≠复合炎症指数、病种≠COPD |
| PLOS One 2025 Hb JLCM | 血红蛋白 | 老年脓毒症 MIMIC | 同上 |
| AJRCCM / ERJ FEV1 JLCM | FEV1 | 气道阻塞社区队列 | 病种近 COPD，暴露≠复合血检指标 |

## 复合炎症指标 × COPD × 死亡（方法不符 → 保留）

检索到多篇 **基线** NLR/PLR/SII/HALP 与 COPD 死亡/加重关联（NHANES、MIMIC 静态 Cox、SPIROMICS 等），**均非** ICU 日级 JLCM 轨迹 + PAMM + 双库外验。  
例：PLOS One 2024 MIMIC COPD 复合炎症与院内死亡；COPD 期刊 HALP/NLR 等营养炎症预测因子。

**结论：dual_safe 名单中，无指标因「方法×指标×结局」同构发表而必须剔除。**  
`config$trajectory_batch$exclude_published = character(0)`。

## 原则性失败（非查重，但停止重跑）

| 指标 | 原因 | 处理 |
|---|---|---|
| SII, PLR, GLR | JLCM ng=1 基线未收敛（conv=2） | `exclude_principle_fail` |
| LactAlb | eICU 合并后 n=0（INDEX_MIN_N） | 同上 |
| PHR | 发现集 PAUSE（阴性/异常） | 同上 |

## eICU partial（工程 bug，已修，须补跑）

ANLR / HALP / NLR：MIMIC 成功；eICU 曾因 `pred$subject` 部分匹配 `subject_id_num` + `pause_on_no_results` 未关 → 假失败。  
引擎已修；补跑 `--db eicu`，原则失败指标不重跑。
