# `container` on Linux

`container` itself needs macOS: every container is a small VM made with Apple's Virtualization framework. On Linux, containers don't need a VM, so this fork ships a small script, [`scripts/linux/container.sh`](../scripts/linux/container.sh), that takes the same commands and runs them through [podman](https://podman.io). It is plain `sh`, so it works on any architecture podman supports, including 32-bit x86.

## Install

```bash
sudo apk add podman          # Alpine
sudo apt install podman      # Debian, Ubuntu
sudo install -m 755 scripts/linux/container.sh /usr/local/bin/container
```

## Use

```bash
container run --rm alpine echo hello
container here alpine sh     # same as run -it --rm
container ls -a
container image list
container delete -f web
```

| macOS `container` | Runs on Linux as |
|---|---|
| `list`, `ls` | `podman ps` |
| `delete`, `rm` | `podman rm` |
| `image list` / `image delete` | `podman images` / `podman rmi` |
| `volume list`, `network delete`, … | `podman volume ls`, `podman network rm`, … |
| `run -c N` | `podman run --cpus N` |
| `here IMAGE [CMD]` | `podman run -it --rm IMAGE [CMD]` |
| `system start` / `stop`, `builder …` | nothing to do: podman has no background services |
| `system status` | `podman info` |
| `dash` | not available |

Everything else (`exec`, `logs`, `inspect`, `build`, `pull`, `stop`, `kill`, `wait`, …) passes to podman unchanged. Set `CONTAINER_PODMAN` to use another podman-compatible binary. `sh scripts/linux/test-container.sh` checks the translations without podman.
