# CSA-AKI 3-DB（去 SICdb）结果摘要

- 训练：MIMIC-IV + eICU；纯外验焦点：INSPIRE
- 特征：Allyn keep=1；DROP creatinine / urine_output
- 产出：`/mnt/sda/BlendedICU/data/csaaki_gongqian_42151996/Output_database_pooling_mimic_eicu/`
- 脚本：`prepare_csaaki_mimic_eicu_splits.py`、`run_csaaki_mimic_eicu_train.sh`、`csa3_*` units

## 主终点：患者级死亡 AUROC @ INSPIRE

| Arm | INSPIRE | eICU holdout | MIMIC holdout |
|-----|---------|--------------|---------------|
| B MIMIC-only | 0.9567 | 0.8385 | 0.9571 |
| D MIMIC+eICU pool | 0.9219 | 0.8069 | 0.9563 |
| D−B | **−0.0348** | −0.0316 | −0.0008 |

INSPIRE n=1040，deaths=32。

## 全臂

| Unit | INSPIRE | eICU holdout | MIMIC holdout |
|------|---------|--------------|---------------|
| A eICU solo | 0.8736 | 0.7384 | 0.9177 |
| B MIMIC solo | 0.9567 | 0.8385 | 0.9571 |
| C pretrain | 0.9544 | 0.8425 | 0.9596 |
| C eICU retrain | 0.7375 | 0.7943 | 0.7799 |
| D pool | 0.9219 | 0.8069 | 0.9563 |

## 判读

换掉 SICdb、改用更大的 eICU 入训后，**INSPIRE 上仍是 D < B**，池化叙事仍不阳性；C 微调同样伤外验。
