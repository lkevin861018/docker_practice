"""Runtime security verification; exits nonzero if Flask hardening is missing."""
import os
from pathlib import Path

if os.geteuid() == 0:
    raise SystemExit("FAIL: app is running as root")
print(f"PASS: running as uid={os.geteuid()}")

probe = Path("/app/.v6-write-probe")
try:
    probe.write_text("should be blocked", encoding="utf-8")
except OSError:
    print("PASS: application directory is read-only")
else:
    probe.unlink(missing_ok=True)
    raise SystemExit("FAIL: application directory is writable")

status = {}
for line in Path("/proc/self/status").read_text(encoding="utf-8").splitlines():
    if ":" in line:
        key, value = line.split(":", 1)
        status[key] = value.strip()

if int(status.get("CapEff", "0"), 16) != 0:
    raise SystemExit("FAIL: effective Linux capabilities are nonzero")
print("PASS: effective Linux capabilities dropped")

if status.get("NoNewPrivs") != "1":
    raise SystemExit("FAIL: NoNewPrivs is not set")
print("PASS: no-new-privileges enforced")
