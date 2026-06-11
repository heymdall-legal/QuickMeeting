import SwiftUI

struct HuggingFaceTokenSettingsContent: View {
    @ObservedObject var viewModel: HuggingFaceTokenSettingsViewModel

    private let tokenURL = URL(string: "https://huggingface.co/settings/tokens")!
    private let pyannoteAgreementURL = URL(string: "https://huggingface.co/pyannote/speaker-diarization-community-1")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("hf_...", text: $viewModel.token)
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
        .onChange(of: viewModel.token) { _, _ in
            Task {
                await viewModel.save()
            }
        }
    }
}
