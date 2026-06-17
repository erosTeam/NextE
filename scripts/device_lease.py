#!/usr/bin/env python3
"""Advisory device lease helper for agent-driven real-device validation.

This intentionally does NOT wrap or block a human's direct hdc usage. It is a
cooperation mechanism for Hermes/Codex/Claude agents so that automated tasks do
not fight over the single development device.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
import shlex
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

DEFAULT_DEVICE = "192.168.50.197:12345"
LEASE_ROOT = Path(os.environ.get("NEXTE_DEVICE_LEASE_DIR", Path.home() / ".hermes" / "device-leases"))


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def parse_ttl(value: str) -> int:
    raw = value.strip().lower()
    if raw.endswith("ms"):
        return max(1, int(raw[:-2]) // 1000)
    if raw.endswith("s"):
        return int(raw[:-1])
    if raw.endswith("m"):
        return int(raw[:-1]) * 60
    if raw.endswith("h"):
        return int(raw[:-1]) * 3600
    return int(raw)


def iso(ts: dt.datetime) -> str:
    return ts.astimezone().isoformat(timespec="seconds")


def parse_iso(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value)


def current_host() -> str:
    return socket.gethostname()


def process_exists(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def stale_reason(data: dict[str, Any] | None) -> str | None:
    """Return why a lease is stale before TTL expiry, if known.

    Backward compatibility note: historical leases store ``pid`` as the short-lived
    acquire command's PID. That PID is intentionally *not* treated as holder
    liveness. Only explicit holder_pid process-bound leases can become stale
    before TTL expiry.
    """
    if not data or data.get("status") != "active":
        return None
    try:
        if parse_iso(str(data["expires_at"])) <= utc_now():
            return None
    except Exception:
        return None
    holder_pid = data.get("holder_pid")
    if holder_pid is None:
        return None
    try:
        pid = int(holder_pid)
    except (TypeError, ValueError):
        return "holder pid invalid"
    holder_host = str(data.get("holder_host") or data.get("host") or "")
    if holder_host and holder_host != current_host():
        return None
    if not process_exists(pid):
        return "holder pid not running"
    return None


def device_key(device: str) -> str:
    return device.replace(":", "_").replace("/", "_")


def paths(device: str) -> tuple[Path, Path]:
    LEASE_ROOT.mkdir(parents=True, exist_ok=True)
    key = device_key(device)
    return LEASE_ROOT / f"{key}.json", LEASE_ROOT / f"{key}.lock"


def load_lease(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def save_lease(path: Path, data: dict[str, Any]) -> None:
    tmp = path.with_suffix(".json.tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    tmp.replace(path)


def is_active(data: dict[str, Any] | None) -> bool:
    if not data:
        return False
    if data.get("status") != "active":
        return False
    if stale_reason(data):
        return False
    try:
        return parse_iso(str(data["expires_at"])) > utc_now()
    except Exception:
        return False


def render(data: dict[str, Any] | None) -> str:
    if not data:
        return "no active lease"
    state = ""
    stale = stale_reason(data)
    if data.get("status") == "released":
        state = " (released)"
    elif stale:
        state = f" (stale: {stale})"
    elif not is_active(data):
        state = " (expired)"
    holder_pid = data.get("holder_pid")
    holder_host = data.get("holder_host")
    if holder_pid is None:
        liveness = "TTL-only / not process-bound"
    else:
        holder_host_text = holder_host or data.get("host") or "unknown-host"
        liveness = f"process-bound holder_pid={holder_pid} holder_host={holder_host_text}"
    fields = [
        f"lease_id: {data.get('lease_id')}{state}",
        f"device: {data.get('device')}",
        f"owner: {data.get('owner')}",
        f"project: {data.get('project', '')}",
        f"reason: {data.get('reason', '')}",
        f"liveness: {liveness}",
        f"acquire_pid: {data.get('acquire_pid', data.get('pid'))}",
        f"parent_pid: {data.get('parent_pid', '')}",
        f"host: {data.get('host')}",
        f"started_at: {data.get('started_at')}",
        f"expires_at: {data.get('expires_at')}",
    ]
    return "\n".join(fields)


def with_lock(device: str):
    lease_path, lock_path = paths(device)
    lock_f = lock_path.open("a+", encoding="utf-8")
    fcntl.flock(lock_f, fcntl.LOCK_EX)
    return lease_path, lock_f


def cmd_status(args: argparse.Namespace) -> int:
    lease_path, lock_f = with_lock(args.device)
    try:
        data = load_lease(lease_path)
        if args.json:
            print(json.dumps(data or {}, ensure_ascii=False, indent=2, sort_keys=True))
        else:
            print(render(data if is_active(data) else data))
        return 0 if is_active(data) else 1
    finally:
        fcntl.flock(lock_f, fcntl.LOCK_UN)
        lock_f.close()


def cmd_acquire(args: argparse.Namespace) -> int:
    lease_path, lock_f = with_lock(args.device)
    try:
        existing = load_lease(lease_path)
        if is_active(existing) and not args.force:
            print("device lease denied: device is already leased", file=sys.stderr)
            print(render(existing), file=sys.stderr)
            return 2
        now = utc_now()
        lease_id = f"{now.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}"
        data = {
            "device": args.device,
            "lease_id": lease_id,
            "owner": args.owner,
            "project": args.project,
            "reason": args.reason,
            "pid": os.getpid(),
            "acquire_pid": os.getpid(),
            "parent_pid": os.getppid(),
            "host": current_host(),
            "started_at": iso(now),
            "expires_at": iso(now + dt.timedelta(seconds=parse_ttl(args.ttl))),
            "status": "active",
            "forced": bool(args.force),
        }
        if args.holder_pid is not None:
            data["holder_pid"] = int(args.holder_pid)
            data["holder_host"] = current_host()
            data["liveness"] = "process"
        else:
            data["liveness"] = "ttl"
        save_lease(lease_path, data)
        print(lease_id)
        return 0
    finally:
        fcntl.flock(lock_f, fcntl.LOCK_UN)
        lock_f.close()


def cmd_renew(args: argparse.Namespace) -> int:
    lease_path, lock_f = with_lock(args.device)
    try:
        data = load_lease(lease_path)
        if not is_active(data) or data.get("lease_id") != args.lease:
            print("device lease renew denied: lease is not active or id mismatch", file=sys.stderr)
            print(render(data), file=sys.stderr)
            return 2
        data["expires_at"] = iso(utc_now() + dt.timedelta(seconds=parse_ttl(args.ttl)))
        data["renewed_at"] = iso(utc_now())
        save_lease(lease_path, data)
        print(render(data))
        return 0
    finally:
        fcntl.flock(lock_f, fcntl.LOCK_UN)
        lock_f.close()


def cmd_release(args: argparse.Namespace) -> int:
    lease_path, lock_f = with_lock(args.device)
    try:
        data = load_lease(lease_path)
        if not data:
            return 0
        if data.get("lease_id") != args.lease and not args.force:
            print("device lease release denied: lease id mismatch", file=sys.stderr)
            print(render(data), file=sys.stderr)
            return 2
        data["status"] = "released"
        data["released_at"] = iso(utc_now())
        save_lease(lease_path, data)
        return 0
    finally:
        fcntl.flock(lock_f, fcntl.LOCK_UN)
        lock_f.close()


def wait_for_lease(args: argparse.Namespace) -> dict[str, Any] | None:
    deadline = time.time() + args.wait
    while True:
        lease_path, lock_f = with_lock(args.device)
        try:
            data = load_lease(lease_path)
            if is_active(data) and data.get("lease_id") == args.lease:
                return data
            if args.wait <= 0 or time.time() >= deadline:
                print("device lease run denied: lease is not active or id mismatch", file=sys.stderr)
                print(render(data), file=sys.stderr)
                return None
        finally:
            fcntl.flock(lock_f, fcntl.LOCK_UN)
            lock_f.close()
        time.sleep(1)


def cmd_run(args: argparse.Namespace) -> int:
    if not args.command:
        print("device lease run requires a command after --", file=sys.stderr)
        return 2
    if not wait_for_lease(args):
        return 2
    if args.print_command:
        print("+ " + " ".join(shlex.quote(x) for x in args.command), file=sys.stderr)
    return subprocess.call(args.command)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Advisory real-device lease helper for NextE agent tasks")
    parser.add_argument("--device", default=DEFAULT_DEVICE, help=f"device target, default: {DEFAULT_DEVICE}")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("status")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("acquire")
    p.add_argument("--owner", required=True, help="agent/task owner, e.g. codex:v2next-ui")
    p.add_argument("--project", default="NextE")
    p.add_argument("--reason", default="agent device validation")
    p.add_argument("--ttl", default="30m")
    p.add_argument(
        "--holder-pid",
        type=int,
        help="optional long-running local process PID that holds the lease; if it exits, the lease is stale before TTL",
    )
    p.add_argument("--force", action="store_true", help="manual/user-approved override only")
    p.set_defaults(func=cmd_acquire)

    p = sub.add_parser("renew")
    p.add_argument("--lease", required=True)
    p.add_argument("--ttl", default="30m")
    p.set_defaults(func=cmd_renew)

    p = sub.add_parser("release")
    p.add_argument("--lease", required=True)
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_release)

    p = sub.add_parser("run")
    p.add_argument("--lease", required=True)
    p.add_argument("--wait", type=int, default=0, help="seconds to wait for matching active lease")
    p.add_argument("--print-command", action="store_true")
    p.add_argument("command", nargs=argparse.REMAINDER)
    p.set_defaults(func=cmd_run)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if getattr(args, "command", None) and args.command[:1] == ["--"]:
        args.command = args.command[1:]
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
