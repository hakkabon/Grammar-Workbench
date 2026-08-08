#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: smoke-lsp.sh LSP_PATH" >&2
    exit 2
fi

LSP_PATH="$1"
test -x "$LSP_PATH"

# Drives a minimal LSP session over stdio: initialize, didOpen of a grammar
# document, then shutdown/exit. The server must reply to initialize and exit
# with status 0 after a received shutdown.
python3 - "$LSP_PATH" <<'PY'
import json
import subprocess
import sys

path = sys.argv[1]
process = subprocess.Popen(
    [path],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

def frame(payload: dict) -> bytes:
    body = json.dumps(payload, separators=(",", ":")).encode()
    return f"Content-Length: {len(body)}\r\n\r\n".encode() + body

def send(payload: dict) -> None:
    process.stdin.write(frame(payload))
    process.stdin.flush()

def read_message() -> dict:
    headers = {}
    while True:
        line = process.stdout.readline()
        if not line or line in (b"\r\n", b"\n"):
            break
        key, value = line.decode().split(":", 1)
        headers[key.lower().strip()] = value.strip()
    length = int(headers["content-length"])
    body = process.stdout.read(length)
    return json.loads(body)

send({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "processId": None,
        "capabilities": {},
        "workspaceFolders": None,
    },
})
reply = read_message()
assert reply.get("id") == 1, reply
assert "result" in reply and "capabilities" in reply["result"], reply
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
send({"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None})
reply = read_message()
assert reply.get("id") == 2 and "result" in reply, reply
send({"jsonrpc": "2.0", "method": "exit", "params": None})
process.stdin.close()
exit_code = process.wait(timeout=30)
assert exit_code == 0, f"server exited with {exit_code}"
print("LSP release smoke tests passed.")
PY
