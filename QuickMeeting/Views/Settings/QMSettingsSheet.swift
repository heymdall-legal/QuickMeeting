//
//  QMSettingsSheet.swift
//  QuickMeeting
//
//  The macOS-style Settings sheet from QuickMeeting.dc.html — calendar
//  token field with a bounded dropdown, and auto-recording with a removable
//  watched-apps list and start/stop steppers. Single window, light only.
//

#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

private enum QMSettingsTab: Hashable {
    case general
    case glossary
}

struct QMSettingsSheet: View {
    @ObservedObject var calendarViewModel: CalendarSettingsViewModel
    @ObservedObject var autoRecordingViewModel: AutoRecordingSettingsViewModel
    @ObservedObject var transcriptionViewModel: TranscriptionSettingsViewModel
    @ObservedObject var meetingSummaryViewModel: MeetingSummarySettingsViewModel
    @ObservedObject var markdownExportViewModel: MarkdownExportSettingsViewModel
    let onClose: () -> Void

    @State private var isCalendarDropdownOpen = false
    @State private var isAppImporterPresented = false
    @State private var isMarkdownDirectoryImporterPresented = false
    @State private var glossaryDraft = ""
    @State private var selectedTab: QMSettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(QMTheme.hairline)

            TabView(selection: $selectedTab) {
                settingsScroll {
                    transcriptionSection
                    Divider().overlay(QMTheme.hairline).padding(.vertical, 22)
                    markdownExportSection
                    Divider().overlay(QMTheme.hairline).padding(.vertical, 22)
                    calendarsSection
                    Divider().overlay(QMTheme.hairline).padding(.vertical, 22)
                    autoRecordingSection
                    Divider().overlay(QMTheme.hairline).padding(.vertical, 22)
                    aiSummarizationSection
                }
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(QMSettingsTab.general)

                settingsScroll {
                    glossarySection
                }
                .tabItem {
                    Label("Glossary", systemImage: "text.book.closed")
                }
                .tag(QMSettingsTab.glossary)
            }
            .padding(.top, 12)
            .onChange(of: selectedTab) { _, tab in
                if tab == .glossary {
                    transcriptionViewModel.loadGlossaryIfNeeded()
                }
            }

