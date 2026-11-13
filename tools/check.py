#!/usr/bin/env python3
"""Run this project's checks, as check.toml describes them, and print a compact report.

The last line is always `CHECK: PASS` or `CHECK: FAIL (<stages>)`; the exit code is 0
only for a pass. This script knows nothing about the project's language: every stage is
a shell command from check.toml (see the comments there for each key).

Tiers:
  --tier quick   only the stages marked tier = "quick": seconds, for the inner loop
                 while implementing.
  --tier full    every stage (the default). The only run that says a change works.

Narrowing:
  --filter NAME  run only the stages that have a `filter` command, with {filter}
                 replaced by NAME: one test or test file, for red and green.
  --only A,B     run only the named stages.

Speed:
  Stages marked parallel = true that follow one another run side by side, --jobs at a
  time. A stage with `files` and {files} in its command is split over several processes
  by file, balanced by the times of earlier runs (.check/times.json).
  Every stage reports its wall time; one that takes long while using little CPU is
  flagged, because waiting (sleeps, real clocks, network) is what to remove first.

Pass cache:
  A passing run stores a fingerprint of every project file (tracked or untracked, not
  ignored), of the tool versions and environment variables check.toml names, under
  ~/.cache/check-pass/. A later run on exactly the same files prints [CACHED], the
  stored report and CHECK: PASS without running anything; a full pass also answers for
  any narrower run, except one with --filter. One changed byte and it runs for real.
  Failures are never cached. --fresh ignores the cache; --verbose always runs.

Usage:
  python3 tools/check.py                  # everything
  python3 tools/check.py --tier quick     # the quick stages
  python3 tools/check.py --filter name    # one test, where stages support it
  python3 tools/check.py --only unit      # one stage
  python3 tools/check.py --fresh          # run even if these exact files passed
  python3 tools/check.py --verbose        # every stage's full output
  python3 tools/check.py --list           # the stages and their tiers
"""
from __future__ import annotations

import argparse
import concurrent.futures
import glob
import hashlib
import json
import math
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    sys.exit("tools/check.py needs Python 3.11 or newer (for tomllib).")

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "check.toml"
STATE_DIR = ROOT / ".check"  # per-checkout state (shard times); git-ignored
TIMES_FILE = STATE_DIR / "times.json"
PASS_CACHE_KEEP = 200
DEFAULT_TIMEOUT = 600
DEFAULT_TAIL = 60
SUMMARY_LINES = 4  # at most this many summary lines under a passing stage (or one per process)
# A stage is flagged as "mostly waiting" from this much wall time, under this CPU share.
WAITING_MIN_SECONDS = 5.0
WAITING_CPU_SHARE = 0.25
# Below this much estimated work, splitting a stage over processes is not worth it.
MIN_SHARD_SECONDS = 2.0


# --- configuration ---------------------------------------------------------------------

def load_config() -> dict:
    if not CONFIG.is_file():
        sys.exit(f"{CONFIG.name} not found next to tools/: it lists the stages to run.")
    with CONFIG.open("rb") as f:
        config = tomllib.load(f)
    stages = config.get("stage", [])
    if not stages:
        sys.exit("check.toml has no [[stage]]: add at least one.")
    names = set()
    for stage in stages:
        for key in ("name", "run"):
            if not isinstance(stage.get(key), str) or not stage[key].strip():
                sys.exit(f"check.toml: every [[stage]] needs a `{key}` (in {stage.get('name', '?')}).")
        if stage["name"] in names:
            sys.exit(f"check.toml: two stages are named {stage['name']}.")
        names.add(stage["name"])
        if stage.get("tier", "full") not in ("quick", "full"):
            sys.exit(f"check.toml: stage {stage['name']}: tier must be \"quick\" or \"full\".")
        if "files" in stage and "{files}" not in stage["run"]:
            sys.exit(f"check.toml: stage {stage['name']} has `files` but no {{files}} in `run`.")
    return config


def default_jobs() -> int:
    try:
        return max(1, len(os.sched_getaffinity(0)))
    except AttributeError:  # not on Linux
        return max(1, os.cpu_count() or 1)


# --- running commands ------------------------------------------------------------------

