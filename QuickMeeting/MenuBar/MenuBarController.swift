//
//  MenuBarController.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: AppViewModel) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 220, height: 120)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(viewModel: viewModel)
        )

        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self
        applyIconState(viewModel.menuBarIconState)

        viewModel.$recordingState
            .combineLatest(viewModel.$isAutoRecordingStartPending)
            .sink { [weak self, weak viewModel] _, _ in
                guard let self, let viewModel else {
                    return
                }

                self.applyIconState(viewModel.menuBarIconState)
            }
            .store(in: &cancellables)
    }

    private func applyIconState(_ state: MenuBarIconState) {
        statusItem.button?.image = MenuBarIconImageBuilder.makeImage(for: state)
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
