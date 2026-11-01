import Foundation

public enum ProfileStore {
    public static var configURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/de-monitor", isDirectory: true)
        return base.appendingPathComponent("profiles.json")
    }

    public static func load() -> [String: DisplayProfile] {
        guard let data = try? Data(contentsOf: configURL),
              let setups = try? JSONDecoder().decode([String: DisplayProfile].self, from: data) else {
            return [:]
        }
        return setups
    }

    public static func save(_ setups: [String: DisplayProfile]) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(setups)
        try data.write(to: configURL, options: .atomic)
    }
}
