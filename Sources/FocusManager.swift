import SwiftUI
import Combine

enum FocusItem: Equatable, Hashable {
    case tab(LauncherTab)

    case launchGame
    case offlineMode
    case sideCard(Int) // 0=multiplayer, 1=zombies, 2=workshop
}

final class FocusManager: ObservableObject {
    @Published var focused: FocusItem? = nil
    @Published var selectedTab: LauncherTab = .whatsNew

    private let controller = ControllerManager.shared

    init() {
        controller.onDirection = { [weak self] dir in self?.move(dir) }
        controller.onAction = { [weak self] in self?.activate() }
        controller.onCancel = { [weak self] in self?.cancel() }
        controller.onTriangle = { [weak self] in self?.onLaunch?() }
    }

    var onLaunch: (() -> Void)?
    var onLaunchOffline: (() -> Void)?

    private var orderedItems: [FocusItem] {
        switch selectedTab {
        case .whatsNew:
            return layout_whatsNew
        case .dlc, .mods:
            return layout_header
        }
    }

    private var layout_header: [FocusItem] {
        [
            .tab(.whatsNew), .tab(.dlc), .tab(.mods),
        ]
    }

    private var layout_whatsNew: [FocusItem] {
        [
            .tab(.whatsNew), .tab(.dlc), .tab(.mods),
            .launchGame, .offlineMode,
            .sideCard(0), .sideCard(1), .sideCard(2),
        ]
    }

    // 2D grid layout for spatial navigation
    // Each row is an array of items on that visual row
    private var grid: [[FocusItem]] {
        switch selectedTab {
        case .whatsNew:
            return [
                [.tab(.whatsNew), .tab(.dlc), .tab(.mods)],
                [.launchGame, .offlineMode, .sideCard(0)],
                [.launchGame, .offlineMode, .sideCard(1)],
                [.launchGame, .offlineMode, .sideCard(2)],
            ]
        case .dlc, .mods:
            return [
                [.tab(.whatsNew), .tab(.dlc), .tab(.mods)],
            ]
        }
    }

    private func gridPosition(of item: FocusItem) -> (row: Int, col: Int)? {
        for (r, row) in grid.enumerated() {
            if let c = row.firstIndex(of: item) {
                return (r, c)
            }
        }
        return nil
    }

    func move(_ direction: ControllerDirection) {
        let items = orderedItems
        guard !items.isEmpty else { return }

        if focused == nil {
            focused = items.first
            return
        }

        guard let current = focused,
              let pos = gridPosition(of: current) else {
            focused = items.first
            return
        }

        switch direction {
        case .left:
            let row = grid[pos.row]
            if pos.col > 0 {
                let newItem = row[pos.col - 1]
                if newItem != current { focused = newItem }
                else if pos.col >= 2 { focused = row[pos.col - 2] }
            }
        case .right:
            let row = grid[pos.row]
            if pos.col < row.count - 1 {
                let newItem = row[pos.col + 1]
                if newItem != current { focused = newItem }
                else if pos.col + 2 < row.count { focused = row[pos.col + 2] }
            }
        case .up:
            if pos.row > 0 {
                let targetRow = grid[pos.row - 1]
                let col = min(pos.col, targetRow.count - 1)
                focused = targetRow[col]
            }
        case .down:
            if pos.row < grid.count - 1 {
                let targetRow = grid[pos.row + 1]
                let col = min(pos.col, targetRow.count - 1)
                focused = targetRow[col]
            }
        }
    }

    func activate() {
        guard let item = focused else {
            focused = orderedItems.first
            return
        }

        switch item {
        case .tab(let tab):
            selectedTab = tab
        case .launchGame:
            onLaunch?()
        case .offlineMode:
            onLaunchOffline?()
        case .sideCard(let idx):
            switch idx {
            case 1: onLaunch?()
            case 2: NSWorkspace.shared.open(URL(string: "https://steamcommunity.com/app/311210/workshop/")!)
            default: break
            }
        }
    }

    func cancel() {
        if focused != nil {
            focused = nil
        }
    }
}
