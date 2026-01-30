import sys, pathlib
target = pathlib.Path(sys.argv[1])
target.write_bytes(sys.stdin.buffer.read())
print(f"Written {target.stat().st_size} bytes to {target}")
