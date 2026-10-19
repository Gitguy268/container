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

/// Pure state, key parsing and rendering for `container dash`, kept free of I/O so it can be tested.
struct DashboardView {
    struct Row: Equatable {
        var id: String
        var cells: [String]
        var running: Bool = false
    }

    enum Key: Equatable {
        case up, down, tab, backTab, enter, escape, backspace
        case char(Character)
    }

    static let tabs = ["Containers", "Images", "Machines", "Volumes", "Networks"]

    var tab = 0
    var selected = 0
    var header: [String] = []
    var rows: [Row] = []
    var filter = ""
    var filtering = false
    var message = ""
    /// Id waiting for a y/n answer before it is deleted.
    var confirmDelete: String?
    var showHelp = false

    var visibleRows: [Row] {
        guard !filter.isEmpty else { return rows }
        return rows.filter { $0.cells.joined(separator: " ").localizedCaseInsensitiveContains(filter) }
    }

    var selectedRow: Row? {
        let visible = visibleRows
        return visible.indices.contains(selected) ? visible[selected] : nil
    }

    mutating func clampSelection() {
        selected = max(0, min(selected, visibleRows.count - 1))
    }

    static func parseKeys(_ bytes: [UInt8]) -> [Key] {
        var keys: [Key] = []
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x1b, i + 2 < bytes.count, bytes[i + 1] == UInt8(ascii: "[") {
                switch bytes[i + 2] {
                case UInt8(ascii: "A"): keys.append(.up)
                case UInt8(ascii: "B"): keys.append(.down)
                case UInt8(ascii: "Z"): keys.append(.backTab)
                default: break
                }
                i += 3
                continue
            }
            switch b {
            case 0x1b: keys.append(.escape)
            case 0x09: keys.append(.tab)
            case 0x0d, 0x0a: keys.append(.enter)
            case 0x7f, 0x08: keys.append(.backspace)
            case 0x03: keys.append(.char("q"))  // Ctrl-C quits too
            default:
                if b >= 0x20, b < 0x7f { keys.append(.char(Character(UnicodeScalar(b)))) }
            }
            i += 1
        }
        return keys
    }

    /// Renders one full frame. Lines end in CRLF because the terminal is in raw mode.
    func render(width: Int, height: Int) -> String {
        let width = max(width, 20)
        var lines: [String] = []

        let tabLine = Self.tabs.enumerated().map { i, name in
            i == tab ? "\u{1b}[7m \(name) \u{1b}[0m" : " \(name) "
        }.joined(separator: "│")
        lines.append(" container dash  " + tabLine)
        lines.append(String(repeating: "─", count: width))

        if showHelp {
            lines.append(contentsOf: Self.help)
        } else {
            let visible = visibleRows
            let widths = Self.columnWidths(header: header, rows: visible.map(\.cells))
            lines.append("\u{1b}[1m" + Self.fit(Self.line(header, widths), width) + "\u{1b}[0m")
            let bodyHeight = max(1, height - 6)
            let start = max(0, min(selected - bodyHeight + 1, visible.count - bodyHeight))
            for (offset, row) in visible.dropFirst(start).prefix(bodyHeight).enumerated() {
                let text = Self.fit(Self.line(row.cells, widths), width)
                lines.append(start + offset == selected ? "\u{1b}[7m" + text + "\u{1b}[0m" : text)
            }
            if visible.isEmpty {
                lines.append(filter.isEmpty ? "  (none)" : "  (nothing matches \"\(filter)\")")
            }
        }

        while lines.count < height - 2 {
            lines.append("")
        }
        lines = Array(lines.prefix(max(height - 2, 3)))
        lines.append(String(repeating: "─", count: width))
        lines.append(Self.fit(statusLine, width))

        // Clear each line so shorter frames do not leave old text behind.
        return "\u{1b}[H" + lines.map { $0 + "\u{1b}[K" }.joined(separator: "\r\n") + "\u{1b}[J"
    }

    var statusLine: String {
        if let confirmDelete {
            return "Delete \(confirmDelete)? y/n"
        }
        if filtering {
            return "/\(filter)█"
        }
        if !message.isEmpty {
            return message
        }
        return "↑↓ select  tab switch  s start/stop  r restart  e shell  l logs  d delete  / filter  ? help  q quit"
    }

    static let help = [
        "  ↑ ↓ / j k   move the selection",
        "  tab / ⇧tab  next / previous tab",
        "  s           start or stop the selected container or machine",
        "  r           restart the selected container",
        "  e           open a shell (container exec -it … sh, or machine run)",
        "  l           follow logs (Ctrl-C to return)",
        "  d           delete the selected item (asks first)",
        "  /           filter rows; esc clears",
        "  S           run `container system start`",
        "  q           quit",
    ]

    static func columnWidths(header: [String], rows: [[String]]) -> [Int] {
        var widths = header.map(\.count)
        for row in rows {
            for (i, cell) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }
        return widths
    }

    static func line(_ cells: [String], _ widths: [Int]) -> String {
        " "
            + cells.enumerated().map { i, cell in
                i < widths.count ? cell.padding(toLength: widths[i], withPad: " ", startingAt: 0) : cell
            }.joined(separator: "  ")
    }

    static func fit(_ text: String, _ width: Int) -> String {
        text.count > width ? String(text.prefix(width - 1)) + "…" : text
    }
}