def run_command(cmd: str, env: dict[str, str], timeout: float) -> dict:
    """Run a shell command in the project. Returns code, out, wall, cpu (None where the
    platform cannot say) and timed_out."""
    t0 = time.time()
    posix = os.name == "posix"
    with tempfile.TemporaryFile() as sink:
        proc = subprocess.Popen(cmd, shell=True, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                stdout=sink, stderr=subprocess.STDOUT, start_new_session=posix)
        timed_out = threading.Event()

        def kill() -> None:
            timed_out.set()
            try:
                if posix:
                    os.killpg(proc.pid, signal.SIGKILL)
                else:
                    proc.kill()
            except OSError:
                pass

        timer = threading.Timer(timeout, kill)
        timer.start()
        cpu = None
        try:
            if hasattr(os, "wait4"):
                # wait4 also reports the CPU time the command and its children used.
                _, status, usage = os.wait4(proc.pid, 0)
                code = os.waitstatus_to_exitcode(status)
                cpu = usage.ru_utime + usage.ru_stime
                proc.returncode = code
            else:
                code = proc.wait()
        finally:
            timer.cancel()
        sink.seek(0)
        out = sink.read().decode(errors="replace")
    return {"code": code, "out": out, "wall": time.time() - t0, "cpu": cpu,
            "timed_out": timed_out.is_set()}


def stage_env(stage: dict) -> dict[str, str]:
    env = dict(os.environ)
    env.update({str(k): str(v) for k, v in stage.get("env", {}).items()})
    return env


# --- splitting a stage by file ---------------------------------------------------------

def stage_files(stage: dict) -> list[str]:
    patterns = stage["files"]
    if isinstance(patterns, str):
        patterns = [patterns]
    found: set[str] = set()
    for pattern in patterns:
        for match in glob.glob(pattern, root_dir=ROOT, recursive=True):
            if (ROOT / match).is_file():
                found.add(Path(match).as_posix())
    return sorted(found)


def load_times() -> dict:
    try:
        data = json.loads(TIMES_FILE.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def estimates(files: list[str], known: dict) -> tuple[dict[str, float], bool]:
    """Seconds per file from earlier runs; a file never timed counts as the mean of the
    timed ones. With no times at all, file sizes stand in (second value False)."""
    timed = [float(known[f]) for f in files if f in known]
    if timed:
        mean = sum(timed) / len(timed)
        return {f: float(known.get(f, mean)) for f in files}, True
    return {f: float(max(1, (ROOT / f).stat().st_size)) for f in files}, False


def plan_shards(files: list[str], estimate: dict[str, float], in_seconds: bool, limit: int) -> list[list[str]]:
    """Spread files over at most `limit` processes of about equal work: the largest file
    first, each to the least loaded process."""
    count = min(limit, len(files))
    if in_seconds:
        count = min(count, max(1, math.ceil(sum(estimate.values()) / MIN_SHARD_SECONDS)))
    shards: list[list[str]] = [[] for _ in range(max(1, count))]
    load = [0.0] * len(shards)
    for f in sorted(files, key=lambda f: (-estimate[f], f)):
        i = load.index(min(load))
        shards[i].append(f)
        load[i] += estimate[f]
    return [sorted(s) for s in shards if s]


def save_times(stage: str, shards: list[list[str]], walls: list[float], estimate: dict[str, float]) -> None:
    """Remember about how long each file took: a process's time shared among its files in
    proportion to what was expected of them. Repeated runs sharpen it."""
    times = load_times()
    mine = {f: t for f, t in times.get(stage, {}).items() if (ROOT / f).is_file()}
    for files, wall in zip(shards, walls):
        total = sum(estimate[f] for f in files) or 1.0
        for f in files:
            mine[f] = round(wall * estimate[f] / total, 3)
    times[stage] = mine
    try:
        STATE_DIR.mkdir(exist_ok=True)
        TIMES_FILE.write_text(json.dumps(times, indent=1, sort_keys=True) + "\n")
    except OSError:
        pass


# --- the pass cache --------------------------------------------------------------------

def project_files() -> list[str]:
    """Every file that can change a check's result: tracked or untracked, not ignored.
    Outside a git checkout: everything outside hidden directories."""
    try:
        proc = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "-z"],
                              capture_output=True, cwd=ROOT, timeout=60)
        if proc.returncode == 0:
            names = set(n for n in proc.stdout.decode(errors="surrogateescape").split("\0") if n)
            return sorted(n for n in names if not n.startswith(".check/"))
    except (OSError, subprocess.TimeoutExpired):
        pass
    names = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        names += [(Path(dirpath).relative_to(ROOT) / f).as_posix() for f in filenames]
    return sorted(names)


