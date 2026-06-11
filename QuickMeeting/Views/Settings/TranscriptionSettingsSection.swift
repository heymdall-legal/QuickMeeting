import Combine
import SwiftUI

struct TranscriptionSettingsContent: View {
    @ObservedObject var tokenViewModel: HuggingFaceTokenSettingsViewModel
    @ObservedObject var settingsViewModel: TranscriptionSettingsViewModel

    private let tokenURL = URL(string: "https://huggingface.co/settings/tokens")!
    private let pyannoteAgreementURL = URL(string: "https://huggingface.co/pyannote/speaker-diarization-community-1")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SecureField("hf_...", text: $tokenViewModel.token)
                    .textFieldStyle(.roundedBorder)

                Text("Create a Hugging Face access token in your account settings, then accept the pyannote speaker diarization model agreement before running transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Link("Open token settings", destination: tokenURL)
                    Link("Open pyannote agreement", destination: pyannoteAgreementURL)
                }
                .font(.caption)
            }

            Divider()

            Picker("Language", selection: $settingsViewModel.language) {
                ForEach(TranscriptionLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Initial Prompt")
                TextField(
                    "Known names, products, or domain terms",
                    text: $settingsViewModel.initialPrompt,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

                Text("Use this to give the transcription process a starter list of known names, product names, or specialized terms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: tokenViewModel.token) { _, _ in
            Task {
                await tokenViewModel.save()
            }
        }
        .onChange(of: settingsViewModel.language) { _, _ in
            Task {
                await settingsViewModel.save()
            }
        }
        .onChange(of: settingsViewModel.initialPrompt) { _, _ in
            Task {
                await settingsViewModel.save()
            }
        }
    }
}
