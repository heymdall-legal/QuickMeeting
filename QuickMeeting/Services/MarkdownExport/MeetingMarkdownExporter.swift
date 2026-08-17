import Foundation

protocol MeetingMarkdownExporting {
    @discardableResult
    func exportTranscript(for meeting: Meeting, transcript: StoredTranscript) throws -> URL

    @discardableResult
    func exportSummary(for meeting: Meeting, summary: String) throws -> URL

    func removeTranscript(for meetingID: UUID) throws
    func removeSummary(for meetingID: UUID) throws
}

enum MeetingMarkdownExporterError: LocalizedError, Equatable {
    case exportDirectoryMissing
    case exportDirectoryAccessUnavailable

    var errorDescription: String? {
        switch self {
        case .exportDirectoryMissing:
            return "Choose a Markdown export folder in Settings before exporting meeting notes."
        case .exportDirectoryAccessUnavailable:
            return "QuickMeeting no longer has access to the Markdown export folder. Choose the folder again in Settings."
        }
    }
}

struct ConfiguredMeetingMarkdownExporter: MeetingMarkdownExporting {
    private let settingsStore: any MeetingMarkdownExportSettingsStoring
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private let startAccessingSecurityScopedResource: (URL) -> Bool
    private let stopAccessingSecurityScopedResource: (URL) -> Void

    init(
        settingsStore: any MeetingMarkdownExportSettingsStoring,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init,
        startAccessingSecurityScopedResource: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccessingSecurityScopedResource: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    ) {
        self.settingsStore = settingsStore
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.startAccessingSecurityScopedResource = startAccessingSecurityScopedResource
        self.stopAccessingSecurityScopedResource = stopAccessingSecurityScopedResource
    }

    @discardableResult
    func exportTranscript(for meeting: Meeting, transcript: StoredTranscript) throws -> URL {
        try withExporter { exporter in
            try exporter.exportTranscript(for: meeting, transcript: transcript)
        }
    }

    @discardableResult
    func exportSummary(for meeting: Meeting, summary: String) throws -> URL {
        try withExporter { exporter in
            try exporter.exportSummary(for: meeting, summary: summary)
        }
    }

    func removeTranscript(for meetingID: UUID) throws {
        try withExporter { exporter in
            try exporter.removeTranscript(for: meetingID)
        }
    }

    func removeSummary(for meetingID: UUID) throws {
        try withExporter { exporter in
            try exporter.removeSummary(for: meetingID)
        }
    }

    private func withExporter<T>(_ body: (MeetingMarkdownExporter) throws -> T) throws -> T {
        guard let directoryURL = try settingsStore.resolvedDirectoryURL() else {
            throw MeetingMarkdownExporterError.exportDirectoryMissing
        }

        guard startAccessingSecurityScopedResource(directoryURL) else {
            throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable
        }
        defer { stopAccessingSecurityScopedResource(directoryURL) }

        let exporter = MeetingMarkdownExporter(
            fileManager: fileManager,
            rootURL: directoryURL,
            dateProvider: dateProvider
        )
        return try body(exporter)
    }
}

struct MeetingMarkdownExporter: MeetingMarkdownExporting {
    private enum ExportKind: String {
        case transcript
        case summary
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let dateProvider: () -> Date

    init(
        fileManager: FileManager = .default,
        rootURL: URL,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL.standardizedFileURL
        self.dateProvider = dateProvider
    }

    @discardableResult
    func exportTranscript(for meeting: Meeting, transcript: StoredTranscript) throws -> URL {
        let markdown = renderDocument(
            meeting: meeting,
            kind: .transcript,
            body: renderTranscriptBody(meeting: meeting, transcript: transcript)
        )
        return try write(markdown, for: meeting, kind: .transcript)
    }

    @discardableResult
    func exportSummary(for meeting: Meeting, summary: String) throws -> URL {
        let markdown = renderDocument(
            meeting: meeting,
            kind: .summary,
            body: [
                "## Summary",
                summary.trimmingCharacters(in: .whitespacesAndNewlines)
            ].joined(separator: "\n\n")
        )
        return try write(markdown, for: meeting, kind: .summary)
    }

    func removeTranscript(for meetingID: UUID) throws {
        try removeExistingExports(for: meetingID, kind: .transcript, keeping: nil)
    }

    func removeSummary(for meetingID: UUID) throws {
        try removeExistingExports(for: meetingID, kind: .summary, keeping: nil)
    }

    private func write(_ markdown: String, for meeting: Meeting, kind: ExportKind) throws -> URL {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let destinationURL = rootURL.appendingPathComponent(fileName(for: meeting, kind: kind))
        try removeExistingExports(for: meeting.id, kind: kind, keeping: destinationURL)
        try markdown.write(to: destinationURL, atomically: true, encoding: .utf8)
        return destinationURL
    }

