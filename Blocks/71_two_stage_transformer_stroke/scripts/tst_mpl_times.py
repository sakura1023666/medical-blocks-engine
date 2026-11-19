"""Shared matplotlib Times New Roman setup for TST publication figures."""
from __future__ import annotations

from pathlib import Path

_FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman.ttf",
    "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman_Bold.ttf",
    "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman_Italic.ttf",
    "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman_Bold_Italic.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-BoldItalic.ttf",
    r"C:\Windows\Fonts\times.ttf",
    r"C:\Windows\Fonts\timesbd.ttf",
    r"C:\Windows\Fonts\timesi.ttf",
    r"C:\Windows\Fonts\timesbi.ttf",
    "/mnt/c/Windows/Fonts/times.ttf",
    "/mnt/c/Windows/Fonts/timesbd.ttf",
    "/mnt/c/Windows/Fonts/timesi.ttf",
    "/mnt/c/Windows/Fonts/timesbi.ttf",
]


def setup_times_roman() -> str:
    """Force serif Times-family for PDF text (avoids DejaVuSans P0)."""
    import matplotlib
    from matplotlib import font_manager, pyplot as plt

    regular = None
    bold = None
    for p in _FONT_CANDIDATES:
        fp = Path(p)
        if not fp.exists():
            continue
        try:
            font_manager.fontManager.addfont(str(fp))
        except (OSError, RuntimeError, ValueError):
            continue
        name = font_manager.FontProperties(fname=str(fp)).get_name()
        low = fp.name.lower()
        if "bd" in low or "bold" in low:
            bold = name
        else:
            regular = name
    family = regular or bold or "Times New Roman"
    # 强制全家桶走衬线 Times，避免 tick/±/斜体回落到 DejaVuSans（QC P0）
    matplotlib.rcParams["font.family"] = "serif"
    matplotlib.rcParams["font.serif"] = [family, "Times New Roman", "Liberation Serif", "Nimbus Roman"]
    matplotlib.rcParams["font.sans-serif"] = [family, "Times New Roman", "Liberation Serif"]
    matplotlib.rcParams["axes.unicode_minus"] = False
    matplotlib.rcParams["axes.formatter.use_mathtext"] = False
    matplotlib.rcParams["mathtext.fontset"] = "custom"
    matplotlib.rcParams["mathtext.rm"] = family
    matplotlib.rcParams["mathtext.it"] = family
    matplotlib.rcParams["mathtext.bf"] = family
    matplotlib.rcParams["mathtext.default"] = "rm"
    matplotlib.rcParams["pdf.fonttype"] = 42
    matplotlib.rcParams["ps.fonttype"] = 42
    plt.rcParams.update(matplotlib.rcParams)
    return family
