# Terminal-only VMs and the dashboard

These two commands come from the Gitguy268/container fork.

## `container here`

`container here` runs a container in a VM hosted by the `container` process itself. It does not use `container-apiserver` or the per-container runtime helpers, so you don't need `container system start`, and nothing is left running in the background.

```bash
container here alpine uname -a
container here -v "$PWD:/src" -w /src node:22 npm test
container here --cpus 2 --memory 2g ubuntu bash
```

The VM's lifetime is tied to the command:

| What happens | Result |
|---|---|
| The process in the container exits | The VM stops and is removed. Its exit code becomes `container here`'s exit code. |
| You close the terminal (SIGHUP) or send SIGTERM | The VM is killed and removed. |
| `kill -9` on `container here` | Virtualization.framework stops the VM. The next `container here` removes its leftover files. |
| Ctrl-C | With a terminal it goes to the program inside, as with `container run -it`. Without one it is sent as SIGINT. |

A kernel has to be installed once, for example with `container system start --enable-kernel-install`. After that the services can stay stopped.

Images are stored in `~/Library/Application Support/com.apple.container/here`, apart from the API server's store, so the two never write to the same files at once. That folder is excluded from Time Machine.

Not supported yet: publishing ports, named volumes, private registries, and seeing `here` VMs in `container ls` or `container dash`.

## `container dash`

`container dash` opens a full-screen dashboard with tabs for containers, images, machines, volumes and networks. It reloads every two seconds (`--interval` changes that) and shows CPU and memory use for running containers.

| Key | Action |
|---|---|
| `↑` `↓` or `j` `k` | Move the selection |
| `tab`, `shift-tab` | Next or previous tab |
| `s` | Start or stop the selected container or machine |
| `r` | Restart the selected container |
| `e` | Open a shell (`container exec -it <id> sh`, or `container machine run` for machines) |
| `l` | Follow logs; Ctrl-C returns to the dashboard |
| `d` | Delete the selection, after a `y` to confirm |
| `/` | Filter rows; `esc` clears the filter |
| `S` | Run `container system start` |
| `?` | Help |
| `q` | Quit |

Each action runs the matching `container` command, so it behaves exactly like typing that command yourself.
