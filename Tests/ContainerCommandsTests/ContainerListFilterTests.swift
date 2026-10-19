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

import Testing

@testable import ContainerCommands

struct ContainerListFilterTests {
    @Test func labelKeyAndValue() throws {
        let labels = try Application.ContainerList.labelFilters(["label=app=web.1", "label=tier"])
        #expect(labels == ["app": "^web\\.1$", "tier": ".+"])
    }

    @Test func valueMayContainEquals() throws {
        let labels = try Application.ContainerList.labelFilters(["label=k=a=b"])
        #expect(labels == ["k": "^a=b$"])
    }

    @Test func rejectsUnknownFilters() {
        #expect(throws: (any Error).self) { try Application.ContainerList.labelFilters(["status=running"]) }
        #expect(throws: (any Error).self) { try Application.ContainerList.labelFilters(["label="]) }
    }
}
