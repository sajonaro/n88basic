#!/bin/sh
# serve-web-console.sh -- serve the built console, visibly.
#
# This runs until you stop it, which is what a server does -- but it used to
# run with stderr discarded, and a silent server is indistinguishable from a
# hung one. Two consequences, both reported as "make wc hangs": there was no
# request log to show it working, and a port already in use failed without
# saying so.
#
# So: check the port before binding it, keep the log, and say plainly that the
# prompt is not coming back.
set -eu
cd "$(dirname "$0")/.."

PORT="${PORT:-8088}"
DIR=web-console

[ -d "$DIR" ] || { echo "No console built yet. Run: make web" >&2; exit 1; }

# Refuse a port in use rather than letting python fail into a void.
if command -v python3 >/dev/null 2>&1 && python3 - "$PORT" <<'PY'
import socket, sys
s = socket.socket()
try:
    s.bind(("127.0.0.1", int(sys.argv[1])))
    sys.exit(1)          # free
except OSError:
    sys.exit(0)          # taken
finally:
    s.close()
PY
then
  echo "Port $PORT is already in use." >&2
  echo "Stop whatever is on it, or choose another:  make wc PORT=8099" >&2
  exit 1
fi

echo
echo "  n88basic console:  http://localhost:$PORT/"
echo
echo "  This stays in the foreground and logs each request below."
echo "  Press Ctrl-C to stop it and get your prompt back."
echo

# -u so the log appears as requests arrive rather than when a buffer fills,
# and stderr kept, because the request log is the only sign of life.
exec python3 -u -m http.server "$PORT" --bind 127.0.0.1 --directory "$DIR"
