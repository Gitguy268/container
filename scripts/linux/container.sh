#!/bin/sh
# Copyright © 2026 Apple Inc. and the container project authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# `container` for Linux: the macOS CLI needs Virtualization.framework, so on Linux the same
# commands run through podman. Install as `container` anywhere on PATH; see docs/linux.md.

PODMAN=${CONTAINER_PODMAN:-podman}

if ! command -v "$PODMAN" >/dev/null 2>&1; then
    echo "container: podman is missing. Install it with 'apk add podman' or 'sudo apt install podman'." >&2
    exit 127
fi

p() { exec "$PODMAN" "$@"; }

# list/delete subcommands under image, volume and network.
sub() {
    group=$1 verb=${2-}
    shift
    [ $# -gt 0 ] && shift
    case "$verb" in
        list | ls) if [ "$group" = image ]; then p images "$@"; fi; p "$group" ls "$@" ;;
        delete | rm) if [ "$group" = image ]; then p rmi "$@"; fi; p "$group" rm "$@" ;;
        *) p "$group" "$verb" "$@" ;;
    esac
}

cmd=$1
[ $# -gt 0 ] && shift
case "$cmd" in
    "" | -h | --help | help)
        echo "container (Linux, via podman): run create start stop kill delete list exec logs inspect"
        echo "  image|volume|network list/delete/..., system status/prune/df, here IMAGE [CMD]"
        echo "Anything else is passed to podman unchanged."
        ;;
    --version | version) echo "container for Linux ($("$PODMAN" --version))" ;;
    list | ls) p ps "$@" ;;
    delete | rm) p rm "$@" ;;
    run | create)
        # shortcut: only -c is translated (podman's -c is cpu-shares); other flag differences pass through as is.
        # Options end at the first word that follows a non-flag word (the image), so "sh -c" is left alone.
        prev=- opts=1
        for a; do
            shift
            case "$prev" in -*) ;; *) case "$a" in -*) ;; *) opts=0 ;; esac ;; esac
            if [ $opts = 1 ] && [ "$a" = -c ]; then set -- "$@" --cpus; else set -- "$@" "$a"; fi
            prev=$a
        done
        p "$cmd" "$@"
        ;;
    here) p run -it --rm "$@" ;;
    image | images | i) sub image "$@" ;;
    volume | v) sub volume "$@" ;;
    network | n) sub network "$@" ;;
    system | s)
        case "$1" in
            start | stop) echo "container: podman has no background services; nothing to $1." ;;
            status) "$PODMAN" info >/dev/null && echo "podman is ready." ;;
            *) p system "$@" ;;
        esac
        ;;
    builder) echo "container: 'container build' uses podman's builder; no builder to manage." ;;
    dash) echo "container: dash needs macOS. Use 'container ls -a' here." >&2; exit 1 ;;
    *) p "$cmd" "$@" ;;
esac
