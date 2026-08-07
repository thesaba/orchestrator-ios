#!/usr/bin/env python3
"""Reads one HTTP response on stdin (body, then a final line with the status code),
redacts anything that looks like a credential, and prints a compact schema summary
plus a truncated sample. Nothing unredacted is ever written to disk."""
import json, re, sys

SECRET_KEY = re.compile(
    r"(token|secret|password|passwd|pwd|api_?key|privatekey|private_key|ssh_?key|"
    r"deploy_?key|credential|authorization|cookie|session|dsn|webhook|salt|hash|"
    r"access_?key|client_?secret|bot_?token)", re.I)
SECRET_VALUE = re.compile(r"(orch_[A-Za-z0-9]{8,}|dop_v1_[A-Za-z0-9]+|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_\-]{10,}\.)")

MAX_ARRAY = 3
MAX_STRING = 300

def redact(node, key=None):
    if isinstance(node, dict):
        return {k: redact(v, k) for k, v in node.items()}
    if isinstance(node, list):
        out = [redact(v, key) for v in node[:MAX_ARRAY]]
        if len(node) > MAX_ARRAY:
            out.append("<%d more items omitted>" % (len(node) - MAX_ARRAY))
        return out
    if isinstance(node, str):
        if key and SECRET_KEY.search(key):
            return "<redacted len=%d>" % len(node)
        if SECRET_VALUE.search(node):
            return "<redacted len=%d>" % len(node)
        if len(node) > MAX_STRING:
            return node[:MAX_STRING] + ("<truncated total=%d>" % len(node))
        return node
    return node

def shape(node, path="", out=None):
    if out is None:
        out = []
    if isinstance(node, dict):
        for k, v in node.items():
            shape(v, path + "." + k if path else k, out)
    elif isinstance(node, list):
        if node:
            shape(node[0], path + "[]", out)
        else:
            out.append("%s[] : empty array" % path)
    else:
        t = {type(None): "null", bool: "bool", int: "int", float: "double", str: "string"}.get(type(node), "?")
        if t == "string" and isinstance(node, str) and re.match(r"^\d{4}-\d\d-\d\dT", node):
            t = "string(date)"
        out.append("%s : %s" % (path or "<root>", t))
    return out

def main():
    name, path, code = sys.argv[1], sys.argv[2], sys.argv[3]
    raw = sys.stdin.read()
    print("### %s\nGET %s -> HTTP %s" % (name, path, code))
    body = raw.strip()
    if not body:
        print("(empty body)\n")
        return
    try:
        data = json.loads(body)
    except Exception:
        print("(non-JSON body, first 400 chars)")
        print(re.sub(SECRET_VALUE, "<redacted>", body[:400]))
        print()
        return
    safe = redact(data)
    print("-- shape --")
    for line in dict.fromkeys(shape(data)):
        print("  " + line)
    print("-- sample --")
    print(json.dumps(safe, indent=2, ensure_ascii=False)[:4000])
    print()

main()
