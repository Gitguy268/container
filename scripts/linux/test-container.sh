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

# Checks how container.sh translates commands, with a fake podman that prints its arguments.
cd "$(dirname "$0")" || exit 1
fake=$(mktemp)
trap 'rm -f "$fake"' EXIT
printf '#!/bin/sh\necho "$*"\n' >"$fake" && chmod +x "$fake"
export CONTAINER_PODMAN="$fake"
fail=0

check() {
    want=$1
    shift
    got=$(sh ./container.sh "$@")
    [ "$got" = "$want" ] || { echo "FAIL: container $* -> '$got', want '$want'"; fail=1; }
}

check "ps -a" ls -a
check "ps --all" list --all
check "rm -f web" delete -f web
check "run --cpus 2 -m 1G alpine echo -c" run -c 2 -m 1G alpine echo -c
check "run -m 1G --cpus 2 alpine" run -m 1G -c 2 alpine
check "run -d alpine sh -c true" run -d alpine sh -c true
check "create alpine sh -c true" create alpine sh -c true
check "run -it --rm alpine sh" here alpine sh
check "images" image list
check "rmi alpine" image delete alpine
check "image pull alpine" image pull alpine
check "volume ls" volume list
check "network rm net1" network delete net1
check "system prune -f" system prune -f
check "logs -f web" logs -f web
sh ./container.sh dash 2>/dev/null && { echo "FAIL: dash should exit non-zero"; fail=1; }
CONTAINER_PODMAN=/nonexistent sh ./container.sh ls 2>/dev/null; [ $? = 127 ] || { echo "FAIL: missing podman should exit 127"; fail=1; }

[ $fail = 0 ] && echo "container.sh: all checks passed"
exit $fail
