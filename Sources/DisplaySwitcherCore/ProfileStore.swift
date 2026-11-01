import Foundation

/// JSON profile store at ~/.config/de-monitor/profiles.json.
/// Missing file -> built-in defaults (plan: graceful fallback + manual mode).
public enum ProfileStore {
    public struct Stored: Codable, Sendable {
        public var layouts: PortLayouts
        public init(layouts: PortLayouts = .defaults()) {
            self.layouts = layouts
        }
    }

    public static var configURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/de-monitor", isDirectory: true)
        return base.appendingPathComponent("profiles.json")
    }

    public static func load() -> Stored {
        let url = configURL
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return Stored()
        }
        return stored
    }

    public static func save(_ stored: Stored) throws {
        let url = configURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(stored)
        try data.write(to: url, options: .atomic)
    }
}
