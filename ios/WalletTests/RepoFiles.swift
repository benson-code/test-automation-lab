import Foundation

/// Files of the repository the parity tests read: SPEC.md and the web's tokens.css. The project copies
/// them into the test bundle on every build (the group "Shared files"), so the tests read the current
/// files without reaching outside the simulator: read from the Mac's ~/Documents, the test hung.
enum RepoFiles {
    private final class Token {}

    static func text(_ name: String) throws -> String {
        let bundle = Bundle(for: Token.self)
        guard let url = bundle.url(forResource: name, withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
