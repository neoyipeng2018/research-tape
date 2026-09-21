#!/usr/bin/env bash
# Self-check for lane.py: the streak, what the tape records, and the alarm that fails the
# run. SPEC.md §9. The alarm is the only thing standing between a dead lane and another
# ten-day outage, so it is checked as a process, exit code and all.
set -u
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, os, subprocess, sys, tempfile
sys.path.insert(0, "scripts")
from lane import LANES, contributed, dead_days, missing

fails = 0
def check(name, cond, why=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {why}"))
    fails += 0 if cond else 1

c = tempfile.mkdtemp()
def day(name, sources):
    with open(os.path.join(c, name), "w") as f:
        json.dump([{"source": s} for s in sources], f)

# The streak, per lane. September 2026: arXiv dead, SSRN carrying the tape alone.
day("2026-09-21.json", ["SSRN"]); day("2026-09-20.json", ["SSRN"])
day("2026-09-19.json", ["SSRN", "arXiv"])
check("a lane's streak stops at the last day it produced anything", dead_days(c, "arXiv") == 2,
      dead_days(c, "arXiv"))
check("the other lane, same counter, no streak", dead_days(c, "SSRN") == 0, dead_days(c, "SSRN"))
check("a missing candidates dir is not a crash", dead_days(c + "/nope", "arXiv") == 0)

# The fetchers count history only; the final check counts today too. Same function, one arg.
check("today can be excluded, for a fetcher that has not written it yet",
      dead_days(c, "SSRN", today="2026-09-21") == 0 and dead_days(c, "arXiv", today="2026-09-21") == 1,
      (dead_days(c, "SSRN", today="2026-09-21"), dead_days(c, "arXiv", today="2026-09-21")))

with open(os.path.join(c, "2026-09-18.json"), "w") as f:
    f.write("{ truncated")
check("an unreadable day breaks the chain rather than extending it", dead_days(c, "arXiv") == 2)

# What the tape records, and what the page reads back off it.
pool = [{"source": "SSRN"}, {"source": "SSRN"}]
check("lanes are recorded in a fixed order, not the pool's", contributed(pool) == ["SSRN"])
check("both lanes present is both recorded",
      contributed(pool + [{"source": "arXiv"}]) == ["arXiv", "SSRN"])
check("a day with no lanes at all records none", contributed([]) == [])
check("a tape names the lane that was missing", missing({"lanes": ["SSRN"]}) == ["arXiv"])
check("a full tape names none", missing({"lanes": list(LANES)}) == [])
# The ten tapes already committed have no field. They were not observed, and a backfill would
# be a claim about days nobody watched.
check("a tape written before the field says nothing rather than guessing", missing({}) == [])

# The alarm. Exit code is the whole mechanism: it is what turns the run red and mails.
def alarm(max_dead=3):
    return subprocess.run([sys.executable, "scripts/lane.py", "--candidates", c,
                           "--max-dead", str(max_dead)], capture_output=True, text=True)

check("two dead days is a blip and stays quiet", alarm().returncode == 0, alarm().stderr)
day("2026-09-22.json", ["SSRN"])   # arXiv now three days dead
r = alarm()
check("three dead days fails the run", r.returncode == 1, r.stderr)
check("and says which lane, on the run summary", "::error::arXiv" in r.stderr, r.stderr)
check("the lane still running is not blamed", "::error::SSRN" not in r.stderr, r.stderr)
check("a missing candidates dir never fails the run",
      subprocess.run([sys.executable, "scripts/lane.py", "--candidates", c + "/nope"]).returncode == 0)

sys.exit(1 if fails else 0)
PY
rc=$?
[ $rc -eq 0 ] && echo "all ok"
exit $rc
