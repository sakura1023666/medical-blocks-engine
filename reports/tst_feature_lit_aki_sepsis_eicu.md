# TST 特征文献检索 — sepsis-AKI / eICU（本课题）

- **日期**：2026-09-21
- **病种 / 库**：脓毒症相关 AKI 院内死亡；主库 eICU，外验 MIMIC
- **对标文献**：Yang et al. *Precision Clinical Medicine* 2025，pbaf003（两阶段 Transformer，eICU sepsis）
- **特征来源**：该文 Supplementary Table 1（`docs/literature_assets/pbaf003_supplemental_file.docx`）
- **落盘名单**：`configs/tst_feature_priority/aki_sepsis_eicu_pbaf003.R`（时序槽 ~75；不含原文 `_mask` / 医师专科 one-hot）
- **Methods 口径**：事先点名；不按覆盖率砍特征维；患者整段缺失 >30% 剔除
- **下一病**：禁止直接挂本 R 文件；须对本病重新检索后再建 `<disease>_<db>.R`
