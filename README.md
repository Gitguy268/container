<h1>
  <img alt="Containerization logo" src="./assets/Containerization-Logo.png" width="70" valign="middle">
  &nbsp;container
</h1>

`container` is a tool that you can use to create and run Linux containers as lightweight virtual machines on your Mac. It's written in Swift, and optimized for Apple silicon.

The tool consumes and produces [OCI-compatible container images](https://github.com/opencontainers/image-spec), so you can pull and run images from any standard container registry. You can push images that you build to those registries as well, and run the images in any other OCI-compatible application.

`container` uses the [Containerization](https://github.com/apple/containerization) Swift package for low-level container, image, and process management.

![introductory movie showing some basic commands](./docs/assets/landing-movie.gif)

## What this fork adds

> [!NOTE]
> This is a community fork of [apple/container](https://github.com/apple/container) by [Gitguy268](https://github.com/Gitguy268). It is not affiliated with or endorsed by Apple Inc. The rest of this README is upstream's, unchanged.

| | |
|---|---|
| **`container here`** | Runs a container in a VM that lives inside your terminal. No `container system start`, no background services. Close the tab and the VM is gone. |
| **`container dash`** | Full-screen terminal dashboard for containers, images, machines, volumes and networks, with live CPU and memory, shells, logs, start, stop and delete. |
| **Linux** | The same `container` commands on any Linux terminal, through podman, including 32-bit x86. See [docs/linux.md](./docs/linux.md). |
| **Fixes** | Terminal output in `exec -it` / `run -it` no longer breaks tmux and other TUIs ([#2299](https://github.com/apple/container/issues/2299)). Stable environment variable order ([#2338](https://github.com/apple/container/issues/2338)). `export -o <dir>` no longer deletes the directory ([#2325](https://github.com/apple/container/issues/2325)). `kernel set --force` no longer deletes the installed kernel before the copy succeeds ([#2326](https://github.com/apple/container/issues/2326)). Relative mount targets are rejected instead of silently mounted at `/` ([#2324](https://github.com/apple/container/issues/2324)). |
| **New options** | `container ls --filter label=k[=v]` ([#2403](https://github.com/apple/container/issues/2403)), `container wait` with the exit code kept in `inspect` ([#2402](https://github.com/apple/container/issues/2402)), `--pids-limit` ([#2401](https://github.com/apple/container/issues/2401)), `--sysctl` ([#2400](https://github.com/apple/container/issues/2400)), `container system prune` ([#891](https://github.com/apple/container/issues/891)), `ps` alias, CPU % in `stats --format json`, image snapshots and root filesystems excluded from Time Machine. |

### `container here`: the VM lives in your terminal

![container here booting alpine in the terminal with no services running](./docs/assets/fork-here.webp)

```bash
container system kernel set --recommended   # once; needs the services running for this step only
container system stop                        # nothing in the background from here on
container here alpine uname -a               # boots a VM inside this process
container here ubuntu bash                   # interactive shell; the tty is detected, no -it needed
echo hi | container here alpine cat          # pipes work too
container here alpine sh -c 'exit 3'; echo $? # prints 3
```

<details>
<summary>How it works and what it leaves out</summary>

Upstream `container` runs every VM inside launchd services: `container-apiserver` launches one `container-runtime-linux` helper per container, and the CLI talks to them over XPC. That is why VMs keep running after you close the terminal, and why nothing works before `container system start`.

`container here` skips all of that. It uses the [Containerization](https://github.com/apple/containerization) package directly, in the same way as its `cctl run` example: the CLI process pulls the image, unpacks it, boots the VM with Virtualization.framework, attaches your terminal (or plain stdio when there is none), waits for the process and removes the VM. To do that, the `container` binary is signed with the `com.apple.security.virtualization` entitlement (`signing/container-cli.entitlements`).

- **Lifetime:** the VM is stopped and its files are removed when the command ends, when the terminal closes (SIGHUP) or on SIGTERM. If the process is killed with `kill -9`, Virtualization.framework stops the VM, and the next `container here` removes the leftover files.
- **Ctrl-C:** with a tty it goes to the program in the VM, just like `container run -it`. Without a tty it is forwarded as SIGINT.
- **Storage:** images live in their own store under `~/Library/Application Support/com.apple.container/here`, excluded from Time Machine, so it never writes at the same time as the API server. Images you pulled with `container image pull` are pulled again the first time.
- **Network:** each run gets its own vmnet NAT network, with DNS through the gateway.
- **Not supported:** port publishing (`-p`), named volumes, private registries, `container ls` / `dash` listing of `here` VMs.

</details>

### `container dash`

![container dash showing the containers tab](./docs/assets/fork-dash.webp)

`↑↓`/`jk` select · `tab` switch · `s` start/stop · `r` restart · `e` shell · `l` logs · `d` delete (asks first) · `/` filter · `S` system start · `?` help · `q` quit

<details>
<summary>Build this fork</summary>

```bash
# The fork isn't on GitHub yet: start from a copy of it, kept outside Documents and Desktop (vmnet bug)
cd ~/container
make all                  # builds and signs into ./bin and ./libexec
bin/container system start
bin/container here alpine echo hello
```

CommandLineTools is enough to build. To run the unit tests with only CommandLineTools installed, point the compiler at the Swift Testing macro plugin:

```bash
make test SWIFT_CONFIGURATION_EXTRA="-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
```

</details>

---


## Get started

### Requirements

You need a Mac with Apple silicon to run `container`. To build it, see the [BUILDING](./BUILDING.md) document.

`container` is supported on macOS 26, since it takes advantage of new features and enhancements to virtualization and networking in this release. We do not support older versions of macOS and the `container` maintainers typically will not address issues that cannot be reproduced on macOS 26.

### Initial install

Download the latest signed installer package for `container` from the [GitHub release page](https://github.com/apple/container/releases).

To install the tool, double-click the package file and follow the instructions. Enter your administrator password when prompted, to give the installer permission to place the installed files under `/usr/local`.

Start the system service with:

```bash
container system start
```

### Run your first container

```bash
container run --rm alpine echo hello
```

This pulls the `alpine` image, runs it in a lightweight Linux VM, prints `hello`, and
removes the container when it exits. See the [tutorial](./docs/tutorials/start-here.md)
for a fuller walkthrough that builds and publishes an image of your own.

### Upgrade or downgrade

For both upgrading and downgrading, you can manually download and install the signed installer package by following the steps from [initial install](#initial-install) or use the `update-container.sh` script (installed to `/usr/local/bin`).

If you're upgrading or downgrading, you must stop your existing `container`:

```bash
container system stop
```

To upgrade to the latest release, simply run the command below:

```bash
/usr/local/bin/update-container.sh
```

To downgrade, you must uninstall your existing `container` (the `-k` flag keeps your user data, while `-d` removes it):

```bash
/usr/local/bin/uninstall-container.sh -k
/usr/local/bin/update-container.sh -v 0.3.0
```

Start the system service with:

```bash
container system start
```

### Uninstall

Use the `uninstall-container.sh` script (installed to `/usr/local/bin`) to remove `container` from your system. To remove your user data along with the tool, run:

```bash
/usr/local/bin/uninstall-container.sh -d
```

To retain your user data so that it is available should you reinstall later, run:

```bash
/usr/local/bin/uninstall-container.sh -k
```

## Next steps

- Take [a guided tour of `container`](./docs/tutorials/start-here.md) by building, running, and publishing a simple web server image.
- Learn how to [use various `container` features](./docs/how-to.md).
- Read a brief description and [technical overview](./docs/technical-overview.md) of `container`.
- Browse the [full command reference](./docs/command-reference.md).
- [Build and run](./BUILDING.md) `container` on your own development system.
- View the project [API documentation](https://apple.github.io/container/documentation/).

## Contributing

Contributions to `container` are welcome and encouraged. Please see our [main contributing guide](https://github.com/apple/containerization/blob/main/CONTRIBUTING.md) for more information.

## Project Status

The container project is under active development. Its release versions are product versions, not semantic versions.

The `container` CLI compatibility generally preserves backward compatibility within a major release (not breaking existing scripts), however, there may be the odd case where breaking compatibility may be necessary. **Note:** Features marked *experimental* (for example, the `k8s` subcommand) may change and do not guarantee backward compatibility.

The `container-apiserver` XPC API compatibility preserves forward and backward compatibility within a major version. 
Other non-public XPC helpers do not guarantee CLI or API compatibility across different versions.

The `container` application data provides forward compatibility only, guaranteed within one major version. Upgrading to a newer major version may require a specific upgrade path.