def file_hashes() -> dict[str, str]:
    hashes = {}
    for name in project_files():
        path = ROOT / name
        if path.is_file():  # not: tracked but deleted
            hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def surroundings(config: dict) -> str:
    """What is not a project file but changes results: the tool versions and environment
    variables check.toml's [cache] names."""
    cache = config.get("cache", {})
    parts = []
    for cmd in cache.get("tools", []):
        try:
            proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=ROOT, timeout=60)
            parts.append(f"{cmd}\0{proc.returncode}\0{proc.stdout}{proc.stderr}")
        except (OSError, subprocess.TimeoutExpired) as e:
            parts.append(f"{cmd}\0{e}")
    for name in cache.get("env", []):
        parts.append(f"{name}={os.environ.get(name, '')}")
    return "\n".join(parts)


def fingerprint_of(hashes: dict[str, str], around: str) -> str:
    h = hashlib.sha256()
    for name in sorted(hashes):
        h.update(name.encode(errors="surrogateescape") + b"\0" + hashes[name].encode() + b"\n")
    h.update(around.encode())
    return h.hexdigest()


def pass_cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "check-pass"


def load_pass(fingerprint: str, scope: str, full_answers: bool) -> dict | None:
    try:
        scopes = json.loads((pass_cache_dir() / f"{fingerprint}.json").read_text())
        return scopes.get(scope) or (scopes.get("full") if full_answers else None)
    except (OSError, ValueError, AttributeError):
        return None


def store_pass(fingerprint: str, scope: str, seconds: float, report: list[str]) -> None:
    directory = pass_cache_dir()
    path = directory / f"{fingerprint}.json"
    try:
        directory.mkdir(parents=True, exist_ok=True)
        try:
            scopes = json.loads(path.read_text())
        except (OSError, ValueError):
            scopes = {}
        scopes[scope] = {"when": time.strftime("%Y-%m-%d %H:%M:%S"), "seconds": round(seconds, 1),
                         "full": scope == "full", "report": report}
        tmp = path.with_suffix(f".{os.getpid()}.tmp")
        tmp.write_text(json.dumps(scopes))
        os.replace(tmp, path)
        stored = sorted(directory.glob("*.json"), key=lambda f: f.stat().st_mtime)
        for old in stored[:-PASS_CACHE_KEEP]:
            old.unlink(missing_ok=True)
    except OSError:
        pass


