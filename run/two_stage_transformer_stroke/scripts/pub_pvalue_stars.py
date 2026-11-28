"""TST 发表图显著性星号（全项目统一）。

常见写法:
  *   P < 0.05
  **  P < 0.01
  *** P < 0.001
  ns  P ≥ 0.05（可选；空串表示不标）
"""
from __future__ import annotations


def pub_pvalue_stars(p: float | None, *, show_ns: bool = True) -> str:
    """Map p-value to asterisk annotation for Comparison-of-Models bars."""
    try:
        pv = float(p)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return ""
    if pv != pv:  # NaN
        return ""
    if pv < 0.001:
        return "***"
    if pv < 0.01:
        return "**"
    if pv < 0.05:
        return "*"
    return "ns" if show_ns else ""


STAR_FOOTNOTE = r"$^{*}$ $P<0.05$, $^{**}$ $P<0.01$, $^{***}$ $P<0.001$"
