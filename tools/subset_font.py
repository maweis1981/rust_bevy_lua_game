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
    # ant_clear.lua (Ant Art — reference-matched Chinese UI)
    "关卡",
    "解锁",
    "速度升级",
    "第关",
    "看广告",
    "取消槽位",
    "卡住了",
    "点一个颜色",
    "恭喜完成",
    "再玩一次",
    # gallery.lua (Midnight Gallery VN — every glyph the interrogation script draws)
    "·…、。《》一三上下不且东丢个为么义之九也了事亮人什仍从价会传但位住作你例侧保候值偏做停像儿先光全关再写凉凝几凶出击分别到制前剩加动包十半卖却卸去又反取句只叫可史名后吗吧听周和响哪喊嗓四回因在地场坏城堂墙墨壁声外多夜大天太失套女她好始子字存它安室导就屏己已布师带常幅幕年应座廊开弯当影往待很得心忽怎急您惜意懂我扇手才扭把护拖括拾拿挂指控掩撞收教散整料方旅无时明昨是晚普晴月有服末术机束条来林样格楚楼概正每没注消深清漏火灯灰点然熟物班球理用电男画留疙瘩白的皮监盘目盯相看真眼着睁睛瞎瞟瞬短离秒稳究空穿窃窗站等系索线练经结绕网美老者而脸腰自花苏薇行街衣表被裹西见视览觉计认记讲许证评话询该误说谁账货走赶起跑跟跳身车转辆边过近返还这进述通速造遍那都里钟钩锁错长门问间闷闸附陈隔静音馆鸡黑（），：？",

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
