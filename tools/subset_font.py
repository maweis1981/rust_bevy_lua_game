#!/usr/bin/env python3
"""Build assets/fonts/game.ttf: Noto Sans subset with ASCII + the exact CJK
glyphs our Lua scripts draw.

WHY A SUBSET
------------
Bevy renders whatever glyphs the bundled font contains. A full CJK font is
15MB+ (a non-starter for the wasm bundle); a subset with just the strings we
ship is ~100KB. The trade-off: any NEW Chinese string added to a script must
also be added to STRINGS below, then re-run:

    python3 tools/subset_font.py

Requires: fonttools (pip install fonttools) and the Noto Sans CJK source
(apt-get install fonts-noto-cjk -> /usr/share/fonts/opentype/noto/*.ttc).
Missing glyphs render as blank boxes - same failure mode as before, but now
the fix is one line here instead of "CJK is impossible".
"""
import os
import string
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "fonts", "game.ttf")
TTC = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"

# Every non-ASCII string any script renders. ONE list = the font contract.
STRINGS = [
    # ponies.lua (Pony Parade UI, cloned from the reference video)
    "第关",
    "每种颜色1匹小马",
    "每行每列均有且仅有1匹小马",
    "小马不能相邻",
    "剩余",
    "剩余时间",
    "连胜",
    "清除",
    "坐标",
    "色盲模式",
    "恭喜过关",
    "挑战失败",
    "再试一次",
    "点击继续",
    "找马",
    "提示",
    "爱心用完了",
    "时间到了",
    "小马拼图",
    "、：！？·",
]

def sc_font_number(ttc: str) -> int:
    """Locate the Simplified-Chinese face inside the .ttc collection."""
    from fontTools.ttLib import TTCollection
    coll = TTCollection(ttc, lazy=True)
    for i, f in enumerate(coll.fonts):
        name = f["name"].getDebugName(4) or ""
        if "SC" in name:
            return i
    return 0

def main() -> None:
    if not os.path.exists(TTC):
        sys.exit(f"missing {TTC} (apt-get install fonts-noto-cjk)")
    text = string.printable + "".join(STRINGS)
    num = sc_font_number(TTC)
    subprocess.run(
        [
            sys.executable, "-m", "fontTools.subset", TTC,
            f"--font-number={num}",
            f"--text={text}",
            "--flavor=",  # plain ttf
            "--no-hinting",
            "--desubroutinize",
            f"--output-file={OUT}",
        ],
        check=True,
    )
    print(f"wrote {OUT} ({os.path.getsize(OUT)} bytes, font #{num} of {TTC})")

if __name__ == "__main__":
    main()
