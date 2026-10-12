#!/usr/bin/env python3
"""Copy fonts with new vertical metrics, so `line-height: normal` matches a device font.

usage: patch-metrics.py OUT_DIR ASCENT DESCENT FONT.ttf...
ASCENT and DESCENT are fractions of the em; the line gap is set to 0.
The fractions come from fitting the device's line heights (see calibrate.sh).
"""
import shutil
import sys
from pathlib import Path

from fontTools.ttLib import TTFont


def patch(source, out_dir, ascent, descent):
    font = TTFont(source)
    em = font['head'].unitsPerEm
    up, down = round(ascent * em), round(descent * em)
    font['hhea'].ascent, font['hhea'].descent, font['hhea'].lineGap = up, -down, 0
    os2 = font['OS/2']
    os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = up, -down, 0
    os2.usWinAscent, os2.usWinDescent = up, down
    os2.fsSelection |= 1 << 7  # USE_TYPO_METRICS
    font.save(out_dir / Path(source).name)


def main():
    out_dir = Path(sys.argv[1])
    ascent, descent = float(sys.argv[2]), float(sys.argv[3])
    out_dir.mkdir(parents=True, exist_ok=True)
    for source in sys.argv[4:]:
        patch(source, out_dir, ascent, descent)


if __name__ == '__main__':
    main()
