import Testing
@testable import QuickMeeting

struct SpeakerPaletteTests {
    @Test
    func rotationProvidesAtLeastTwelveDistinctSpeakerStyles() {
        let styles = (65..<79).map { scalarValue in
            QMSpeakerPalette.style(
                for: "Named speaker",
                key: String(UnicodeScalar(scalarValue)!)
            )
        }

        let distinctStyles = styles.reduce(into: [QMSpeakerStyle]()) { result, style in
            if !result.contains(style) {
                result.append(style)
            }
        }

        #expect(distinctStyles.count >= 12)
    }
}
