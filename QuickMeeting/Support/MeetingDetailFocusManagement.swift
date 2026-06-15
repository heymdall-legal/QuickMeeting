#if canImport(AppKit)
import AppKit
import SwiftUI

@MainActor
func clearMeetingDetailFocus(in window: NSWindow?) {
    guard let window else { return }
    window.endEditing(for: nil)
    window.makeFirstResponder(nil)
}

struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = true
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            window = nsView.window
        }
    }
}
#endif
