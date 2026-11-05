#!/usr/bin/env bash
# First encrypted job inside ghcr.io/niobiuminc/fhe-dev.
# Locks two numbers, multiplies them without opening them, then opens the box.
# No Fog account. Pass --fog only when this container already has a Fog login.
set -euo pipefail

EXAMPLES="${NIOBIUM_EXAMPLES:-/opt/niobium-client/build/examples}"
FOG=0
nums=()
for arg in "$@"; do
  if [[ "$arg" == "--fog" ]]; then
    FOG=1
  else
    nums+=("$arg")
  fi
done

if [[ ${#nums[@]} -eq 2 ]]; then
  A="${nums[0]}"
  B="${nums[1]}"
elif [[ ${#nums[@]} -eq 0 && -t 0 ]]; then
  read -r -p "First number: " A
  read -r -p "Second number: " B
else
  echo "Type two whole numbers when asked, or pass them: bash try-it.sh 8 5"
  echo "From this folder, run:"
  echo "  docker run --rm -it -v \"\$PWD\":/work -w /work ghcr.io/niobiuminc/fhe-dev:latest bash try-it.sh"
  exit 1
fi

if [[ ! "$A" =~ ^[0-9]+$ || ! "$B" =~ ^[0-9]+$ ]]; then
  echo "Use two whole numbers. Example: bash try-it.sh 8 5"
  exit 1
fi

if [[ ! -x "$EXAMPLES/mult_client" || ! -x "$EXAMPLES/mult_server" || ! -x "$EXAMPLES/mult_decrypt" ]]; then
  echo "Those programs live in the Niobium image, not on your laptop."
  echo "From this folder, run:"
  echo "  docker run --rm -it -v \"\$PWD\":/work -w /work ghcr.io/niobiuminc/fhe-dev:latest bash try-it.sh"
  exit 1
fi

cd "$EXAMPLES"
rm -rf mult_keys mult_server_workload_ckks_mult
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ms_now() { date +%s%N; }
elapsed() {
  python3 - "$1" "$2" << 'PY'
import sys
a, b = int(sys.argv[1]), int(sys.argv[2])
print(f"{(b - a) / 1e9:.2f}")
PY
}

t0=$(ms_now)
if ! ./mult_client mult_keys "$A" "$B" >"$tmp/client.log" 2>&1; then
  echo "Locking the numbers failed:"
  cat "$tmp/client.log"
  exit 1
fi
t1=$(ms_now)
if ! ./mult_server mult_keys >"$tmp/server.log" 2>&1; then
  echo "The multiply failed:"
  cat "$tmp/server.log"
  exit 1
fi
t2=$(ms_now)
if ! ./mult_decrypt mult_keys >"$tmp/decrypt.log" 2>&1; then
  echo "Opening the box failed:"
  cat "$tmp/decrypt.log"
  exit 1
fi
t3=$(ms_now)

result=$(sed -n 's/^Result: //p' "$tmp/decrypt.log" | head -1)
pass=$(grep -E '^\[PASS\]|^\[FAIL\]' "$tmp/decrypt.log" || true)
instructions=$(grep -oE 'Recording stopped \([0-9]+ instructions\)' "$tmp/server.log" | grep -oE '[0-9]+' || true)
bytes=$(find mult_keys -type f -printf '%s\n' | python3 -c 'import sys; print(sum(int(x) for x in sys.stdin))')
files=$(find mult_keys -type f | wc -l | tr -d ' ')

echo
echo "Receipt"
echo "Answer: ${result:-not printed}"
echo "Check: ${pass:-not printed}"
echo "Locked files: ${files} files, ${bytes} bytes"
echo "Instructions recorded: ${instructions:-not printed}"
echo "Time to lock: $(elapsed "$t0" "$t1") sec"
echo "Time to multiply here: $(elapsed "$t1" "$t2") sec"
echo "Time to open: $(elapsed "$t2" "$t3") sec"
echo "Total: $(elapsed "$t0" "$t3") sec"

if [[ "$FOG" -eq 0 ]]; then
  echo "Where the multiply ran: on this machine, inside the image. The secret key stayed in this container."
  echo "Chip time: not in this receipt. A Fog login is a separate step, and the command still does not print milliseconds on the chip."
  echo "Fog: skipped. Add --fog after you have run fog login in this container."
  exit 0
fi

echo "Where the local multiply ran: on this machine, inside the image. The secret key stayed in this container."
echo "Chip time: not in this receipt. The Fog lines below are the cloud job. Milliseconds on the chip are only in the console."

cred="${FOG_HOME:-$HOME/.fog}/credentials"
if [[ ! -f "$cred" ]]; then
  echo "Fog: no login file at $cred. The local result above still stands."
  exit 0
fi

echo "Fog: sending the same multiply to a chip."
if ! fog submit ./mult_server mult_keys --hollow --target=FOG >"$tmp/fog.log" 2>&1; then
  echo "Fog submit failed. The log was not printed."
  exit 1
fi
job=$(grep -oE 'assigned [0-9a-f-]{36}' "$tmp/fog.log" | awk '{print $2}' | head -1)
if [[ -z "$job" ]]; then
  echo "Fog submit finished, but no job id was printed."
  exit 0
fi
if ! fog get "$job" >"$tmp/job.json" 2>"$tmp/fog-get.err"; then
  echo "Fog status check failed. The log was not printed."
  exit 1
fi
python3 - "$tmp/job.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("Fog job:", d.get("job_id"), d.get("status"))
print("Sent:", d.get("bytes_in"), "bytes in", d.get("upload_seconds"), "sec")
print("Came back:", d.get("bytes_out"), "bytes in", d.get("download_seconds"), "sec")
print("Queued:", d.get("enqueued_at"), "Ended:", d.get("ended_at"))
print("Worker:", d.get("worker_hostname"))
print("Milliseconds on the chip: not in this record. The console shows that number. This command does not.")
PY
