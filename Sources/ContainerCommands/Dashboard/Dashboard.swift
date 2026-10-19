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
import ContainerResource
import ContainerVersion
import ContainerizationExtras
import ContainerizationOS
import Foundation
import MachineAPIClient

extension Application {
    public struct Dashboard: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "dash",
            abstract: "Full-screen terminal dashboard for containers, images, machines, volumes and networks"
        )

        @OptionGroup
        public var logOptions: Flags.Logging

        @Option(name: .long, help: "Seconds between refreshes")
        var interval: Double = 2

        public func run() async throws {
            guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
                throw ValidationError("container dash needs an interactive terminal")
            }
            let terminal = try Terminal(descriptor: STDIN_FILENO)
            var view = DashboardView()
            var cpu = CPUSampler()
            var lastLoad = Date.distantPast
            var dirty = true
            var lastFrame = ""

            // Ctrl-C in a child (`logs --follow`) also signals us. A handler, unlike SIG_IGN, is reset on exec,
            // so the child still stops on Ctrl-C while the dashboard survives.
            signal(SIGINT) { _ in }
            Self.enter(terminal)
            defer { Self.leave(terminal) }

            while true {
                if dirty || Date().timeIntervalSince(lastLoad) >= interval {
                    await Self.load(&view, cpu: &cpu)
                    lastLoad = Date()
                    dirty = false
                }
                let size = (try? terminal.size).map { (Int($0.width), Int($0.height)) } ?? (100, 30)
                let frame = view.render(width: size.0, height: size.1)
                if frame != lastFrame {
                    Self.write(frame)
                    lastFrame = frame
                }

                // Short poll so window resizes repaint quickly; data reloads on `interval`.
                var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                guard poll(&fds, 1, 250) > 0 else { continue }
                var buffer = [UInt8](repeating: 0, count: 64)
                let n = read(STDIN_FILENO, &buffer, buffer.count)
                guard n > 0 else { continue }

                for key in DashboardView.parseKeys(Array(buffer.prefix(n))) {
                    switch Self.handle(key, &view) {
                    case .none:
                        break
                    case .quit:
                        return
                    case .reload:
                        dirty = true
                    case .sequence(let commands):
                        for args in commands {
                            view.message = "container \(args.joined(separator: " ")) …"
                            Self.write(view.render(width: size.0, height: size.1))
                            let result = Self.runCLI(args)
                            view.message = result.message
                            if !result.ok { break }
                        }
                        dirty = true
                    case .run(let args, let interactive):
                        if interactive {
                            Self.leave(terminal)
                            let result = Self.runInteractive(args)
                            // Keep the output readable when the command failed or only prints and exits.
                            if !result.ok || args.first == "system" {
                                print("\n\(result.message). Press Enter to return to the dashboard.")
                                _ = readLine()
                            }
                            Self.enter(terminal)
                            lastFrame = ""
                        } else {
                            view.message = "container \(args.joined(separator: " ")) …"
                            Self.write(view.render(width: size.0, height: size.1))
                            view.message = Self.runCLI(args).message
                        }
                        dirty = true
                    }
                }
            }
        }

        enum Action: Equatable {
            case none, quit, reload
            case run([String], interactive: Bool)
            /// Non-interactive commands run in order, stopping at the first failure.
            case sequence([[String]])
        }

        /// Maps a key to an action for the current tab and selection. Pure, apart from `view`.
        static func handle(_ key: DashboardView.Key, _ view: inout DashboardView) -> Action {
            if let id = view.confirmDelete {
                view.confirmDelete = nil
                guard key == .char("y") || key == .char("Y") else {
                    view.message = "Delete cancelled"
                    return .none
                }
                let args: [String]
                switch DashboardView.tabs[view.tab] {
                case "Containers": args = ["delete", "--force", id]
                case "Images": args = ["image", "delete", id]
                case "Machines": args = ["machine", "delete", id]
                case "Volumes": args = ["volume", "delete", id]
                default: args = ["network", "delete", id]
                }
                return .run(args, interactive: false)
            }
            if view.filtering {
                switch key {
                case .enter: view.filtering = false
                case .escape:
                    view.filtering = false
                    view.filter = ""
                case .backspace: _ = view.filter.popLast()
                case .char(let c): view.filter.append(c)
                default: break
                }
                view.clampSelection()
                return .none
            }

            view.message = ""
            let tab = DashboardView.tabs[view.tab]
            let row = view.selectedRow
            switch key {
            case .up, .char("k"):
                view.selected -= 1
                view.clampSelection()
            case .down, .char("j"):
                view.selected += 1
                view.clampSelection()
            case .tab, .backTab:
                let step = key == .tab ? 1 : DashboardView.tabs.count - 1
                view.tab = (view.tab + step) % DashboardView.tabs.count
                view.selected = 0
                view.rows = []
                return .reload
            case .char("q"): return .quit
            case .char("?"): view.showHelp.toggle()
            case .char("/"): view.filtering = true
            case .escape:
                view.filter = ""
                view.showHelp = false
            case .char("S"): return .run(["system", "start"], interactive: true)
            case .char("d"):
                if let row { view.confirmDelete = row.id }
            case .char("s"):
                guard let row else { break }
                if tab == "Containers" { return .run([row.running ? "stop" : "start", row.id], interactive: false) }
                if tab == "Machines" { return .run(row.running ? ["machine", "stop", row.id] : ["machine", "run", "-n", row.id, "true"], interactive: false) }
            case .char("r"):
                if tab == "Containers", let row { return .sequence([["stop", row.id], ["start", row.id]]) }
            case .char("e"):
                guard let row else { break }
                if tab == "Containers" { return .run(["exec", "-it", row.id, "sh"], interactive: true) }
                if tab == "Machines" { return .run(["machine", "run", "-n", row.id], interactive: true) }
            case .char("l"):
                guard let row else { break }
                if tab == "Containers" { return .run(["logs", "--follow", row.id], interactive: true) }
                if tab == "Machines" { return .run(["machine", "logs", "--follow", row.id], interactive: true) }
            default: break
            }
            return .none
        }

        static func load(_ view: inout DashboardView, cpu: inout CPUSampler) async {
            do {
                switch DashboardView.tabs[view.tab] {
                case "Containers":
                    let client = ContainerClient()
                    let containers = try await client.list(filters: ContainerListFilters.all.withoutMachines())
                    view.header = ["ID", "IMAGE", "STATE", "IP", "CPU %", "MEM USED", "CPUS", "MEMORY", "STARTED"]
                    var rows: [DashboardView.Row] = []
                    for snapshot in containers {
                        let running = snapshot.status == .running
                        let stats = running ? try? await client.stats(id: snapshot.id) : nil
                        let config = snapshot.configuration
                        let cpuPercent = stats == nil ? "" : cpu.percent(id: snapshot.id, usec: stats?.cpuUsageUsec)
                        let memoryUsed = stats?.memoryUsageBytes.map { "\($0 / (1024 * 1024)) MB" } ?? ""
                        let cells: [String] = [
                            snapshot.id,
                            Self.shortImage(config.image.reference),
                            snapshot.status.rawValue,
                            snapshot.networks.map { $0.ipv4Address.address.description }.joined(separator: ","),
                            cpuPercent,
                            memoryUsed,
                            "\(config.resources.cpus)",
                            "\(config.resources.memoryInBytes / (1024 * 1024)) MB",
                            snapshot.startedDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "",
                        ]
                        rows.append(.init(id: snapshot.id, cells: cells, running: running))
                    }
                    view.rows = rows
                case "Images":
                    let config = try await ClientHealthCheck.loadContainerSystemConfig()
                    var resources: [ImageResource] = []
                    for image in try await ClientImage.list()
                    where !Utility.isInfraImage(name: image.reference, builderImage: config.build.image, initImage: config.vminit.image) {
                        resources.append(try await image.toImageResource(containerSystemConfig: config))
                    }
                    view.header = ImageResource.tableHeader
                    view.rows = resources.map { .init(id: $0.quietValue, cells: $0.tableRow) }
                case "Machines":
                    let machines = try await MachineClient().list()
                    view.header = ["NAME", "IP", "CPUS", "STATE"]
                    view.rows = machines.map {
                        .init(id: $0.id, cells: [$0.id, $0.ipAddress ?? "-", "\($0.bootConfig.cpus)", $0.status.rawValue], running: $0.status == .running)
                    }
                case "Volumes":
                    let volumes = try await ClientVolume.list().map { VolumeResource(configuration: $0) }
                    view.header = VolumeResource.tableHeader
                    view.rows = volumes.map { .init(id: $0.quietValue, cells: $0.tableRow) }
                default:
                    let networks = try await NetworkClient().list()
                    view.header = NetworkResource.tableHeader
                    view.rows = networks.map { .init(id: $0.quietValue, cells: $0.tableRow) }
                }
                view.clampSelection()
            } catch {
                view.header = []
                view.rows = []
                view.message = "Press S to run `container system start`. Cannot reach the API server: \(error)"
            }
        }

        /// Runs this binary in the foreground with the terminal attached. Foundation's Process would put the
        /// child in its own process group, where reading the terminal stops it with SIGTTIN.
        static func runInteractive(_ args: [String]) -> (ok: Bool, message: String) {
            let argv = ([CommandLine.executablePath.string] + args).map { strdup($0) } + [nil]
            defer { argv.forEach { free($0) } }
            // Start the child with no blocked signals and default handlers, so Ctrl-C stops `logs --follow`.
            var attr: posix_spawnattr_t?
            posix_spawnattr_init(&attr)
            defer { posix_spawnattr_destroy(&attr) }
            var empty = sigset_t()
            sigemptyset(&empty)
            var defaults = sigset_t()
            sigemptyset(&defaults)
            for sig in [SIGINT, SIGQUIT, SIGTERM, SIGTSTP] { sigaddset(&defaults, sig) }
            posix_spawnattr_setsigmask(&attr, &empty)
            posix_spawnattr_setsigdefault(&attr, &defaults)
            posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
            var pid: pid_t = 0
            let rc = posix_spawn(&pid, argv[0], nil, &attr, argv, environ)
            guard rc == 0 else {
                return (false, "failed to run container \(args.joined(separator: " ")): \(String(cString: strerror(rc)))")
            }
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            // WEXITSTATUS: exit code when the child exited normally, otherwise report the raw status.
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : status
            // 130 is how Ctrl-C ends `logs --follow`, the normal way back to the dashboard.
            let ok = code == 0 || code == 130
            return (ok, "container \(args.joined(separator: " ")): \(ok ? "done" : "failed (exit \(code))")")
        }

        /// Runs this same binary as a child with its output captured, so every action reuses the normal command code.
        static func runCLI(_ args: [String]) -> (ok: Bool, message: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.executablePath.string)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return (false, "failed to run container \(args.joined(separator: " ")): \(error)")
            }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            let last = output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            let verdict = process.terminationStatus == 0 ? "done" : "failed (exit \(process.terminationStatus))"
            return (process.terminationStatus == 0, "container \(args.joined(separator: " ")): \(verdict)\(last.isEmpty ? "" : " — \(last)")")
        }

        /// `docker.io/library/alpine:latest` → `alpine:latest`, as people type it.
        static func shortImage(_ reference: String) -> String {
            reference.hasPrefix("docker.io/library/") ? String(reference.dropFirst("docker.io/library/".count)) : reference
        }

        static func enter(_ terminal: Terminal) {
            // A child (`exec -it`) may leave the shared tty non-blocking; writes would then fail with EAGAIN.
            for fd in [STDIN_FILENO, STDOUT_FILENO] {
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
            }
            try? terminal.setrawNoOutputProcessing()
            write("\u{1b}[?1049h\u{1b}[?25l")
        }

        static func leave(_ terminal: Terminal) {
            write("\u{1b}[?25h\u{1b}[?1049l")
            terminal.tryReset()
        }

        static func write(_ text: String) {
            FileHandle.standardOutput.write(Data(text.utf8))
        }
    }
}

/// CPU % between two refreshes, from the cgroup's cumulative usage counter.
struct CPUSampler {
    private var last: [String: (usec: UInt64, at: Date)] = [:]

    mutating func percent(id: String, usec: UInt64?, now: Date = Date()) -> String {
        guard let usec else { return "" }
        defer { last[id] = (usec, now) }
        guard let previous = last[id], usec >= previous.usec else { return "…" }
        let wall = now.timeIntervalSince(previous.at) * 1_000_000
        guard wall > 0 else { return "…" }
        return String(format: "%.1f", Double(usec - previous.usec) / wall * 100)
    }
}
