# Physclip 三卡计划（有 clip）

**更正**：旧结果无 clip；本轮五条规则 + 全体 ICU = **有 clip**。

## 今天开跑

| GPU | 第一棒 | 第二棒 |
|-----|--------|--------|
| 29 #0 | ACG+胆红素 (~16k) | SOFA≥1 (~36k) |
| 29 #1 | MARS (~21k) | ACG 纯酶学 (~41k) |
| 34 #0 | SOFA≥2 (~19k) | （协助全体 ICU） |

并行：CPU 准备全体 ICU `blendedlos_full`（symlink + split）。

## 明天

- 收完 sofa1 / acg 的 equaln·dataset·size·CI  
- 三卡切入 **全体 ICU**（流程同 EASL：四臂+extras，无 DROP）  
- 全体 ICU 训练量约 10–20×，墙钟约 **3–7 天**

## 产出目录

- `…/liver_dysfunction_<rule>_42151996/Output_physclip/`  
- `…/blendedlos_full_icu_42151996/Output_physclip/`  
- 日志：`/mnt/sda/liver_easl_paper_extras/logs_physclip_queue/`
