# Liver inclusion rule screening (four databases)

Shared gates: age >= 18; ICU stay > 0.5 h; missing required labs excluded (not imputed).
Lab timing: first value at or after ICU admission, unless MARS early window (any TBil >=33 within 48 h).
Harmonized bilirubin is umol/L. Enzyme ULN operationalized as ALT/AST 40 U/L, ALP 115 U/L.
User gate for four-arm design: smallest database patients > 500.

## Patient counts (unique patients)

| rule_id | Amsterdam | MIMIC-IV | eICU | HiRID | min | pass>500 |
|---|---:|---:|---:|---:|---:|:---:|
| acg_enzyme_ge2uln | 3323 | 11222 | 18369 | 5152 | 3323 | YES |
| acg_mild_plus_bili12 | 732 | 5373 | 7241 | 1796 | 732 | YES |
| apasl_lab_bili5_inr15 | 73 | 1925 | 1352 | 185 | 73 | NO |
| easl_dili_lab_mild | 1223 | 5980 | 7978 | 2060 | 1223 | YES |
| hys_law_lab | 293 | 2994 | 3198 | 810 | 293 | NO |
| mars_early_bili33_48h | 852 | 6824 | 8435 | 1892 | 852 | YES |
| sofa_liver_ge1 | 1590 | 10025 | 15930 | 3267 | 1590 | YES |
| sofa_liver_ge2 | 681 | 6204 | 7881 | 1752 | 681 | YES |
| sofa_liver_ge3 | 100 | 2019 | 1648 | 385 | 100 | NO |
| sofa_liver_ge4 | 27 | 955 | 631 | 128 | 27 | NO |
| tbili_ge3_mgdl | 284 | 3991 | 4144 | 968 | 284 | NO |

## Rule definitions and references

### sofa_liver_ge1

- Definition: SOFA liver item >=1 (first TBil >=20 umol/L)
- Predicate: `first_bili IS NOT NULL AND first_bili >= 20`
- Labs: complete_lab=first_bili
- Reference: Vincent et al. Crit Care Med 1998; SOFA liver bilirubin bands

### sofa_liver_ge2

- Definition: SOFA liver item >=2 (first TBil >=33 umol/L) [current main]
- Predicate: `first_bili IS NOT NULL AND first_bili >= 33`
- Labs: complete_lab=first_bili
- Reference: Vincent et al. Crit Care Med 1998; same cut as current study

### mars_early_bili33_48h

- Definition: MARS early hyperbilirubinemia: TBil >=33 umol/L within first 48 h
- Predicate: `first_time_bili33 IS NOT NULL AND first_time_bili33 <= 48 * 3600 * 1e6`
- Labs: complete_lab=any bili in window
- Reference: Jager et al. Front Med 2022 (MARS); TBil >=33 umol/L (>=2 mg/dL) in first 2 ICU days

### tbili_ge3_mgdl

- Definition: First TBil >=3 mg/dL (>=51.3 umol/L)
- Predicate: `first_bili IS NOT NULL AND first_bili >= 51.3`
- Labs: complete_lab=first_bili
- Reference: Common ICU hyperbilirubinemia threshold above SOFA-2; 3 mg/dL x17.1

### sofa_liver_ge3

- Definition: SOFA liver item >=3 (first TBil >=102 umol/L)
- Predicate: `first_bili IS NOT NULL AND first_bili >= 102`
- Labs: complete_lab=first_bili
- Reference: Vincent et al. Crit Care Med 1998; SOFA liver score 3 (~6 mg/dL)

### sofa_liver_ge4

- Definition: SOFA liver item >=4 (first TBil >=204 umol/L)
- Predicate: `first_bili IS NOT NULL AND first_bili >= 204`
- Labs: complete_lab=first_bili
- Reference: Vincent et al. Crit Care Med 1998; SOFA liver score 4 (~12 mg/dL)

### apasl_lab_bili5_inr15

- Definition: APASL lab gate only: first TBil >=5 mg/dL AND first INR >=1.5
- Predicate: `first_bili IS NOT NULL AND first_inr IS NOT NULL AND first_bili >= 85.5 AND first_inr >= 1.5`
- Labs: complete_lab=bili+INR
- Reference: Sarin et al. Hepatol Int 2019 (APASL ACLF update). NOT full ACLF (no ascites/HE)

### acg_enzyme_ge2uln

- Definition: ACG-style enzyme elevation: first ALT or AST >=2xULN (ULN=40)
- Predicate: `(first_alt IS NOT NULL OR first_ast IS NOT NULL) AND ((first_alt >= 80) OR (first_ast >= 80))`
- Labs: complete_lab=ALT or AST
- Reference: Kwo et al. Am J Gastroenterol 2017 ACG Clinical Guideline (enzyme bands); ULN 40 U/L operationalized

### acg_mild_plus_bili12

- Definition: ACG enzyme >=2xULN AND first TBil >1.2 mg/dL (>=20 umol/L)
- Predicate: `first_bili IS NOT NULL AND first_bili >= 20 AND ((first_alt >= 80) OR (first_ast >= 80))`
- Labs: complete_lab=bili+(ALT or AST)
- Reference: Med Intensiva 2024 secondary HI comparison (ACG3-like); SOFA-1.2 bili + ACG enzyme band

### easl_dili_lab_mild

- Definition: EASL/DILI lab gate: first ALT >=5xULN OR ALP >=2xULN (ULN ALT40/ALP115)
- Predicate: `(first_alt >= 200) OR (first_alp >= 230)`
- Labs: complete_lab=ALT or ALP
- Reference: EASL CPG Drug-induced liver injury 2019; International DILI Expert Working Group lab thresholds

### hys_law_lab

- Definition: Hy's-law lab pattern: (ALT or AST >=3xULN) AND first TBil >=2xULN (>=34 umol/L)
- Predicate: `first_bili IS NOT NULL AND first_bili >= 34 AND ((first_alt >= 120) OR (first_ast >= 120))`
- Labs: complete_lab=bili+(ALT or AST)
- Reference: FDA Guidance Drug-Induced Liver Injury 2009 (Hy's law laboratory pattern); not full causality
