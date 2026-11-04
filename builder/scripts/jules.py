#!/usr/bin/env python3
"""Jules sessions for the weekly cssdm bump: review every bump PR, propose a fix when one fails.

Same scheme as fmu1337/sourcemod-css34 (builder/scripts/jules.py):

    jules.py prompt review|fix --old SHA --new SHA --rev N [--context FILE]
        The prompt for a read-only review of a bump PR, or for a minimal fix of a bump
        that could not be applied (the check log goes in --context).
    jules.py start --title T --prompt-file F --branch B [--auto-pr] [--skip-if-exists]
        Create a session on this repository starting from branch B. Without --auto-pr
        Jules opens no pull request (review); with it, a finished change becomes Jules'
        own PR (fix). Prints {"name": ..., "url": ..., "existing": bool}.
    jules.py wait <session name> [--timeout S] [--interval S] [--out FILE]
        Poll until the session ends (or the timeout), then write a markdown report.

Jules never gets a token of this repository, starts from a branch it cannot push to unless
it opens its own PR, and nothing it produces is merged automatically.

Env: JULES_API_KEY (start/wait), JULES_API_URL (default https://jules.googleapis.com/v1alpha),
GITHUB_REPOSITORY (default fmu1337/sm34.cssdm).
"""
import argparse
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request

TERMINAL = {"COMPLETED", "FAILED", "AWAITING_USER_FEEDBACK", "AWAITING_PLAN_APPROVAL", "PAUSED"}
COMMENT_LIMIT = 60000  # GitHub comments are capped at 65536 characters

SAFETY = """Hard rules (a human merges everything; CI must stay meaningful):
- Never change .github/, testing/, builder/scripts/, or any check, test or CI step, and
  never weaken, skip or delete a check to make something pass.
- Never change builder/patches/2.1/1.patch (it is for the old upstream tree), release tags
  or published releases.
- Never guess gamedata: a CS:S v34 offset or signature must come from the v34 server binary
  (symbols, disassembly) or be left out and reported.
- Keep changes minimal and explain each one. If you are not sure a change is right, do not
  make it: describe it in your report instead."""


def prompt(kind, old, new, rev, context):
    compare = "https://github.com/alliedmodders/cssdm/compare/{}...{}".format(old, new)
    head = (
        "Repository fmu1337/sm34.cssdm builds CS:S Deathmatch (cssdm) for Counter-Strike: Source v34 "
        "(SDK episode1, 32-bit Linux) against fmu1337/sourcemod-css34's SourceMod 1.11, 1.12 and 1.13. "
        "Upstream alliedmodders/cssdm is the `cssdm` submodule; builder/run/build.py applies the base patch "
        "that builder/run/config.json selects for the upstream revision (builder/patches/2.1/2.patch for "
        "git325 and later: AMBuild 2 + hl2sdk-manifests for episode1, C++17, ep1 ConVar/ClientCommand shims, "
        "plugins kept compilable with SourceMod 1.11's spcomp), then ships the v34 gamedata from "
        "builder/patches/2.1/gamedata/ instead of upstream's. Plugins must compile with spcomp 1.11 "
        "(line-sm11-oldstable) as well as 1.12 / 1.13.\n\n"
        "This bump moves the submodule from {old} to {new} (git{rev}). Upstream diff: {compare}\n"
    ).format(old=old, new=new, rev=rev, compare=compare)
    ctx = ""
    if context:
        ctx = "\nContext from the bump workflow:\n\n" + Path(context).read_text(errors="replace")[-30000:] + "\n"
    if kind == "review":
        task = (
            "\nTASK (read-only review): the branch you start on already carries the bump; CI runs on its PR. "
            "Do NOT modify any file and do NOT create commits or pull requests. Go through every upstream commit "
            "between the two commits and how it meets this repository:\n"
            "1. files builder/patches/2.1/2.patch changes (its diff --git headers);\n"
            "2. gamedata lookups (GetOffset/GetMemSig/GetKeyValue, plugin GameData / SDKConf) against "
            "builder/patches/2.1/gamedata/cssdm.games.txt;\n"
            "3. episode1 differences (ConVar, CCommand/ClientCommand, SourceHook, engine interfaces);\n"
            "4. plugin APIs newer than SourceMod 1.11 (spcomp 1.11 must still compile them);\n"
            "5. build changes (AMBuildScript, AMBuilder, PackageScript, configure.py, buildbot/, hl2sdk-manifests).\n"
            "Answer with a short report in this shape:\n"
            "## Upstream commits and what they mean for CS:S v34 (one line each)\n"
            "## Risks and what to check on a test server\n"
            "## Changes needed in this repository (file and what), or \"nothing to change\"\n"
        )
    else:
        task = (
            "\nTASK (fix): the automated bump could not be applied; the workflow log is below. Make the "
            "smallest change that lets the bump through, on a new branch from master:\n"
            "1. move the `cssdm` submodule to {new};\n"
            "2. where builder/patches/2.1/2.patch no longer applies, adapt the patch to the new upstream code "
            "(keep what each hunk is for), regenerating it from a patched checkout with git diff;\n"
            "3. if the new code looks up gamedata the v34 file lacks, add CS:S v34 values only when you can show "
            "where they come from; otherwise leave them out and report.\n"
            "Only the `cssdm` submodule pointer, builder/patches/2.1/2.patch, builder/patches/2.1/gamedata/** and "
            "builder/run/config.json may change. In the PR description list every hunk you changed and why. If "
            "you cannot fix it safely, make no code change and explain what blocks it.\n"
        ).format(new=new)
    return head + task + "\n" + SAFETY + "\n" + ctx