# --- main ------------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tier", choices=["quick", "full"], default="full", help="quick: only the quick stages; full (default): every stage")
    ap.add_argument("--only", action="append", default=[], help="run only these stages (comma-separated, repeatable)")
    ap.add_argument("--filter", help="run only stages with a `filter` command, on tests matching this")
    ap.add_argument("--jobs", type=int, default=default_jobs(), help="how many commands run side by side (default: the CPUs available)")
    ap.add_argument("--fresh", action="store_true", help="run even when these exact files already passed (ignore the pass cache)")
    ap.add_argument("--verbose", action="store_true", help="print every stage's full output")
    ap.add_argument("--list", action="store_true", help="list the stages and exit")
    args = ap.parse_args()
    jobs = max(1, args.jobs)
    started = time.time()
    config = load_config()
    stages: list[dict] = config["stage"]

    if args.list:
        for stage in stages:
            marks = [stage.get("tier", "full")]
            marks += [m for m in ("parallel", "stop_on_fail") if stage.get(m)]
            marks += ["filter"] if stage.get("filter") else []
            marks += ["split by file"] if stage.get("files") else []
            print(f"{stage['name']:<16} {', '.join(marks):<40} {stage['run']}")
        return 0

    only = [n for chunk in args.only for n in chunk.split(",") if n]
    unknown = [n for n in only if n not in {s["name"] for s in stages}]
    if unknown:
        sys.exit(f"--only: no stage named {', '.join(unknown)} (see --list).")

    def chosen(stage: dict) -> bool:
        if only and stage["name"] not in only:
            return False
        if args.tier == "quick" and stage.get("tier", "full") != "quick":
            return False
        if args.filter and not stage.get("filter"):
            return False
        return True

    selected = [s for s in stages if chosen(s)]
    if not selected:
        sys.exit("No stage to run: " + ("no stage has a `filter` command in check.toml." if args.filter
                                         else "nothing is left by --only / --tier (see --list)."))

    # A stage whose tools are missing is skipped (if_missing = "skip") or fails.
    missing: dict[str, list[str]] = {}
    for stage in selected:
        lacking = [tool for tool in stage.get("needs", []) if shutil.which(tool) is None]
        if lacking:
            missing[stage["name"]] = lacking
    skipped = [s["name"] for s in selected if s["name"] in missing and s.get("if_missing") == "skip"]

    failed: list[str] = []
    report: list[str] = []  # what a later run on the same files prints from the pass cache

    def emit(line: str = "") -> None:
        print(line, flush=True)
        report.append(line)

    # Pass cache: these exact files may have passed this check (or the full one) already.
    is_full = args.tier == "full" and not only and not args.filter and not skipped
    scope = "full" if is_full else json.dumps([args.tier, sorted(only), args.filter, sorted(skipped)])
    use_cache = not args.verbose and config.get("cache", {}).get("enabled", True)
    before: dict[str, str] = {}
    around = ""
    if use_cache:
        before = file_hashes()
        around = surroundings(config)
        # A filtered run is answered only by the same filter's pass: a full pass does not
        # say that the filter matches any test.
        hit = None if args.fresh else load_pass(fingerprint_of(before, around), scope, not args.filter)
        if hit:
            what = "the full check" if hit.get("full") else "this check"
            print(f"[CACHED] these exact files passed {what} on {hit['when']} ({hit['seconds']}s). "
                  "Nothing was run; --fresh runs it again. Its report:")
            for line in hit["report"]:
                print(("    " + line).rstrip())
            print()
            print("CHECK: PASS")
            return 0

    times = load_times()
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=jobs)
    no_match: list[str] = []   # filtered stages whose runner said "no test matches"
    matched: list[str] = []

    def commands_for(stage: dict) -> tuple[list[str], list[list[str]], dict[str, float]]:
        """The stage's command(s): one, or one per process when it is split by file."""
        template = stage["filter"] if args.filter else stage["run"]
        template = template.replace("{filter}", shlex.quote(args.filter or "")).replace("{jobs}", str(jobs))
        if "files" not in stage or "{files}" not in template:
            return [template], [], {}
        files = stage_files(stage)
        if not files:
            return [], [], {}
        estimate, in_seconds = estimates(files, times.get(stage["name"], {}))
        shards = plan_shards(files, estimate, in_seconds, min(jobs, int(stage.get("max_processes", jobs))))
        return [template.replace("{files}", shlex.join(s)) for s in shards], shards, estimate

    def start(stage: dict) -> dict:
        commands, shards, estimate = commands_for(stage)
        env = stage_env(stage)
        timeout = float(stage.get("timeout", DEFAULT_TIMEOUT))
        return {"stage": stage, "shards": shards, "estimate": estimate, "commands": commands,
                "futures": [pool.submit(run_command, c, env, timeout) for c in commands]}

    def finish(running: dict) -> bool:
        """Wait for a stage, print its lines. Returns whether it passed."""
        stage = running["stage"]
        name = stage["name"]
        results = [f.result() for f in running["futures"]]
        if not results:
            emit(f"[FAIL] {name}: no file matches `files` ({stage['files']})")
            failed.append(name)
            return False
        if running["shards"] and not args.filter:
            save_times(name, running["shards"], [r["wall"] for r in results], running["estimate"])
        wall = max(r["wall"] for r in results)
        codes = [r["code"] for r in results]
        quiet_codes = stage.get("no_match_exit", []) if args.filter else []
        hits = [c for c in codes if c not in quiet_codes]
        # A runner that exits 0 when nothing matches: its output says whether a test ran.
        if args.filter and stage.get("filter_match") and all(c == 0 for c in codes) and not any(
                re.search(stage["filter_match"], r["out"], re.M) for r in results):
            hits = []
        ok = all(c == 0 for c in hits) and not any(r["timed_out"] for r in results)
        out = "\n".join(r["out"].rstrip("\n") for r in results if r["out"].strip())
        note = f", {len(results)} processes" if len(results) > 1 else ""
        if args.filter and not hits:
            no_match.append(name)
            emit(f"[NONE] {name} ({wall:.1f}s{note}): no test matches --filter={args.filter}")
            return True
        if args.filter:
            matched.append(name)
        if any(r["timed_out"] for r in results):
            note += f", timed out after {stage.get('timeout', DEFAULT_TIMEOUT)}s"
        elif not ok:
            note += f", exit {next(c for c in hits if c != 0)}"
        emit(f"[{'PASS' if ok else 'FAIL'}] {name} ({wall:.1f}s{note})")
        lines = out.splitlines()
        if args.verbose:
            for i, r in enumerate(results):
                if len(results) > 1:
                    emit(f"    $ {running['commands'][i]}")
                for line in r["out"].splitlines():
                    emit("    " + line)
        elif not ok:
            tail = int(stage.get("tail", DEFAULT_TAIL))
            if len(lines) > tail:
                emit(f"    ... {len(lines) - tail} earlier lines (--verbose shows all)")
            for line in lines[-tail:]:
                emit("    " + line)
        elif stage.get("summary"):
            # The runner's own summary line(s), so a report can quote them.
            found = [m.group(0) for m in re.finditer(stage["summary"], out, re.M)]
            for line in found[-max(SUMMARY_LINES, len(results)):]:
                emit("    " + line.strip())
        # Long but idle: the time went into waiting, which is what to remove first.
        cpus = [r["cpu"] for r in results]
        total_wall = sum(r["wall"] for r in results)
        if None not in cpus and total_wall >= WAITING_MIN_SECONDS and sum(cpus) < WAITING_CPU_SHARE * total_wall:
            emit(f"    note: {total_wall:.1f}s of wall time but {sum(cpus):.1f}s of CPU: this stage mostly waits "
                 "(sleeps, real-time clocks, network, locks, polling) instead of computing. That is the first thing to remove.")
        if not ok:
            failed.append(name)
        return ok

    # Stages run in check.toml's order; neighbours marked parallel run side by side.
    groups: list[list[dict]] = []
    for stage in selected:
        if stage.get("parallel") and groups and groups[-1][0].get("parallel"):
            groups[-1].append(stage)
        else:
            groups.append([stage])
    stopped_by = ""
    for group in groups:
        runnable = []
        for stage in group:
            name = stage["name"]
            if stopped_by:
                emit(f"[SKIP] {name} ({stopped_by} failed)")
            elif name in missing and stage.get("if_missing") == "skip":
                emit(f"[SKIP] {name} (not installed: {', '.join(missing[name])})")
            elif name in missing:
                emit(f"[FAIL] {name}: not installed: {', '.join(missing[name])}")
                failed.append(name)
                if stage.get("stop_on_fail"):
                    stopped_by = name
            else:
                runnable.append(stage)
        for running in [start(stage) for stage in runnable]:
            if not finish(running) and running["stage"].get("stop_on_fail") and not stopped_by:
                stopped_by = running["stage"]["name"]
    pool.shutdown()

    if args.filter and not matched and not failed:
        emit(f"[FAIL] filter: no test matches --filter={args.filter} in {', '.join(no_match)}")
        failed.append("filter")

    seconds = time.time() - started
    budget = config.get("budget", {}).get(args.tier)
    if budget and not only and not args.filter and seconds > float(budget):
        emit(f"note: the {args.tier} tier took {seconds:.1f}s; its budget is {budget}s (check.toml [budget]). "
             + ("Move slow tests to the full tier or make them faster: a slow quick tier stops being run."
                if args.tier == "quick" else "Look for the slowest stage above, and for one that mostly waits."))
    print()
    print(f"total: {seconds:.1f}s")
    if failed:
        print(f"CHECK: FAIL ({', '.join(failed)})")
        return 1
    # Remember the pass, unless a file changed while the check ran.
    if use_cache:
        after = file_hashes()
        if after == before:
            store_pass(fingerprint_of(before, around), scope, seconds, report)
        else:
            changed = sorted(n for n in set(before) | set(after) if before.get(n) != after.get(n))
            shown = ", ".join(changed[:5]) + (f" and {len(changed) - 5} more" if len(changed) > 5 else "")
            print(f"note: this pass was not stored in the pass cache: files changed while the check ran ({shown}). "
                  "If the check itself writes them, add them to .gitignore, or commit them if they belong "
                  "to the project (a lock file).")
    print("CHECK: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
