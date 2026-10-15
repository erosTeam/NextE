#!/usr/bin/env python3
"""Device lease and checked-protocol gate for NextE device validation."""
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


LEASE_ROOT = Path(
    os.environ.get(
        "HARMONY_DEVICE_LEASE_DIR",
        os.environ.get("NEXTE_DEVICE_LEASE_DIR", Path.home() / ".hermes" / "device-leases"),
    )
)
PROJECT_ROOT = Path(__file__).resolve().parent.parent
CHECKED_PROTOCOL_RUNNER = (
    Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    / "skills"
    / "harmony-run-device-diagnostics"
    / "scripts"
    / "run_device_protocol.py"
).resolve()
CHECKED_RECORDING_RUNNER = (
    Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    / "skills"
    / "harmony-run-device-diagnostics"
    / "scripts"
    / "capture_transition_recording.mjs"
).resolve()


DIRECT_HDC_TRANSPORT_COMMANDS = {"tconn"}
DIRECT_HDC_SHELL_PROBES = {
    ("echo", "ok"),
    ("param", "get", "bootevent.boot.completed"),
}


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


def iso(timestamp: dt.datetime) -> str:
    return timestamp.astimezone().isoformat(timespec="seconds")


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
        with path.open("r", encoding="utf-8") as file:
            data = json.load(file)
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def save_lease(path: Path, data: dict[str, Any]) -> None:
    temporary_path = path.with_suffix(".json.tmp")
    with temporary_path.open("w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=2, sort_keys=True)
        file.write("\n")
    temporary_path.replace(path)


def is_active(data: dict[str, Any] | None) -> bool:
    if not data or data.get("status") != "active" or stale_reason(data):
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
    liveness = "TTL-only / not process-bound" if holder_pid is None else (
        f"process-bound holder_pid={holder_pid} holder_host={holder_host or data.get('host') or 'unknown-host'}"
    )
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


def with_lock(device: str) -> tuple[Path, Any]:
    lease_path, lock_path = paths(device)
    lock_file = lock_path.open("a+", encoding="utf-8")
    fcntl.flock(lock_file, fcntl.LOCK_EX)
    return lease_path, lock_file


def cmd_status(args: argparse.Namespace) -> int:
    lease_path, lock_file = with_lock(args.device)
    try:
        data = load_lease(lease_path)
        if args.json:
            print(json.dumps(data or {}, ensure_ascii=False, indent=2, sort_keys=True))
        else:
            print(render(data))
        return 0 if is_active(data) else 1
    finally:
        fcntl.flock(lock_file, fcntl.LOCK_UN)
        lock_file.close()


def cmd_acquire(args: argparse.Namespace) -> int:
    lease_path, lock_file = with_lock(args.device)
    try:
        existing = load_lease(lease_path)
        if is_active(existing) and not args.force:
            print("device lease denied: device is already leased", file=sys.stderr)
            print(render(existing), file=sys.stderr)
            return 2
        now = utc_now()
        lease_id = f"{now.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}"
        data: dict[str, Any] = {
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
        fcntl.flock(lock_file, fcntl.LOCK_UN)
        lock_file.close()


def cmd_renew(args: argparse.Namespace) -> int:
    lease_path, lock_file = with_lock(args.device)
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
        fcntl.flock(lock_file, fcntl.LOCK_UN)
        lock_file.close()


def cmd_release(args: argparse.Namespace) -> int:
    lease_path, lock_file = with_lock(args.device)
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
        fcntl.flock(lock_file, fcntl.LOCK_UN)
        lock_file.close()


def wait_for_lease(args: argparse.Namespace) -> dict[str, Any] | None:
    deadline = time.time() + args.wait
    while True:
        lease_path, lock_file = with_lock(args.device)
        try:
            data = load_lease(lease_path)
            if is_active(data) and data.get("lease_id") == args.lease:
                return data
            if args.wait <= 0 or time.time() >= deadline:
                print("device lease run denied: lease is not active or id mismatch", file=sys.stderr)
                print(render(data), file=sys.stderr)
                return None
        finally:
            fcntl.flock(lock_file, fcntl.LOCK_UN)
            lock_file.close()
        time.sleep(1)


def direct_device_protocol_violation(
    command: list[str], expected_device: str | None = None
) -> str | None:
    """Reject lease-wrapped shortcuts around the manifest protocol runner."""
    if not command:
        return None
    executable = Path(command[0]).name
    if executable.startswith("python"):
        if len(command) != 3 or Path(command[1]).resolve() != CHECKED_PROTOCOL_RUNNER:
            return "Python device commands must use the checked run_device_protocol.py invocation"
        manifest = Path(command[2]).resolve()
        try:
            manifest.relative_to(PROJECT_ROOT)
        except ValueError:
            return "device protocol manifest must be project-owned"
        try:
            manifest_payload = json.loads(manifest.read_text(encoding="utf-8"))
            manifest_target = str(manifest_payload["target"])
            manifest_authorized_target = manifest_payload.get("authorizedTarget")
        except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
            return "device protocol manifest must be readable JSON with a target"
        if expected_device and manifest_target != expected_device:
            return "device protocol manifest target must match the active lease target"
        if (
            manifest_authorized_target is not None
            and str(manifest_authorized_target) != manifest_target
        ):
            return "device protocol manifest target must match its authorized target"
        return None
    if executable == "node":
        if len(command) != 3 or Path(command[1]).resolve() != CHECKED_RECORDING_RUNNER:
            return "Node device commands must use the checked capture_transition_recording.mjs invocation"
        manifest = Path(command[2]).resolve()
        try:
            manifest.relative_to(PROJECT_ROOT)
        except ValueError:
            return "transition recording manifest must be project-owned"
        try:
            manifest_payload = json.loads(manifest.read_text(encoding="utf-8"))
            manifest_target = str(manifest_payload["target"])
            manifest_authorized_target = manifest_payload.get("authorizedTarget")
            recording_file_name = str(manifest_payload["recordingFileName"])
        except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
            return "transition recording manifest must be readable JSON with target and recordingFileName"
        if not recording_file_name.endswith(".mp4"):
            return "transition recording manifest must declare an mp4 recordingFileName"
        if expected_device and manifest_target != expected_device:
            return "transition recording manifest target must match the active lease target"
        if (
            manifest_authorized_target is not None
            and str(manifest_authorized_target) != manifest_target
        ):
            return "transition recording manifest target must match its authorized target"
        return None
    if executable in {"sh", "bash", "zsh", "env"}:
        return "shell or environment wrappers are not permitted for device commands"
    if executable != "hdc":
        return "lease run accepts only the checked protocol runner or explicit transport probes"

    argv = list(command[1:])
    command_target: str | None = None
    if argv[:1] == ["-t"] and len(argv) >= 3:
        command_target = argv[1]
        argv = argv[2:]
    if not argv:
        return "direct HDC invocation has no permitted transport operation"
    if argv[0] in DIRECT_HDC_TRANSPORT_COMMANDS:
        if len(argv) != 2 or (expected_device and argv[1] != expected_device):
            return "HDC reconnect target must match the active lease target"
        return None
    if argv[:2] == ["list", "targets"] and command_target is None:
        return None
    if command_target is None:
        return "device-specific HDC probes require an explicit -t target"
    if expected_device and command_target != expected_device:
        return "HDC target must match the active lease target"
    if argv[:2] == ["file", "recv"]:
        return None
    if argv[0] == "shell":
        shell_argv = tuple(argv[1:])
        if shell_argv in DIRECT_HDC_SHELL_PROBES:
            return None
    return "stateful or evidentiary HDC commands must run through a checked device-protocol manifest"


def cmd_run(args: argparse.Namespace) -> int:
    if not args.command:
        print("device lease run requires a command after --", file=sys.stderr)
        return 2
    violation = direct_device_protocol_violation(args.command, args.device)
    if violation:
        print(f"device lease run denied: {violation}", file=sys.stderr)
        print(
            "use scripts/run-device-protocol --device <target> --lease <lease> <manifest.json>",
            file=sys.stderr,
        )
        return 2
    if not wait_for_lease(args):
        return 2
    if args.print_command:
        print("+ " + " ".join(shlex.quote(part) for part in args.command), file=sys.stderr)
    # HDC may auto-start its host server; detach the client from a short-lived exec group.
    return subprocess.call(
        args.command, start_new_session=Path(args.command[0]).name == "hdc"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Real-device lease and checked protocol gate for NextE agent tasks"
    )
    parser.add_argument("--device", required=True, help="explicit user-authorized device target; no default")
    sub = parser.add_subparsers(dest="cmd", required=True)

    status = sub.add_parser("status")
    status.add_argument("--json", action="store_true")
    status.set_defaults(func=cmd_status)

    acquire = sub.add_parser("acquire")
    acquire.add_argument("--owner", required=True)
    acquire.add_argument("--project", default="NextE")
    acquire.add_argument("--reason", default="agent device validation")
    acquire.add_argument("--ttl", default="30m")
    acquire.add_argument("--holder-pid", type=int)
    acquire.add_argument("--force", action="store_true", help="manual/user-approved override only")
    acquire.set_defaults(func=cmd_acquire)

    renew = sub.add_parser("renew")
    renew.add_argument("--lease", required=True)
    renew.add_argument("--ttl", default="30m")
    renew.set_defaults(func=cmd_renew)

    release = sub.add_parser("release")
    release.add_argument("--lease", required=True)
    release.add_argument("--force", action="store_true")
    release.set_defaults(func=cmd_release)

    run = sub.add_parser("run")
    run.add_argument("--lease", required=True)
    run.add_argument("--wait", type=int, default=0)
    run.add_argument("--print-command", action="store_true")
    run.add_argument("command", nargs=argparse.REMAINDER)
    run.set_defaults(func=cmd_run)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if getattr(args, "command", None) and args.command[:1] == ["--"]:
        args.command = args.command[1:]
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
