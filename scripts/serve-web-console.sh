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
# nginx also gets the media types right without being told -- .js, .svg and
# .css all arrive with the header a browser will act on, which is the part a
# hand-rolled static server gets wrong quietly.
#
# It runs until you stop it, which is what a server does -- but it used to run
# with its log discarded, and a silent server is indistinguishable from a hung
# one. Both were reported as "make wc hangs". So: keep the log, say plainly
# that the prompt is not coming back, and name the port when the bind fails.
set -eu
cd "$(dirname "$0")/.."

PORT="${PORT:-8088}"
DIR=web-console
# Pinned rather than :alpine, which moves under you. The Dockerfile's VERSIONS
# block pins the build images the same way and for the same reason.
IMAGE="${N88_HTTPD_IMAGE:-nginx:1.27-alpine}"

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

say() { printf '  %s\n' "$*"; }

# Pull EXPLICITLY rather than letting `docker run` do it implicitly. Two
# reasons, and the second is a bug this had:
#
#   1. A first run fetches ~20 MB with nothing on screen to say so. That wait
#      is the single longest silent stretch in `make wc`.
#   2. `cid=$(docker run -d ... 2>&1)` captures the PULL PROGRESS into $cid
#      along with the container id, and the `docker cp` that follows is then
#      handed several lines of download output instead of an id.
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  say "fetching $IMAGE (first run only, about 20 MB)..."
  docker pull "$IMAGE" || exit 1
fi

say "starting the server..."
err="$(mktemp)"
trap 'rm -f "$err"' EXIT
# stdout is the container id and ONLY the container id; anything docker has to
# say goes to $err, where it can be shown without contaminating the id.
if ! cid=$(docker run -d --init -p "127.0.0.1:$PORT:80" "$IMAGE" 2>"$err"); then
  cat "$err" >&2
  echo >&2
  echo "If that port is already taken, choose another:  make wc PORT=8099" >&2
  exit 1
fi

trap 'docker rm -f "$cid" >/dev/null 2>&1 || true; rm -f "$err"' EXIT INT TERM

say "copying $(ls "$DIR" | wc -l) files into it..."
docker cp "$DIR/." "$cid:/usr/share/nginx/html/" >/dev/null

# Do not claim it is ready -- ask it. wget is busybox's, already in the image,
# so this needs nothing on your machine. Without this the banner printed while
# nginx was still starting, and the first thing you saw after the URL was
# twenty lines of its boot log pushing that URL off the screen.
say "waiting for it to answer..."
ready=no
i=0
while [ "$i" -lt 50 ]; do
  if docker exec "$cid" wget -q -O /dev/null http://localhost/ 2>/dev/null; then
    ready=yes
    break
  fi
  if [ -z "$(docker ps -q --filter id="$cid")" ]; then
    echo "The server exited while starting up:" >&2
    docker logs "$cid" 2>&1 | tail -20 >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 0.2
done
if [ "$ready" != yes ]; then
  echo "The server started but never answered on port 80 inside the container." >&2
  docker logs "$cid" 2>&1 | tail -20 >&2
  exit 1
fi

echo
echo "  n88basic console is up:  http://localhost:$PORT/"
echo
echo "  Serving $DIR/ (a snapshot -- rebuild and restart to pick up changes)."
echo "  Each request is logged below. Ctrl-C stops it and frees the port."
echo

# --tail 0: only what happens from NOW. nginx replays twenty lines of startup
# chatter otherwise, and the URL above is the thing worth having on screen.
docker logs -f --tail 0 "$cid"
