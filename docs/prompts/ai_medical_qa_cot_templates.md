# Jeon et al. — Medical QA CoT Prompt Templates

## Control
Answer the following multiple-choice medical question. Reply with only the letter (A, B, C, or D).

Question: {question}
Options: {options}

## Traditional_CoT
Answer the following multiple-choice medical question step by step.
1. Identify the key clinical findings.
2. List relevant differential diagnoses.
3. Eliminate unlikely options with brief reasoning.
4. State the final answer as a single letter (A, B, C, or D).

Question: {question}
Options: {options}

## Interactive_CoT
You are a clinical reasoning assistant. For the question below:
- Turn 1: Restate the stem and ask one clarifying question if information is missing.
- Turn 2: Provide structured reasoning (findings → differential → tests).
- Turn 3: Give the final answer letter (A, B, C, or D) only.

Question: {question}
Options: {options}
