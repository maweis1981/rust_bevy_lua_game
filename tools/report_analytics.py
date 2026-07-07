#!/usr/bin/env python3
"""Playtest debrief for the local analytics log (plan M1: data-driven tuning).

Reads ~/.hollowlullaby/analytics.log (TSV: unix_ts \t event \t value) and prints,
per game, the session table the tuning loop needs: session lengths (from *_start
to *_over), score distribution, death-cause mix and fusion/combo depth.

Usage: python3 tools/report_analytics.py [path/to/analytics.log]
"""

import statistics
import sys
from pathlib import Path

LOG = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".hollowlullaby" / "analytics.log"

GAMES = {
    "forge": {"start": "forge_start", "over": "forge_over",
              "counters": ["forge_merge", "forge_combo", "forge_eaten", "forge_escape"]},
    "fireflies": {"start": "fireflies_start", "over": "fireflies_over",
                  "counters": ["fireflies_ring", "fireflies_web_loss"]},
}


def fmt_dist(xs):
    if not xs:
        return "n=0"
    return (f"n={len(xs)}  min {min(xs):.0f}  median {statistics.median(xs):.0f}  "
            f"max {max(xs):.0f}  mean {statistics.mean(xs):.1f}")


def main():
    if not LOG.exists():
        sys.exit(f"no log at {LOG} — play a few rounds first")
    rows = []
    for line in LOG.read_text().splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0].isdigit():
            rows.append((int(parts[0]), parts[1], float(parts[2]) if len(parts) > 2 and parts[2] else None))

    for game, spec in GAMES.items():
        sessions, scores = [], []
        counts = {c: 0 for c in spec["counters"]}
        open_start = None
        per_session = {c: [] for c in spec["counters"]}
        cur = {c: 0 for c in spec["counters"]}
        for ts, ev, val in rows:
            if ev == spec["start"]:
                open_start = ts
                cur = {c: 0 for c in spec["counters"]}
            elif ev == spec["over"]:
                if open_start is not None:
                    sessions.append(ts - open_start)
                    for c in spec["counters"]:
                        per_session[c].append(cur[c])
                    open_start = None
                if val is not None:
                    scores.append(val)
            elif ev in counts:
                counts[ev] += 1
                cur[ev] += 1

        print(f"== {game} ==")
        print(f"  sessions (s): {fmt_dist(sessions)}")
        print(f"  final score : {fmt_dist(scores)}")
        for c in spec["counters"]:
            print(f"  {c:<18} total {counts[c]:>5}   per-session {fmt_dist(per_session[c])}")
        print()


if __name__ == "__main__":
    main()
