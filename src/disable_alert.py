#!/usr/bin/env python3
"""Static ELF patcher: neutralize alert/paywall initialization prologues.

Scans a target ELF executable in binary read/write mode for critical
assembler signature sequences (function prologues) and replaces them with
immediate x86_64 RET (0xC3) padded with NOP (0x90) to preserve file offsets.
"""

import os
import sys

# Signatures of alert/paywall initialization prologues to neutralize.
# Each entry: (signature_bytes, description)
SIGNATURES = [
    (b"\x55\x48\x89\xe5", "standard function prologue (push rbp; mov rbp, rsp)"),
    (b"\x55\x48\x89\xe5\x48\x83\xec", "prologue with stack frame allocation"),
    (b"\x48\x83\xec\x28\x48\x89\x5c\x24", "sub rsp, 0x28; mov [rsp+...], rbx"),
]

RET_OPCODE = b"\xc3"
NOP_OPCODE = b"\x90"


def scan_and_patch(path: str) -> int:
    if not os.path.isfile(path):
        print(f"[disable_alert] target not found: {path}", file=sys.stderr)
        return 1

    patched_count = 0
    with open(path, "rb+") as f:
        data = f.read()
        for sig, desc in SIGNATURES:
            offset = 0
            while True:
                idx = data.find(sig, offset)
                if idx == -1:
                    break
                # Replace first byte with RET, pad the rest with NOP.
                patch = RET_OPCODE + (NOP_OPCODE * (len(sig) - 1))
                f.seek(idx)
                f.write(patch)
                f.flush()
                os.fsync(f.fileno())
                patched_count += 1
                print(f"[disable_alert] patched {desc} at offset 0x{idx:x}")
                offset = idx + len(sig)
        # Refresh in-memory view not required; file already written.

    print(f"[disable_alert] total patches applied: {patched_count}")
    return 0


def main(argv):
    if len(argv) != 2:
        print("usage: disable_alert.py <elf-binary>", file=sys.stderr)
        return 2
    return scan_and_patch(argv[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv))