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
import ContainerResource
import ContainerizationError

extension Application {
    public struct ContainerWait: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "wait",
            abstract: "Block until one or more containers stop, then print their exit codes")

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Container IDs")
        var containerIds: [String]

        public func run() async throws {
            let client = ContainerClient()
            for id in containerIds {
                // shortcut: polls the snapshot every 250ms; add a wait route to the API server if this is ever hot.
                var snapshot = try await client.get(id: id)
                while snapshot.status != .stopped {
                    try await Task.sleep(for: .milliseconds(250))
                    snapshot = try await client.get(id: id)
                }
                guard let code = snapshot.exitCode else {
                    throw ContainerizationError(.notFound, message: "container \(id) stopped without a recorded exit code")
                }
                print(code)
            }
        }
    }
}
