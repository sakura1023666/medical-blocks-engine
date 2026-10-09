# 疾病分层数值门控 — 急性胰腺炎 WPR 双库轨迹

- 本课题主分层不是 AP 指南分期（BISAP/Ranson/坏死），那些列已列入 `disease_vars`。
- 主结局与已发表 MIMIC 单库一致：入院/ICU 后 28 天院内死亡。
- MIMIC：`death_within_hosp_28days` → `survival_28d`；非事件行政截尾至第 28 天。
- eICU：`hospdischargestatus==Expired` 且 `hosplosday<=28` → 事件；非事件同样截尾至第 28 天。
- 两库同一公式、同一切点、同一时间窗；eICU 缺预后/打标的 stay 已剔除，不改口径。
- 年龄亚组：65 岁二分类（PMID 36205509；BMC Gastroenterology 2023 大型 AP 队列常用老年界）。
- 轨迹类别：锁定 MIMIC 已发表 WPR `ng = 2`，eICU 外验用同一类别数。
