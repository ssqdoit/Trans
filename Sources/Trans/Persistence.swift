import Foundation

final class PersistenceStore {
    static let shared = PersistenceStore()
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let directory: URL

    init(directory: URL? = nil) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let target = directory ?? base.appendingPathComponent("Trans", isDirectory: true)
        self.directory = target
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func load<T: Decodable>(_ type: T.Type, from name: String, fallback: T) -> T {
        guard let data = try? Data(contentsOf: url(name)),
              let value = try? decoder.decode(type, from: data) else { return fallback }
        return value
    }

    func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    func exportHistory(_ history: [HistoryItem], to destination: URL) throws {
        let data = try encoder.encode(history)
        try data.write(to: destination, options: .atomic)
    }
}
