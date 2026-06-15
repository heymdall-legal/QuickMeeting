//
//  MenuBarController.swift
//  QuickMeeting
//

import AppKit
import Combine
import SwiftData
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let hostingController: NSHostingController<AnyView>
    private var cancellables = Set<AnyCancellable>()
    private var sizeObservation: NSKeyValueObservation?
    private var elapsedTimer: Timer?
    private weak var viewModel: AppViewModel?

    init(
        viewModel: AppViewModel,
        autoRecordingViewModel: AutoRecordingSettingsViewModel,
        modelContainer: ModelContainer,
        onOpenMainWindow: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover.behavior = .transient

        let menuBarView = MenuBarView(
            viewModel: viewModel,
            autoRecordingViewModel: autoRecordingViewModel,
            onOpenMainWindow: onOpenMainWindow
        )
        .modelContainer(modelContainer)

        hostingController = NSHostingController(rootView: AnyView(menuBarView))
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 320, height: 360)

        // On macOS 13+, let the hosting controller track the SwiftUI view's natural size
        // and propagate it back to the popover via KVO.
        if #available(macOS 13, *) {
            hostingController.sizingOptions = [.preferredContentSize]
        }
        sizeObservation = hostingController.observe(\.preferredContentSize, options: [.new]) { [weak self] vc, change in
            guard let self, let size = change.newValue, size.height > 0 else { return }
            DispatchQueue.main.async { self.popover.contentSize = size }
        }

        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self
        applyIconState(viewModel.menuBarIconState)

        viewModel.$recordingState
            .combineLatest(viewModel.$isAutoRecordingStartPending)
            .sink { [weak self, weak viewModel] _, _ in
                guard let self, let viewModel else { return }
                self.applyIconState(viewModel.menuBarIconState)
            }
            .store(in: &cancellables)
    }

    private func applyIconState(_ state: MenuBarIconState) {
        statusItem.button?.image = MenuBarIconImageBuilder.makeImage(for: state)

        switch state {
        case .recording:
            statusItem.button?.imagePosition = .imageLeft
            startElapsedTimer()
            updateElapsedTitle()
        default:
            stopElapsedTimer()
            statusItem.button?.attributedTitle = NSAttributedString()
            statusItem.button?.imagePosition = .imageOnly
        }
    }

    private func startElapsedTimer() {
        guard elapsedTimer == nil else { return }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateElapsedTitle() }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsedTitle() {
        guard let startedAt = viewModel?.recordingStartedAt else {
            statusItem.button?.attributedTitle = NSAttributedString()
            return
        }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let text = String(format: " %d:%02d", elapsed / 60, elapsed % 60)
        statusItem.button?.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            ]
        )
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
