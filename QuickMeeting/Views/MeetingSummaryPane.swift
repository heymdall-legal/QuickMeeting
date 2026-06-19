#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

enum SummaryPaneState {
    case idle
    case generating
    case ready(String)
    case failed(String)
}

struct MeetingSummaryPane: View {
    let state: SummaryPaneState
    let actionTitle: String
    let onGenerate: () -> Void

    var body: some View {
        switch state {
        case .idle:
            idleView
        case .generating:
            generatingView
        case .ready(let text):
            readyView(text: text)
        case .failed(let message):
            failedView(message: message)
        }
    }

    // MARK: Idle

    private var idleView: some View {
        VStack(spacing: 0) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(QMTheme.faint)
                .frame(width: 56, height: 56)
                .background(QMTheme.chip, in: Circle())
                .padding(.bottom, 18)

            Text("No summary yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(QMTheme.ink)
                .padding(.bottom, 6)

            Text("Generate an AI summary with key decisions, action items, and next steps.")
                .font(.system(size: 13.5))
                .foregroundStyle(QMTheme.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.bottom, 20)

            Button(action: onGenerate) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(QMTheme.sage, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    // MARK: Generating

    private var generatingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Generating summary…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(QMTheme.ink)
                .padding(.bottom, 4)
            Text("This may take a moment.")
                .font(.system(size: 13))
                .foregroundStyle(QMTheme.tertiary)
                .padding(.bottom, 18)

            SummaryShimmerBar()
                .frame(height: 5)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(skeletonWidths.enumerated()), id: \.offset) { _, width in
                    SummarySkeletonLine(maxWidth: width)
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private let skeletonWidths: [CGFloat?] = [nil, nil, 280, nil, nil, 220, nil, nil, 300, nil, 180]

    // MARK: Ready

    private func readyView(text: String) -> some View {
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summaryContentView(text: text)
                    Color.clear.frame(height: 32)
                }
                .padding(.horizontal, 30)
                .padding(.top, 12)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(QMTheme.danger)
                .frame(width: 56, height: 56)
                .background(QMTheme.chip, in: Circle())
                .padding(.bottom, 18)

            Text("Summary failed")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(QMTheme.ink)
                .padding(.bottom, 6)

            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(QMTheme.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.bottom, 20)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    // MARK: Helpers

    @ViewBuilder
    private func summaryContentView(text: String) -> some View {
        let bubbleMetrics = MeetingBubbleShellMetrics.transcript

        Group {
            if let markdown = makeMeetingSummaryDisplayAttributedString(from: text) {
                Text(markdown)
            } else {
                Text(text)
                    .font(.system(size: 14.5))
                    .lineSpacing(4)
            }
        }
        .foregroundStyle(QMTheme.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .modifier(
            MeetingBubbleShell(
                metrics: bubbleMetrics,
                background: QMTheme.chip,
                borderColor: .clear,
                borderWidth: 0
            )
        )
    }
}

private func makeMeetingSummaryDisplayAttributedString(from markdown: String) -> AttributedString? {
    #if canImport(AppKit)
    guard
        let attributedString = try? makeMeetingSummaryAttributedString(from: markdown),
        let displayString = try? AttributedString(attributedString, including: \.appKit)
    else {
        return nil
    }
    return displayString
    #else
    return nil
    #endif
}

#if canImport(AppKit)
func makeMeetingSummaryAttributedString(from markdown: String) throws -> NSAttributedString {
    let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
    let lines = normalizedMarkdown.components(separatedBy: "\n")
    let rendered = NSMutableAttributedString()
    var pendingBlankLine = false

    for line in lines {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        if trimmedLine.isEmpty {
            pendingBlankLine = rendered.length > 0
            continue
        }

        if rendered.length > 0 {
            rendered.append(
                NSAttributedString(
                    string: pendingBlankLine ? "\n\n" : "\n",
                    attributes: bodyAttributes()
                )
            )
        }

        pendingBlankLine = false

        if let heading = parseSummaryMarkdownHeading(from: trimmedLine) {
            appendInlineMarkdown(
                heading.text,
                to: rendered,
                baseAttributes: headingAttributes(level: heading.level)
            )
            continue
        }

        if let listItem = parseSummaryMarkdownListItem(from: trimmedLine) {
            let attributes = listItemAttributes()
            rendered.append(NSAttributedString(string: listItem.marker, attributes: attributes))
            appendInlineMarkdown(listItem.text, to: rendered, baseAttributes: attributes)
            continue
        }

        appendInlineMarkdown(trimmedLine, to: rendered, baseAttributes: bodyAttributes())
    }

    return rendered
}

private struct SummaryMarkdownHeading {
    let level: Int
    let text: String
}

private struct SummaryMarkdownListItem {
    let marker: String
    let text: String
}

private func parseSummaryMarkdownHeading(from line: String) -> SummaryMarkdownHeading? {
    let headingMarks = line.prefix { $0 == "#" }
    let level = headingMarks.count
    guard (1 ... 6).contains(level) else {
        return nil
    }

    let content = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
    guard !content.isEmpty else {
        return nil
    }

    return SummaryMarkdownHeading(level: level, text: content)
}

private func parseSummaryMarkdownListItem(from line: String) -> SummaryMarkdownListItem? {
    if let stripped = line.stripPrefix("- ") ?? line.stripPrefix("* ") ?? line.stripPrefix("+ ") {
        return SummaryMarkdownListItem(marker: "\u{2022} ", text: stripped)
    }

    let digits = line.prefix { $0.isNumber }
    guard !digits.isEmpty else {
        return nil
    }

    let remainder = line.dropFirst(digits.count)
    guard remainder.hasPrefix(". ") else {
        return nil
    }

    let text = remainder.dropFirst(2)
    guard !text.isEmpty else {
        return nil
    }

    return SummaryMarkdownListItem(marker: "\(digits). ", text: String(text))
}

private func appendInlineMarkdown(
    _ text: String,
    to rendered: NSMutableAttributedString,
    baseAttributes: [NSAttributedString.Key: Any]
) {
    let nsText = text as NSString
    let pattern = #"\*\*([^*]+)\*\*|\*([^*]+)\*"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []
    var cursor = 0

    for match in matches {
        let fullRange = match.range

        if fullRange.location > cursor {
            rendered.append(
                NSAttributedString(
                    string: nsText.substring(with: NSRange(location: cursor, length: fullRange.location - cursor)),
                    attributes: baseAttributes
                )
            )
        }

        if let boldRange = Range(match.range(at: 1), in: text) {
            rendered.append(
                NSAttributedString(
                    string: String(text[boldRange]),
                    attributes: boldAttributes(from: baseAttributes)
                )
            )
        } else if let italicRange = Range(match.range(at: 2), in: text) {
            rendered.append(
                NSAttributedString(
                    string: String(text[italicRange]),
                    attributes: italicAttributes(from: baseAttributes)
                )
            )
        }

        cursor = fullRange.location + fullRange.length
    }

    if cursor < nsText.length {
        rendered.append(
            NSAttributedString(
                string: nsText.substring(from: cursor),
                attributes: baseAttributes
            )
        )
    }
}

private func bodyAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 4

    return [
        .font: NSFont.systemFont(ofSize: 14.5),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraphStyle
    ]
}

private func listItemAttributes() -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 4
    paragraphStyle.headIndent = 18
    paragraphStyle.firstLineHeadIndent = 0

    return [
        .font: NSFont.systemFont(ofSize: 14.5),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraphStyle
    ]
}

private func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 4

    let pointSize: CGFloat
    switch level {
    case 1: pointSize = 22
    case 2: pointSize = 19
    case 3: pointSize = 17
    case 4: pointSize = 16
    case 5: pointSize = 15
    default: pointSize = 14.5
    }

    return [
        .font: NSFont.boldSystemFont(ofSize: pointSize),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraphStyle
    ]
}

private func boldAttributes(from baseAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
    var attributes = baseAttributes
    if let font = baseAttributes[.font] as? NSFont {
        attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }
    return attributes
}

private func italicAttributes(from baseAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
    var attributes = baseAttributes
    if let font = baseAttributes[.font] as? NSFont {
        attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
    return attributes
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }

        return String(dropFirst(prefix.count))
    }
}
#endif

// MARK: - Private components

private struct SummaryShimmerBar: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(QMTheme.searchField)
                .overlay(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [QMTheme.sage.opacity(0), QMTheme.sage, QMTheme.sage.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * 0.4)
                        .offset(x: phase * proxy.size.width)
                )
                .clipShape(Capsule())
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1.2
                    }
                }
        }
    }
}

private struct SummarySkeletonLine: View {
    var maxWidth: CGFloat?
    @State private var pulsing = false

    var body: some View {
        Capsule()
            .fill(QMTheme.faint)
            .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
            .frame(height: 13)
            .opacity(pulsing ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
