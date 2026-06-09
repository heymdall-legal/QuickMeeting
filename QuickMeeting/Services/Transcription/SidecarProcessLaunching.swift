import Foundation

struct SidecarLaunchRequest: Sendable, Equatable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
}

enum SidecarLaunchError: Error, Equatable {
    case executableMissing
    case launchFailed(String)
    case terminatedWithoutTerminalEvent
    case sidecarReported(String)
}

protocol SidecarProcessLaunching: Sendable {
    func run(
        _ request: SidecarLaunchRequest,
        onLine: @escaping @Sendable (String) async throws -> Void
    ) async throws
}
