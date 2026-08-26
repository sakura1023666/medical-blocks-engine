### Task 8: 升级 Cursor 规则

**Files:**
- Modify: `.cursor/rules/pub_figure_image_information.mdc`

- [ ] **Step 1: 在「铁律」中新增第 7 条**

```markdown
7. **图面标注必录**：图上可见的关键数字/标注必须写入 `## 图面说明`（建议小标题「图上标注」），包括但不限于：
   - RCS：`P-overall` / `P for overall`、`P-non-linear` / `P for nonlinear`、竖线 cutoff
   - KM：Log-rank P、二分 cutoff
   - Forest：Overall 与各亚组效应量(95%CI)、P for interaction
   - ROC：AUC、CI、Youden、灵敏度/特异度（图上有则写）
   - maxstat：图上切点
   - Flowchart：逐步 n 与排除人数
   数字只来自可收获产物；缺则写「未收获」；**禁止编造**。其它图种若图上有数字，同理。
```

- [ ] **Step 2: 检查清单增加 RCS/KM/Forest 标注项**

- [ ] **Step 3: 反例增加「RCS 图上有 P/cutoff，md 只有空话」**

- [ ] **Step 4: 确认 `alwaysApply: true`**

- [ ] **Step 5: Commit（仅当用户要求）**

---

