#!/usr/bin/env python3
"""Smoke test for M3: completion + hover over stdio."""
import json
import subprocess
import sys
import time

BUFFER = bytearray()
RESPONSES = []


def read_message(proc):
    while b"\r\n\r\n" not in BUFFER:
        chunk = proc.stdout.read(1)
        if not chunk:
            raise EOFError("server closed stdout")
        BUFFER.extend(chunk)
    header, _, rest = bytes(BUFFER).partition(b"\r\n\r\n")
    length = 0
    for line in header.split(b"\r\n"):
        if line.lower().startswith(b"content-length:"):
            length = int(line.split(b":")[1].strip())
    BUFFER.clear()
    BUFFER.extend(rest)
    while len(BUFFER) < length:
        chunk = proc.stdout.read(1)
        if not chunk:
            raise EOFError("server closed stdout")
        BUFFER.extend(chunk)
    payload = bytes(BUFFER[:length])
    del BUFFER[:length]
    return json.loads(payload)


def send(proc, message):
    body = json.dumps(message).encode()
    proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    proc.stdin.flush()


def request(proc, method, params, message_id):
    send(proc, {"jsonrpc": "2.0", "id": message_id, "method": method, "params": params})
    while True:
        message = read_message(proc)
        if "id" in message:
            RESPONSES.append(message)
            return message
        print(f"  skipped notification: {message.get('method')}")


def notify(proc, method, params):
    send(proc, {"jsonrpc": "2.0", "method": method, "params": params})


def main():
    binary = sys.argv[1] if len(sys.argv) > 1 else ".build/debug/grammar-workbench-lsp"
    proc = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        init = request(proc, "initialize", {"processId": None, "capabilities": {}, "workspaceFolders": None}, 1)
        capabilities = init["result"]["capabilities"]
        assert capabilities.get("hoverProvider") is True, capabilities
        assert "completionProvider" in capabilities, capabilities
        print("PASS: initialize advertises completionProvider + hoverProvider")
        notify(proc, "initialized", {})
        send(proc, {"jsonrpc": "2.0", "method": "workspace/didChangeConfiguration", "params": {"settings": None}})

        grammar = """%start Program
Program : Stmt Program | Stmt ;
Stmt : 'print' Expr ;
Expr : 'number' | 'string' ;
"""
        notify(proc, "textDocument/didOpen", {"textDocument": {
            "uri": "file:///tmp/prog.grammarworkbench", "languageId": "grammar",
            "version": 1, "text": grammar,
        }})

        source_uri = "file:///tmp/program.txt"
        notify(proc, "textDocument/didOpen", {"textDocument": {
            "uri": source_uri, "languageId": "prog", "version": 1, "text": "print nu",
        }})
        # Wait for the diagnostics notification for the source document.
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            message = read_message(proc)
            if message.get("method") == "textDocument/publishDiagnostics" and message["params"]["uri"] == source_uri:
                break
        else:
            raise AssertionError("no diagnostics published for the source document")
        print("PASS: diagnostics published for the source document")

        completion = request(proc, "textDocument/completion", {
            "textDocument": {"uri": source_uri}, "position": {"line": 0, "character": 8},
        }, 2)
        items = completion["result"]["items"]
        assert [item["label"] for item in items] == ["number"], items
        item = items[0]
        assert item["textEdit"] == {"range": {"start": {"line": 0, "character": 6}, "end": {"line": 0, "character": 8}}, "newText": "number"}, item
        assert item["kind"] == 14, item
        assert item["detail"] == "'number'", item
        print("PASS: completion filters expected terminals, kinds, textEdit", items)

        notify(proc, "textDocument/didChange", {"textDocument": {"uri": source_uri, "version": 2}, "contentChanges": [{"text": "print number"}]})
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            message = read_message(proc)
            if message.get("method") == "textDocument/publishDiagnostics" and message["params"]["uri"] == source_uri:
                break
        else:
            raise AssertionError("no diagnostics published after change")
        print("PASS: document change reanalyzed")

        hover = request(proc, "textDocument/hover", {
            "textDocument": {"uri": source_uri}, "position": {"line": 0, "character": 7},
        }, 3)
        contents = hover["result"]["contents"]
        assert contents["kind"] == "markdown", contents
        assert "Token `number`" in contents["value"], contents
        assert "Expr → 'number'" in contents["value"], contents
        assert hover["result"]["range"]["start"] == {"line": 0, "character": 6}, hover
        print("PASS: hover shows token and production", contents["value"].splitlines())

        shutdown = request(proc, "shutdown", None, 4)
        assert shutdown["result"] is None
        send(proc, {"jsonrpc": "2.0", "method": "exit", "params": None})
        proc.wait(timeout=5)
        print("PASS: shutdown + exit")
        print("ALL M3 SMOKE CHECKS PASSED")
    finally:
        if proc.poll() is None:
            proc.kill()


if __name__ == "__main__":
    main()
