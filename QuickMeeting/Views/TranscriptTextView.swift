import SwiftUI
#if canImport(AppKit)
import AppKit

struct TranscriptTextView: NSViewRepresentable {
    let display: MeetingTranscriptDisplay
    let showSegmentTimes: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let documentView = TranscriptDocumentView()
        documentView.update(display: display, showSegmentTimes: showSegmentTimes, availableWidth: 700)

        scrollView.documentView = documentView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let documentView = scrollView.documentView as? TranscriptDocumentView else {
            return
        }

        documentView.update(
            display: display,
            showSegmentTimes: showSegmentTimes,
            availableWidth: max(scrollView.contentSize.width, 240)
        )
    }
}

final class TranscriptDocumentView: NSView {
    private let timestampContainerView = FlippedView()
    private let transcriptTextView = NSTextView()
    private let timestampColumnWidth: CGFloat = 56
    private let columnSpacing: CGFloat = 16
    private var timestampLabels = [NSTextField]()

    var transcriptString: String {
        transcriptTextView.string
    }

    var timestampStrings: [String] {
        timestampLabels.map(\.stringValue)
    }

    var timestampOrigins: [CGFloat] {
        timestampLabels.map { $0.frame.minY }
    }

    var isTimestampContainerFlipped: Bool {
        timestampContainerView.isFlipped
    }

    override var isFlipped: Bool {
        true
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(display: MeetingTranscriptDisplay, showSegmentTimes: Bool, availableWidth: CGFloat) {
        let layout = makeTranscriptLayout(from: display)
        transcriptTextView.textStorage?.setAttributedString(layout.attributedString)

        timestampContainerView.isHidden = !showSegmentTimes
        updateLayout(layout: layout, showSegmentTimes: showSegmentTimes, availableWidth: availableWidth)
    }

    private func configureViews() {
        timestampContainerView.isHidden = true
        configureTranscriptTextView()

        addSubview(timestampContainerView)
        addSubview(transcriptTextView)
    }

    private func configureTranscriptTextView() {
        transcriptTextView.isEditable = false
        transcriptTextView.isSelectable = true
        transcriptTextView.drawsBackground = false
        transcriptTextView.isRichText = false
        transcriptTextView.importsGraphics = false
        transcriptTextView.usesFindBar = true
        transcriptTextView.allowsUndo = false
        transcriptTextView.textContainerInset = .zero
        transcriptTextView.textContainer?.lineFragmentPadding = 0
        transcriptTextView.textContainer?.widthTracksTextView = true
        transcriptTextView.isHorizontallyResizable = false
        transcriptTextView.isVerticallyResizable = true
        transcriptTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        transcriptTextView.minSize = .zero
    }

    private func updateLayout(layout: TranscriptLayout, showSegmentTimes: Bool, availableWidth: CGFloat) {
        let width = max(availableWidth, 240)
        let timestampWidth = showSegmentTimes ? timestampColumnWidth : 0
        let spacing = showSegmentTimes ? columnSpacing : 0
        let transcriptWidth = max(width - timestampWidth - spacing, 120)

        let transcriptHeight = measuredHeight(for: transcriptTextView, width: transcriptWidth)
        transcriptTextView.frame = NSRect(
            x: timestampWidth + spacing,
            y: 0,
            width: transcriptWidth,
            height: transcriptHeight
        )

        if showSegmentTimes {
            let timestampHeight = updateTimestampLabels(layout.timestampAnchors)
            timestampContainerView.frame = NSRect(x: 0, y: 0, width: timestampWidth, height: timestampHeight)
            frame = NSRect(x: 0, y: 0, width: width, height: max(transcriptHeight, timestampHeight))
        } else {
            clearTimestampLabels()
            timestampContainerView.frame = .zero
            frame = NSRect(x: 0, y: 0, width: width, height: transcriptHeight)
        }
    }

    private func measuredHeight(for textView: NSTextView, width: CGFloat) -> CGFloat {
        guard let textContainer = textView.textContainer, let layoutManager = textView.layoutManager else {
            return 0
        }

        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = false
        textView.frame.size.width = width
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return max(ceil(usedRect.height + (textView.textContainerInset.height * 2)), 1)
    }

    private func updateTimestampLabels(_ anchors: [TranscriptTimestampAnchor]) -> CGFloat {
        clearTimestampLabels()

        guard
            let textContainer = transcriptTextView.textContainer,
            let layoutManager = transcriptTextView.layoutManager
        else {
            return 0
        }

        layoutManager.ensureLayout(for: textContainer)
        let textOrigin = transcriptTextView.textContainerOrigin
        var maxY: CGFloat = 0

        for anchor in anchors {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: anchor.characterRange, actualCharacterRange: nil)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let label = NSTextField(labelWithString: anchor.timestampText)
            label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .left
            label.lineBreakMode = .byClipping
            label.frame = NSRect(
                x: 0,
                y: ceil(textOrigin.y + glyphRect.minY),
                width: timestampColumnWidth,
                height: ceil(label.intrinsicContentSize.height)
            )
            timestampContainerView.addSubview(label)
            timestampLabels.append(label)
            maxY = max(maxY, label.frame.maxY)
        }

        return max(maxY, 1)
    }

    private func clearTimestampLabels() {
        timestampLabels.forEach { $0.removeFromSuperview() }
        timestampLabels.removeAll()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}
#endif
