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
import ContainerizationError
import Foundation

extension Application {
    public struct SystemPrune: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Remove stopped containers, unused networks and dangling images (and unused volumes with --volumes)"
        )

        @OptionGroup
        public var logOptions: Flags.Logging

        @Flag(name: .shortAndLong, help: "Remove all unused images, not just dangling ones")
        var all = false

        @Flag(name: .long, help: "Also remove unused volumes")
        var volumes = false

        @Flag(name: .shortAndLong, help: "Do not ask for confirmation")
        var force = false

        public func run() async throws {
            if !force {
                let what = volumes ? "stopped containers, unused networks, images and volumes" : "stopped containers, unused networks and images"
                print("This removes all \(what). Continue? [y/N] ", terminator: "")
                guard readLine()?.lowercased().hasPrefix("y") == true else {
                    throw ContainerizationError(.cancelled, message: "prune cancelled")
                }
            }
            // Containers first, so the networks, images and volumes they held become unused.
            try await ContainerPrune.parse([]).run()
            try await NetworkCommand.NetworkPrune.parse([]).run()
            try await ImagePrune.parse(all ? ["--all"] : []).run()
            if volumes {
                try await VolumeCommand.VolumePrune.parse([]).run()
            }
        }
    }
}