            Divider().overlay(QMTheme.hairline)
            footer
        }
        .frame(width: 600, height: 600)
        .background(QMTheme.sheetBackground)
        .task {
            await autoRecordingViewModel.load()
            await calendarViewModel.reload()
        }
        .fileImporter(
            isPresented: $isAppImporterPresented,
            allowedContentTypes: [.application],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { try? await autoRecordingViewModel.addSelectedApp(at: url) }
        }
        .fileImporter(
            isPresented: $isMarkdownDirectoryImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            markdownExportViewModel.selectDirectory(url)
        }
        .alert("Auto Recording App Error", isPresented: autoRecordingErrorIsPresented) {
            Button("OK") { autoRecordingViewModel.clearError() }
        } message: {
            Text(autoRecordingViewModel.errorMessage ?? "Unknown error.")
        }
        .alert("Markdown Export Error", isPresented: markdownExportErrorIsPresented) {
            Button("OK") { markdownExportViewModel.clearError() }
        } message: {
            Text(markdownExportViewModel.errorMessage ?? "Unknown error.")
        }
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(QMTheme.ink)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(QMTheme.tertiary)
                    .frame(width: 30, height: 30)
                    .background(Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(QMTheme.sage, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(QMTheme.muted)
    }

    // MARK: Transcription

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Transcription")

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default language")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                    Text("Auto-detect picks the language per recording.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.tertiary)
                }
                Spacer(minLength: 0)
                languageMenu
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vocabulary assistance")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                    Text("Optional batch-only CTC stage for glossary terms.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.tertiary)
                }
                Spacer(minLength: 0)
                ctcModeMenu
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diarization clustering")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                    Text("Legacy 0.8 and upstream 0.6 are neutral A/B baselines.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.tertiary)
                }
                Spacer(minLength: 0)
                clusteringPresetMenu
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diarization step ratio")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                    Text("Smaller steps increase overlap and compute cost.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.tertiary)
                }
                Spacer(minLength: 0)
                diarizationStepRatioMenu
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Embedding skip strategy")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                    Text("Optionally skip nearly identical masks at 0.95 similarity.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.tertiary)
                }
                Spacer(minLength: 0)
                embeddingSkipStrategyMenu
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LLM transcript correction")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                    Text("Runs after ASR and diarization when correction settings are complete.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.tertiary)
                }
                Spacer(minLength: 0)
                QMToggle(isOn: Binding(
                    get: { transcriptionViewModel.isLLMCorrectionEnabled },
                    set: { transcriptionViewModel.setLLMCorrectionEnabled($0) }
                ))
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(transcriptionViewModel.options) { option in
                Button {
                    transcriptionViewModel.selectLanguage(code: option.code)
                } label: {
                    if transcriptionViewModel.languageCode == option.code {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(transcriptionViewModel.selectedLanguageName)
                    .font(.system(size: 13.5))
                    .foregroundStyle(QMTheme.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(QMTheme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 170)
            .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(QMTheme.fieldBorder, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var ctcModeMenu: some View {
        Menu {
            ForEach(transcriptionViewModel.ctcOptions, id: \.self) { mode in
                Button {
                    transcriptionViewModel.selectCTCMode(mode)
                } label: {
                    if transcriptionViewModel.ctcMode == mode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(transcriptionViewModel.ctcMode.displayName)
                    .font(.system(size: 13.5))
                    .foregroundStyle(QMTheme.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(QMTheme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 170)
            .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(QMTheme.fieldBorder, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var clusteringPresetMenu: some View {
        Menu {
            ForEach(transcriptionViewModel.clusteringPresets, id: \.self) { preset in
                Button {
                    transcriptionViewModel.selectClusteringPreset(preset)
                } label: {
                    if transcriptionViewModel.offlineDiarization.clusteringPreset == preset {
                        Label(preset.displayName, systemImage: "checkmark")
                    } else {
                        Text(preset.displayName)
                    }
                }
            }
        } label: {
            settingsMenuLabel(transcriptionViewModel.selectedClusteringName)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var diarizationStepRatioMenu: some View {
        Menu {
            ForEach(transcriptionViewModel.diarizationStepRatios, id: \.self) { ratio in
                Button {
                    transcriptionViewModel.selectDiarizationStepRatio(ratio)
                } label: {
                    let text = String(format: "%.2f", ratio)
                    if transcriptionViewModel.offlineDiarization.segmentationStepRatio == ratio {
                        Label(text, systemImage: "checkmark")
                    } else {
                        Text(text)
                    }
                }
            }
        } label: {
            settingsMenuLabel(
                String(format: "%.2f", transcriptionViewModel.offlineDiarization.segmentationStepRatio)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var embeddingSkipStrategyMenu: some View {
        Menu {
            ForEach(transcriptionViewModel.embeddingSkipStrategies, id: \.self) { strategy in
                Button {
                    transcriptionViewModel.selectEmbeddingSkipStrategy(strategy)
                } label: {
                    if transcriptionViewModel.offlineDiarization.embeddingSkipStrategy == strategy {
                        Label(strategy.displayName, systemImage: "checkmark")
                    } else {
                        Text(strategy.displayName)
                    }
                }
            }
        } label: {
            settingsMenuLabel(transcriptionViewModel.offlineDiarization.embeddingSkipStrategy.displayName)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func settingsMenuLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(QMTheme.ink)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(QMTheme.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 170)
        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(QMTheme.fieldBorder, lineWidth: 1))
    }

    // MARK: Glossary

    private var glossarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader("Glossary")
                Spacer()
                glossaryCountText
            }

            Text("Terms are used by batch CTC vocabulary assistance and LLM transcript correction.")
                .font(.system(size: 12.5))
                .foregroundStyle(QMTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("Kubernetes, Core ML, Vector DB...", text: $glossaryDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(QMTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(QMTheme.fieldBorder, lineWidth: 1))
                    .onSubmit { addGlossaryDraft() }

                Button {
                    addGlossaryDraft()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(QMTheme.secondary)
                        .frame(width: 32, height: 32)
                        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(QMTheme.recordedDot, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Add term")
            }

            if !transcriptionViewModel.isGlossaryLoaded {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if transcriptionViewModel.glossaryTerms.isEmpty {
                Text("No glossary terms yet.")
                    .font(.system(size: 12.5))
                    .italic()
                    .foregroundStyle(QMTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(transcriptionViewModel.glossaryTerms) { term in
                        glossaryRow(term)
                    }
                }
            }
        }
    }

    private var glossaryCountText: some View {
        Group {
            if transcriptionViewModel.isGlossaryLoaded {
                Text("\(transcriptionViewModel.glossaryTerms.count) terms")
            } else {
                Text("Not loaded")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(QMTheme.muted)
    }

    private func glossaryRow(_ term: TranscriptionGlossaryTerm) -> some View {
        HStack(spacing: 9) {
            QMToggle(isOn: Binding(
                get: { term.isEnabled },
                set: { transcriptionViewModel.setGlossaryTermEnabled(id: term.id, isEnabled: $0) }
            ))
            Text(term.text)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(QMTheme.ink)
                .lineLimit(1)
            if !term.aliases.isEmpty {
                Text(term.aliases.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(QMTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                transcriptionViewModel.removeGlossaryTerm(id: term.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(QMTheme.muted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Remove term")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(QMTheme.cardBorder, lineWidth: 1))
    }

    private func addGlossaryDraft() {
        transcriptionViewModel.addGlossaryTerm(text: glossaryDraft)
        glossaryDraft = ""
    }

    // MARK: Markdown Export

    private var markdownExportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Markdown Export")

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Obsidian folder")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                    Text("QuickMeeting writes transcript and summary Markdown files for every completed meeting.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if markdownExportViewModel.hasDirectory {
                        Button {
                            markdownExportViewModel.clearDirectory()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(QMTheme.muted)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .help("Clear folder")
                    }

                    Button {
                        isMarkdownDirectoryImporterPresented = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "folder")
                                .font(.system(size: 12, weight: .semibold))
                            Text(markdownExportViewModel.hasDirectory ? "Change" : "Choose")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(QMTheme.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(QMTheme.recordedDot, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(markdownExportViewModel.displayPath)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(markdownExportViewModel.hasDirectory ? QMTheme.secondary : QMTheme.faint)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(QMTheme.fieldBorder, lineWidth: 1))
        }
    }

    // MARK: Calendars

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Calendars")
                .padding(.bottom, 4)
            Text("Used to name meetings and suggest attendees.")
                .font(.system(size: 12.5))
                .foregroundStyle(QMTheme.tertiary)
                .padding(.bottom, 10)

            switch calendarViewModel.authorizationState {
            case .authorized:
                calendarTokenField
                if isCalendarDropdownOpen {
                    calendarDropdown.padding(.top, 8)
                }
            case .notDetermined, .denied:
                grantCalendarAccess
            }
        }
    }

    private var calendarTokenField: some View {
        HFlow(spacing: 6, rowSpacing: 6) {
            ForEach(selectedCalendars) { calendar in
                HStack(spacing: 7) {
                    Circle().fill(calendarColor(calendar.id)).frame(width: 9, height: 9)
                    Text(calendar.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(QMTheme.body)
                    Button {
                        calendarViewModel.toggleCalendarSelection(id: calendar.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(QMTheme.muted)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .background(QMTheme.chip, in: Capsule())
                .overlay(Capsule().stroke(QMTheme.fieldBorder, lineWidth: 1))
            }

            if selectedCalendars.isEmpty {
                Text("No calendars selected")
                    .font(.system(size: 13))
                    .foregroundStyle(QMTheme.faint)
                    .padding(.leading, 4)
            }

            Button {
                isCalendarDropdownOpen.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Add calendar").font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(QMTheme.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .overlay(Capsule().strokeBorder(QMTheme.recordedDot, style: StrokeStyle(lineWidth: 1, dash: [3])))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(QMTheme.fieldBorder, lineWidth: 1))
    }

    private var calendarDropdown: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(calendarViewModel.availableCalendars) { calendar in
                    Button {
                        calendarViewModel.toggleCalendarSelection(id: calendar.id)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(calendarColor(calendar.id)).frame(width: 11, height: 11)
                            Text(calendar.title)
                                .font(.system(size: 13.5))
                                .foregroundStyle(QMTheme.ink)
                            Spacer(minLength: 0)
                            if calendarViewModel.selectedCalendarIDs.contains(calendar.id) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(QMTheme.sage)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .frame(maxWidth: 292, maxHeight: 248, alignment: .leading)
        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(QMTheme.popoverBorder, lineWidth: 1))
        .shadow(color: Color(hex: "#28241e").opacity(0.22), radius: 18, y: 10)
    }

    private var grantCalendarAccess: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow calendar access so QuickMeeting can name meetings and suggest attendees.")
                .font(.system(size: 13))
                .foregroundStyle(QMTheme.tertiary)
            Button {
                Task { await calendarViewModel.requestAccess() }
            } label: {
                Text("Grant Calendar Access")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(QMTheme.sage, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Auto-recording

    private var autoRecordingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Auto-recording")
                .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch apps and record automatically")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                    Text("QuickMeeting starts and stops recording based on activity in the apps you choose.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                QMToggle(isOn: $autoRecordingViewModel.isEnabled)
            }
            .padding(.bottom, 16)

            if autoRecordingViewModel.isEnabled {
                watchedAppsBox.padding(.bottom, 18)
                stepperRow(
                    title: "Start after",
                    value: $autoRecordingViewModel.startDelay,
                    range: 5...20, step: 1, unit: "seconds of activity"
                )
                stepperRow(
                    title: "Stop after",
                    value: $autoRecordingViewModel.stopGracePeriod,
                    range: 30...120, step: 5, unit: "seconds of silence"
                )
                .padding(.bottom, 8)
            }
        }
        .onChange(of: autoRecordingViewModel.isEnabled) { _, _ in save() }
        .onChange(of: autoRecordingViewModel.startDelay) { _, _ in save() }
        .onChange(of: autoRecordingViewModel.stopGracePeriod) { _, _ in save() }
    }

    private var watchedAppsBox: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Watched apps")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(QMTheme.secondary)
                Spacer()
                Button {
                    isAppImporterPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("Add app…").font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(QMTheme.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(QMTheme.recordedDot, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if autoRecordingViewModel.selectedApps.isEmpty {
                Text("No apps added yet. Click “Add app…” to choose one.")
                    .font(.system(size: 12.5))
                    .italic()
                    .foregroundStyle(QMTheme.muted)
            } else {
                VStack(spacing: 6) {
                    ForEach(autoRecordingViewModel.selectedApps, id: \.bundleIdentifier) { app in
                        watchedAppRow(app)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(QMTheme.sidebar, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(QMTheme.cardBorder, lineWidth: 1))
    }

    private func watchedAppRow(_ app: AutoRecordingTarget) -> some View {
        HStack(spacing: 11) {
            appIcon(for: app)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayName)
                    .font(.system(size: 13.5))
                    .foregroundStyle(QMTheme.ink)
                Text(app.bundleIdentifier)
                    .font(.system(size: 11))
                    .foregroundStyle(QMTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                Task { await autoRecordingViewModel.removeSelectedApp(bundleIdentifier: app.bundleIdentifier) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(QMTheme.muted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(QMTheme.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func appIcon(for app: AutoRecordingTarget) -> some View {
        #if canImport(AppKit)
        if !app.appPath.isEmpty, FileManager.default.fileExists(atPath: app.appPath) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.appPath))
                .resizable()
                .frame(width: 26, height: 26)
        } else {
            appIconFallback(app)
        }
        #else
        appIconFallback(app)
        #endif
    }

    private func appIconFallback(_ app: AutoRecordingTarget) -> some View {
        Text(String(app.displayName.prefix(1)).uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(QMSpeakerPalette.style(for: app.displayName).color, in: RoundedRectangle(cornerRadius: 7))
    }

    private func stepperRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(QMTheme.ink)
            Spacer()
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    stepperButton("minus") {
                        value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                        save()
                    }
                    Text("\(Int(value.wrappedValue))")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(QMTheme.ink)
                        .frame(width: 44)
                    stepperButton("plus") {
                        value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                        save()
                    }
                }
                .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(QMTheme.fieldBorder, lineWidth: 1))

                Text(unit)
                    .font(.system(size: 13))
                    .foregroundStyle(QMTheme.tertiary)
                    .frame(width: 116, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
    }

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(QMTheme.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: AI Summarization

    private var aiSummarizationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("AI Summarization")
                .padding(.bottom, 4)
            Text("Connect a language-model endpoint to turn transcripts into summaries.")
                .font(.system(size: 12.5))
                .foregroundStyle(QMTheme.tertiary)
                .padding(.bottom, 16)

            summaryTextField(label: "API base URL", placeholder: "https://api.openai.com/v1", hint: "The chat-completions endpoint of your provider.", text: $meetingSummaryViewModel.baseURL)
                .onChange(of: meetingSummaryViewModel.baseURL) { _, _ in meetingSummaryViewModel.save() }
                .padding(.bottom, 18)

            summaryTextField(label: "Model", placeholder: "gpt-4o-mini", hint: "The model identifier to request from your endpoint.", text: $meetingSummaryViewModel.modelName)
                .onChange(of: meetingSummaryViewModel.modelName) { _, _ in meetingSummaryViewModel.save() }
                .padding(.bottom, 18)

            summarySecureField(label: "API token", placeholder: "sk-…", hint: "Stored on this Mac only — never leaves your device except to call your endpoint.", text: $meetingSummaryViewModel.authToken)
                .onChange(of: meetingSummaryViewModel.authToken) { _, _ in meetingSummaryViewModel.save() }
                .padding(.bottom, 18)

            summaryTextField(label: "Auth header", placeholder: "Authorization", hint: "Authorization sends Bearer automatically. Custom headers send the token as entered.", text: $meetingSummaryViewModel.authHeaderName)
                .onChange(of: meetingSummaryViewModel.authHeaderName) { _, _ in meetingSummaryViewModel.save() }
                .padding(.bottom, 18)

            summaryTemplateField
                .padding(.bottom, 8)

            Divider().overlay(QMTheme.hairline).padding(.vertical, 14)

            summaryTextField(label: "Correction model", placeholder: "gpt-4.1-mini", hint: "Used only when LLM transcript correction is enabled.", text: $meetingSummaryViewModel.correctionModelName)
                .onChange(of: meetingSummaryViewModel.correctionModelName) { _, _ in meetingSummaryViewModel.save() }
                .padding(.bottom, 18)

            correctionTemplateField
                .padding(.bottom, 8)
        }
    }

    private func summaryTextField(label: String, placeholder: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(QMTheme.ink)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, design: .monospaced))
                .foregroundStyle(QMTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(QMTheme.fieldBorder, lineWidth: 1))
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(QMTheme.muted)
        }
    }

    private func summarySecureField(label: String, placeholder: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(QMTheme.ink)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, design: .monospaced))
                .foregroundStyle(QMTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(QMTheme.fieldBorder, lineWidth: 1))
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(QMTheme.muted)
        }
    }

    private var summaryTemplateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summarization template")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(QMTheme.ink)
            Text("The prompt sent to the model. Insert these placeholders anywhere and they'll be filled in for each meeting:")
                .font(.system(size: 12.5))
                .foregroundStyle(QMTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                summaryPlaceholderChip("{text}", description: "full transcript")
                summaryPlaceholderChip("{date}", description: "meeting date")
            }
            .padding(.top, 5)
            TextEditor(text: $meetingSummaryViewModel.promptTemplate)
                .onChange(of: meetingSummaryViewModel.promptTemplate) { _, _ in meetingSummaryViewModel.save() }
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(QMTheme.ink)
                .frame(minHeight: 132)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(QMTheme.fieldBorder, lineWidth: 1))
            Text("Tip: ask for a specific structure — action items, decisions, key points — to get consistent summaries.")
                .font(.system(size: 12))
                .foregroundStyle(QMTheme.muted)
        }
    }

    private var correctionTemplateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Correction template")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(QMTheme.ink)
            Text("This prompt is used after ASR. Keep the rules strict so the model only corrects transcript errors.")
                .font(.system(size: 12.5))
                .foregroundStyle(QMTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                summaryPlaceholderChip("{text}", description: "segment JSON")
                summaryPlaceholderChip("{glossary}", description: "enabled terms")
            }
            .padding(.top, 5)
            TextEditor(text: $meetingSummaryViewModel.correctionPromptTemplate)
                .onChange(of: meetingSummaryViewModel.correctionPromptTemplate) { _, _ in meetingSummaryViewModel.save() }
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(QMTheme.ink)
                .frame(minHeight: 132)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(QMTheme.fieldBorder, lineWidth: 1))
        }
    }

    private func summaryPlaceholderChip(_ code: String, description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(code)
                .font(.system(size: 12.5, design: .monospaced).weight(.bold))
                .foregroundStyle(QMTheme.sage)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(QMTheme.tertiary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(QMTheme.chip, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(QMTheme.cardBorder, lineWidth: 1))
    }

    // MARK: Helpers

    private var selectedCalendars: [CalendarDescriptor] {
        calendarViewModel.availableCalendars.filter { calendarViewModel.selectedCalendarIDs.contains($0.id) }
    }

    private func calendarColor(_ id: String) -> Color {
        let palette = ["#6f86b0", "#6f9e84", "#c08562", "#cba35e", "#c08aa0", "#9a7fb0", "#5f9a9a", "#b0726a", "#a8a05e"]
        var hash = 0
        for scalar in id.unicodeScalars { hash = (hash &+ Int(scalar.value)) % 9973 }
        return Color(hex: palette[hash % palette.count])
    }

    private func save() {
        Task { await autoRecordingViewModel.save() }
    }

    private var autoRecordingErrorIsPresented: Binding<Bool> {
        Binding(
            get: { autoRecordingViewModel.errorMessage != nil },
            set: { if !$0 { autoRecordingViewModel.clearError() } }
        )
    }

    private var markdownExportErrorIsPresented: Binding<Bool> {
        Binding(
            get: { markdownExportViewModel.errorMessage != nil },
            set: { if !$0 { markdownExportViewModel.clearError() } }
        )
    }
}

/// The sage pill switch from the design.
struct QMToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? QMTheme.sage : QMTheme.recordedDot)
                    .frame(width: 44, height: 26)
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(.horizontal, 3)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
    }
}