    private func removeExistingExports(
        for meetingID: UUID,
        kind: ExportKind,
        keeping destinationURL: URL?
    ) throws {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }

        let suffix = ".\(kind.rawValue).md"
        let uuidText = meetingID.uuidString
        let existingURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )

        for url in existingURLs {
            guard
                destinationURL.map({ url.standardizedFileURL != $0.standardizedFileURL }) ?? true,
                url.lastPathComponent.contains(uuidText),
                url.lastPathComponent.hasSuffix(suffix)
            else {
                continue
            }

            try fileManager.removeItem(at: url)
        }
    }

    private func renderDocument(meeting: Meeting, kind: ExportKind, body: String) -> String {
        [
            renderFrontmatter(meeting: meeting, kind: kind),
            "# \(displayTitle(for: meeting))",
            renderMetadataSection(meeting: meeting),
            body
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        + "\n"
    }

    private func renderFrontmatter(meeting: Meeting, kind: ExportKind) -> String {
        var lines = [
            "---",
            "id: \"\(meeting.id.uuidString)\"",
            "type: \(kind.rawValue)",
            "title: \(yamlQuoted(displayTitle(for: meeting)))",
            "started_at: \(iso8601String(for: meeting.startedAt))",
        ]

        if let endedAt = meeting.endedAt {
            lines.append("ended_at: \(iso8601String(for: endedAt))")
        }

        if let duration = meeting.duration {
            lines.append("duration_seconds: \(Int(duration.rounded()))")
        }

        if let status = try? meeting.status {
            lines.append("status: \(status.rawValue)")
        }

        if meeting.attendeeNames.isEmpty {
            lines.append("attendees: []")
        } else {
            lines.append("attendees:")
            lines.append(contentsOf: meeting.attendeeNames.map { "  - \(yamlQuoted($0))" })
        }

        lines.append("source_audio: \(yamlQuoted(meeting.audioFilePath))")
        lines.append("created_at: \(iso8601String(for: meeting.createdAt))")
        lines.append("updated_at: \(iso8601String(for: meeting.updatedAt))")
        lines.append("exported_at: \(iso8601String(for: dateProvider()))")
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private func renderMetadataSection(meeting: Meeting) -> String {
        var lines = [
            "## Metadata",
            "- Date: \(displayDateTime(for: meeting.startedAt))",
        ]

        if let endedAt = meeting.endedAt {
            lines.append("- Ended: \(displayDateTime(for: endedAt))")
        }

        if let duration = meeting.duration {
            lines.append("- Duration: \(transcriptExportDurationText(duration))")
        }

        if !meeting.attendeeNames.isEmpty {
            lines.append("- Attendees: \(meeting.attendeeNames.joined(separator: ", "))")
        }

        lines.append("- Source audio: \(meeting.audioFilePath)")
        return lines.joined(separator: "\n")
    }

    private func renderTranscriptBody(meeting _: Meeting, transcript: StoredTranscript) -> String {
        let speakerNames = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0.id, $0.displayName) })
        let sections = transcript.segments.reduce(into: [(speakerName: String, lines: [String])]()) { result, segment in
            let line = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                return
            }

            let speakerName = segment.speakerID.flatMap { speakerNames[$0] } ?? "Speaker"
            if result.last?.speakerName == speakerName {
                result[result.count - 1].lines.append(line)
            } else {
                result.append((speakerName: speakerName, lines: [line]))
            }
        }

        let renderedSections = sections.map { section in
            "### \(section.speakerName)\n\n" + section.lines.joined(separator: "\n\n")
        }

        return (["## Transcript"] + renderedSections).joined(separator: "\n\n")
    }

    private func fileName(for meeting: Meeting, kind: ExportKind) -> String {
        [
            fileDateString(for: meeting.startedAt),
            sanitizedFileNameComponent(displayTitle(for: meeting)),
            meeting.id.uuidString
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        + ".\(kind.rawValue).md"
    }

    private func displayTitle(for meeting: Meeting) -> String {
        let trimmed = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Meeting" : trimmed
    }

    private func sanitizedFileNameComponent(_ value: String) -> String {
        let invalidScalars = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.controlCharacters)
        let scalars = value.unicodeScalars.map { scalar in
            invalidScalars.contains(scalar) ? " " : String(scalar)
        }
        let collapsed = scalars.joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(120))
    }

    private func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func iso8601String(for date: Date) -> String {
        Self.iso8601Formatter.string(from: date)
    }

    private func fileDateString(for date: Date) -> String {
        Self.fileDateFormatter.string(from: date)
    }

    private func displayDateTime(for date: Date) -> String {
        Self.displayDateFormatter.string(from: date)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
