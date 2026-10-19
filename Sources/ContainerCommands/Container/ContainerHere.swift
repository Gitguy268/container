//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc. and the container project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import ArgumentParser
import ContainerAPIClient
import ContainerPersistence
import ContainerPlugin
import ContainerResource
import Containerization
import ContainerizationError
import ContainerizationOCI
import ContainerizationOS
import Foundation

extension Application {
    /// Runs a container in a VM hosted by this process instead of the launchd services,
    /// so the VM lives exactly as long as the terminal session that started it.
    public struct ContainerHere: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "here",
            abstract: "Run a container in a VM that lives inside this terminal",
            discussion: """
                The VM runs inside this process: `container system start` is not needed, and closing \
                the terminal stops the VM and removes it. Images are kept in their own store under \
                <app-root>/here, apart from the API server's store.
                """
        )

        @OptionGroup
        public var logOptions: Flags.Logging

        @OptionGroup
        var resourceFlags: Flags.Resource

        @Option(name: .shortAndLong, help: "Set an environment variable (format: key=value)")
        var env: [String] = []

        @Option(name: [.customLong("volume"), .short], help: "Bind mount a host directory (format: host-path:container-path[:ro])")
        var volumes: [String] = []

        @Option(name: [.customShort("w"), .customLong("workdir")], help: "Set the initial working directory inside the container")
        var cwd: String?

        @Option(name: .long, help: "Name for the VM (default: here-<random>)")
        var name: String?

        @Option(name: .long, help: .init("Override the entrypoint of the image", valueName: "cmd"))
        var entrypoint: String?

        @Argument(help: "Image to run")
        var image: String

        @Argument(parsing: .captureForPassthrough, help: "Command to run in the container")
        var arguments: [String] = []

        static var root: URL { URL(fileURLWithPath: ApplicationRoot.pathname).appendingPathComponent("here") }
        static let pidFile = "here.pid"

        public func run() async throws {
            let systemConfig: ContainerSystemConfig = try await ConfigurationLoader.load()
            let kernel = try Self.defaultKernel()
            let mounts = try Self.mounts(volumes)
            let id = name ?? "here-\(UUID().uuidString.prefix(8).lowercased())"
            // The id becomes a directory name that is removed afterwards, so it must not be a path.
            guard ManagedContainer.nameValid(id) else {
                throw ContainerizationError(.invalidArgument, message: "invalid name '\(id)': use letters, digits, '.', '_' or '-'")
            }
            let cpus = Int(resourceFlags.cpus ?? Int64(systemConfig.container.cpus))
            let memory =
                try resourceFlags.memory.map { try Parser.memoryStringAsMiB($0).mib() }
                ?? UInt64(systemConfig.container.memory.measurement.converted(to: .mebibytes).value).mib()

            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            try? PathUtils.excludeFromBackup(Self.root)
            Self.sweepLeftovers()

            let store = try ImageStore(path: Self.root)
            var network: Network? = nil
            if #available(macOS 26, *) {
                network = try VmnetNetwork()
            }
            var manager = try await ContainerManager(
                kernel: kernel,
                initfsReference: systemConfig.vminit.image,
                imageStore: store,
                network: network
            )

            let reference = try ClientImage.normalizeReference(image, containerSystemConfig: systemConfig)
            // shortcut: anonymous pulls only; read registry credentials from the keychain if private images are needed here.
            let img = try await store.get(reference: reference, pull: true)
            let imageConfig = try await img.config(for: .current).config
            let processArguments = try Self.resolveArguments(arguments, entrypoint: entrypoint, imageConfig: imageConfig, reference: reference)
            let environment = try Parser.allEnv(imageEnvs: imageConfig?.env ?? [], envFiles: [], envs: env)

            let terminal = isatty(STDIN_FILENO) == 1 ? try? Terminal(descriptor: STDIN_FILENO) : nil
            if let terminal {
                try terminal.setrawNoOutputProcessing()
            }
            defer { terminal?.tryReset() }

            // Leftovers of dead runs were swept above, so an existing directory belongs to a live run.
            guard !FileManager.default.fileExists(atPath: Self.root.appendingPathComponent("containers/\(id)").path) else {
                throw ContainerizationError(.exists, message: "a `container here` VM named \(id) is already running")
            }
            // From here the directory is ours, including when create fails halfway.
            defer { try? manager.delete(id) }
            let container = try await manager.create(
                id,
                image: img,
                vm: VMResources(cpus: cpus, memoryInBytes: memory + VMResources.guestMemoryOverhead)
            ) { config in
                config.cpus = cpus
                config.memoryInBytes = memory
                config.process.arguments = processArguments
                config.process.environmentVariables = environment
                config.process.workingDirectory = cwd ?? imageConfig?.workingDir ?? "/"
                if let terminal {
                    config.process.setTerminalIO(terminal: terminal)
                } else {
                    config.process.stdin = StandardInput()
                    config.process.stdout = HandleWriter(handle: .standardOutput)
                    config.process.stderr = HandleWriter(handle: .standardError)
                }
                config.mounts.append(contentsOf: mounts)
                // vmnet's shared-mode gateway forwards DNS to the host resolver.
                if let gateway = config.interfaces.first?.ipv4Gateway {
                    config.dns = DNS(nameservers: [gateway.description])
                }
                config.hosts = Hosts.default
            }
            try "\(getpid())".write(
                to: Self.root.appendingPathComponent("containers").appendingPathComponent(id).appendingPathComponent(Self.pidFile),
                atomically: true, encoding: .utf8)

            let signals = AsyncSignalHandler.create(notify: [SIGHUP, SIGTERM, SIGINT, SIGWINCH])
            try await container.create()
            try await container.start()
            if let terminal {
                try? await container.resize(to: try terminal.size)
            }

            let exit = try await withThrowingTaskGroup(of: Void.self, returning: ExitStatus.self) { group in
                group.addTask {
                    for await signal in signals.signals {
                        switch signal {
                        case SIGWINCH:
                            if let terminal { try? await container.resize(to: try terminal.size) }
                        case SIGINT:
                            // Only reaches us without a tty; in raw mode Ctrl-C goes to the guest as a byte.
                            try? await container.kill(.int)
                        default:
                            // SIGHUP (terminal closed) or SIGTERM: stop the VM so wait() returns and cleanup runs.
                            try? await container.kill(.kill)
                        }
                    }
                }
                let status = try await container.wait()
                group.cancelAll()
                try? await container.stop()
                return status
            }

            if exit.exitCode != 0 {
                // ExitCode unwinds past the defers, so clean up first.
                terminal?.tryReset()
                try? manager.delete(id)
                throw ExitCode(exit.exitCode)
            }
        }

        static func resolveArguments(_ arguments: [String], entrypoint: String?, imageConfig: ImageConfig?, reference: String) throws -> [String] {
            let entry = entrypoint.map { [$0] } ?? imageConfig?.entrypoint ?? []
            let resolved = entry + (arguments.isEmpty ? imageConfig?.cmd ?? [] : arguments)
            guard !resolved.isEmpty else {
                throw ContainerizationError(.invalidArgument, message: "image \(reference) declares no entrypoint or cmd; pass a command to run")
            }
            return resolved
        }

        static func mounts(_ volumes: [String]) throws -> [Containerization.Mount] {
            try volumes.map { spec in
                let parts = spec.split(separator: ":").map(String.init)
                guard (2...3).contains(parts.count), parts.count == 2 || parts[2] == "ro" else {
                    throw ContainerizationError(.invalidArgument, message: "invalid volume '\(spec)': expected host-path:container-path[:ro]")
                }
                let source = URL(fileURLWithPath: parts[0], relativeTo: .currentDirectory()).standardizedFileURL.path
                guard FileManager.default.fileExists(atPath: source) else {
                    throw ContainerizationError(.invalidArgument, message: "host path \(source) does not exist")
                }
                guard parts[1].hasPrefix("/") else {
                    throw ContainerizationError(.invalidArgument, message: "container path \(parts[1]) is not absolute")
                }
                return .share(source: source, destination: parts[1], options: parts.count == 3 ? ["ro"] : [])
            }
        }

        static func defaultKernel() throws -> Kernel {
            let platform = SystemPlatform.linuxArm
            let link = URL(fileURLWithPath: ApplicationRoot.pathname)
                .appendingPathComponent("kernels/default.kernel-\(platform.architecture)")
                .resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: link.path) else {
                throw ContainerizationError(.notFound, message: "no kernel installed; run `container system kernel set --recommended` first")
            }
            return Kernel(path: link, platform: platform)
        }

        /// Removes VMs left behind by a `here` process that was killed before it could clean up.
        static func sweepLeftovers() {
            let containers = root.appendingPathComponent("containers")
            let entries = (try? FileManager.default.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil)) ?? []
            for dir in entries {
                guard let text = try? String(contentsOf: dir.appendingPathComponent(pidFile), encoding: .utf8),
                    let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
                else { continue }
                if kill(pid, 0) != 0 && errno == ESRCH {
                    try? FileManager.default.removeItem(at: dir)
                }
            }
        }
    }
}

/// Streams this process's stdin to the guest when there is no tty.
private struct StandardInput: ReaderStream {
    func stream() -> AsyncStream<Data> {
        AsyncStream { continuation in
            FileHandle.standardInput.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
    }
}

private struct HandleWriter: Writer {
    let handle: FileHandle

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }

    func close() throws {}
}
