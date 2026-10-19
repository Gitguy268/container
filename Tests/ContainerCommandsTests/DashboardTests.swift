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

import Foundation
import Testing

@testable import ContainerCommands

struct DashboardTests {
    private func sample() -> DashboardView {
        var view = DashboardView()
        view.header = ["ID", "STATE"]
        view.rows = [
            .init(id: "web", cells: ["web", "running"], running: true),
            .init(id: "db", cells: ["db", "stopped"]),
        ]
        return view
    }

    @Test func parsesArrowsTabsAndChars() {
        let keys = DashboardView.parseKeys([0x1b, 0x5b, 0x41, 0x1b, 0x5b, 0x42, 0x09, 0x1b, 0x5b, 0x5a, 0x71, 0x0d, 0x7f, 0x1b])
        #expect(keys == [.up, .down, .tab, .backTab, .char("q"), .enter, .backspace, .escape])
    }

    @Test func renderHighlightsSelectionAndFitsHeight() {
        var view = sample()
        view.selected = 1
        let frame = view.render(width: 60, height: 12)
        let lines = frame.components(separatedBy: "\r\n")
        #expect(lines.count == 12)
        #expect(frame.contains("\u{1b}[7m db"))
        #expect(!frame.contains("\u{1b}[7m web"))
    }

    @Test func filterNarrowsRowsAndSelection() {
        var view = sample()
        _ = Application.Dashboard.handle(.char("/"), &view)
        for c in "stop" { _ = Application.Dashboard.handle(.char(c), &view) }
        _ = Application.Dashboard.handle(.enter, &view)
        #expect(view.visibleRows.map(\.id) == ["db"])
        #expect(view.selectedRow?.id == "db")
    }

    @Test func actionsForContainers() {
        var view = sample()
        #expect(Application.Dashboard.handle(.char("s"), &view) == .run(["stop", "web"], interactive: false))
        #expect(Application.Dashboard.handle(.char("e"), &view) == .run(["exec", "-it", "web", "sh"], interactive: true))
        #expect(Application.Dashboard.handle(.char("r"), &view) == .sequence([["stop", "web"], ["start", "web"]]))
        _ = Application.Dashboard.handle(.down, &view)
        #expect(Application.Dashboard.handle(.char("s"), &view) == .run(["start", "db"], interactive: false))
    }

    @Test func deleteAsksFirst() {
        var view = sample()
        #expect(Application.Dashboard.handle(.char("d"), &view) == .none)
        #expect(view.statusLine == "Delete web? y/n")
        #expect(Application.Dashboard.handle(.char("n"), &view) == .none)
        #expect(view.confirmDelete == nil)
        _ = Application.Dashboard.handle(.char("d"), &view)
        #expect(Application.Dashboard.handle(.char("y"), &view) == .run(["delete", "--force", "web"], interactive: false))
    }

    @Test func tabSwitchWrapsAndReloads() {
        var view = sample()
        #expect(Application.Dashboard.handle(.backTab, &view) == .reload)
        #expect(DashboardView.tabs[view.tab] == "Networks")
        #expect(Application.Dashboard.handle(.tab, &view) == .reload)
        #expect(view.tab == 0)
    }

    @Test func cpuSamplerUsesDeltaOverWallTime() {
        var sampler = CPUSampler()
        let t0 = Date(timeIntervalSince1970: 0)
        #expect(sampler.percent(id: "a", usec: 1_000_000, now: t0) == "…")
        #expect(sampler.percent(id: "a", usec: 2_000_000, now: t0.addingTimeInterval(2)) == "50.0")
    }
}
