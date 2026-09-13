#!/bin/sh
# serve-web-console.sh -- serve the built console over HTTP, in the foreground.
#
# WHY DOCKER AND NOTHING ELSE. The console already needs Docker on any machine
# without js_of_ocaml, because that is how it gets built there. Serving it with
# python3 meant a second dependency for the smaller half of the job, and a
# machine that could build the console but not show it. One dependency, both
# halves.
#
# WHY THE FILES ARE COPIED IN RATHER THAN BIND-MOUNTED. `docker run -v` hands
# the DAEMON a path and asks it to find that directory. That works only when the
# daemon shares a filesystem with you, and it fails QUIETLY when it does not:
# a remote DOCKER_HOST, a Docker Desktop VM without this directory shared, a
# checkout the VM cannot see -- each mounts an empty directory instead of
# erroring, and you get a 403 from nginx with nothing to say why. `docker cp`
# is resolved by the CLIENT, here, in this shell, so the layout of this machine
# stops being something the daemon has to agree with.
#
# The cost is that the files are a snapshot: rebuild, and restart this to see
# it. `make wc` builds first, so that is the normal path anyway.
#
# nginx also gets the media types right without being told -- .js, .svg, .css
# and .wasm all arrive with the header a browser will act on, which is the part
# a hand-rolled static server gets wrong quietly.
#
# It runs until you stop it, which is what a server does -- but it used to run
# with its log discarded, and a silent server is indistinguishable from a hung
# one. Both were reported as "make wc hangs". So: keep the log, say plainly
# that the prompt is not coming back, and name the port when the bind fails.
set -eu
cd "$(dirname "$0")/.."

PORT="${PORT:-8088}"
DIR=web-console
IMAGE="${N88_HTTPD_IMAGE:-nginx:alpine}"

[ -d "$DIR" ] || { echo "No console built yet. Run: make web" >&2; exit 1; }

if ! command -v docker >/dev/null 2>&1; then
  echo "This serves the console with Docker, and docker is not on your PATH." >&2
  echo "The console is already built and is plain static files:" >&2
  echo "  $(pwd)/$DIR" >&2
  echo "Point any static web server at that directory." >&2
  exit 1
fi

# Bound to the loopback address rather than every interface: this is a dev
# console, not something to put on the network by accident.
set +e
cid=$(docker run -d -p "127.0.0.1:$PORT:80" "$IMAGE" 2>&1)
started=$?
set -e
if [ "$started" != 0 ]; then
  echo "$cid" >&2
  echo >&2
  echo "If that port is already taken, choose another:  make wc PORT=8099" >&2
  exit 1
fi

# Before anything can go wrong below. Ctrl-C reaches this shell, not the
# detached container, so without the trap the server outlives the command that
# started it -- which is worse than a hang, because nothing says it is there.
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT INT TERM

docker cp "$DIR/." "$cid:/usr/share/nginx/html/"

echo
echo "  n88basic console:  http://localhost:$PORT/"
echo
echo "  This stays in the foreground and logs each request below."
echo "  Press Ctrl-C to stop it and get your prompt back."
echo

docker logs -f "$cid"