def api(method, path, body=None):
    key = os.environ.get("JULES_API_KEY", "")
    if not key:
        raise SystemExit("FAIL: JULES_API_KEY is not set")
    base = os.environ.get("JULES_API_URL", "https://jules.googleapis.com/v1alpha").rstrip("/")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + "/" + path.lstrip("/"), data=data, method=method,
                                 headers={"X-Goog-Api-Key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:500]
        raise SystemExit("FAIL: Jules API {} {}: HTTP {} {}".format(method, path, err.code, detail))


def source():
    return "sources/github/" + os.environ.get("GITHUB_REPOSITORY", "fmu1337/sm34.cssdm")


def find(title, pages=3):
    """An existing session with exactly this title (the newest pages only), or None."""
    token = ""
    for _ in range(pages):
        page = api("GET", "sessions?pageSize=100" + ("&pageToken=" + token if token else ""))
        for session in page.get("sessions", []):
            if session.get("title") == title:
                return session
        token = page.get("nextPageToken", "")
        if not token:
            return None
    return None


def start(title, prompt_text, branch, auto_pr, skip_if_exists=False):
    if skip_if_exists:
        existing = find(title)
        if existing:
            return {"name": existing.get("name", ""), "url": existing.get("url") or "", "existing": True}
    body = {"title": title, "prompt": prompt_text,
            "sourceContext": {"source": source(), "githubRepoContext": {"startingBranch": branch}}}
    if auto_pr:
        body["automationMode"] = "AUTO_CREATE_PR"
    session = api("POST", "sessions", body)
    name = session.get("name") or "sessions/" + str(session.get("id", ""))
    return {"name": name, "url": session.get("url") or "", "existing": False}


def activities(name):
    out, token = [], ""
    while True:
        page = api("GET", "{}/activities?pageSize=100{}".format(name, "&pageToken=" + token if token else ""))
        out.extend(page.get("activities", []))
        token = page.get("nextPageToken", "")
        if not token:
            return out


def wait(name, timeout, interval):
    deadline = time.monotonic() + timeout
    session = api("GET", name)
    while session.get("state") not in TERMINAL and time.monotonic() < deadline:
        time.sleep(interval)
        session = api("GET", name)
    state = session.get("state", "UNKNOWN")
    messages = [a["agentMessaged"].get("agentMessage", "") for a in activities(name) if "agentMessaged" in a]
    prs = [o["pullRequest"]["url"] for o in session.get("outputs", []) if o.get("pullRequest", {}).get("url")]
    url = session.get("url") or ""
    link = "[session]({})".format(url) if url else "session `{}`".format(name)
    lines = ["**Jules** ({}): state `{}`{}.".format(
        link, state, "" if state in TERMINAL else " (still running when the workflow stopped waiting)")]
    for pr in prs:
        lines.append("Jules opened {} (review it like any PR; nothing merges automatically).".format(pr))
    lines.append("")
    lines.append(messages[-1].strip() if messages else "_No report from Jules yet; see the session._")
    text = "\n".join(lines) + "\n"
    if len(text) > COMMENT_LIMIT:
        text = text[:COMMENT_LIMIT] + "\n\n… (truncated; full report in the session)\n"
    return state, text


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prompt")
    p.add_argument("kind", choices=("review", "fix"))
    p.add_argument("--old", required=True)
    p.add_argument("--new", required=True)
    p.add_argument("--rev", required=True)
    p.add_argument("--context")
    p = sub.add_parser("start")
    p.add_argument("--title", required=True)
    p.add_argument("--prompt-file", required=True, type=Path)
    p.add_argument("--branch", required=True)
    p.add_argument("--auto-pr", action="store_true")
    p.add_argument("--skip-if-exists", action="store_true",
                   help="reuse a session with the same title instead of starting another")
    p = sub.add_parser("wait")
    p.add_argument("name")
    p.add_argument("--timeout", type=float, default=2400)
    p.add_argument("--interval", type=float, default=60)
    p.add_argument("--out", type=Path)
    args = parser.parse_args()
    if args.cmd == "prompt":
        sys.stdout.write(prompt(args.kind, args.old, args.new, args.rev, args.context))
    elif args.cmd == "start":
        print(json.dumps(start(args.title, args.prompt_file.read_text(), args.branch, args.auto_pr,
                               args.skip_if_exists)))
    else:
        state, text = wait(args.name, args.timeout, args.interval)
        if args.out:
            args.out.write_text(text)
        else:
            sys.stdout.write(text)
        print("state=" + state, file=sys.stderr)


if __name__ == "__main__":
    main()
