import Foundation

@MainActor
enum DemoArtifactStore {
    private static let folderName = "OneKDemo"
    private static let manifestName = "manifest.json"

    static var rootURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(folderName, isDirectory: true)
    }

    static var manifestURL: URL {
        rootURL.appendingPathComponent(manifestName)
    }

    static func prepare() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    static func loadManifest() throws -> DemoManifest {
        try prepare()
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return DemoManifest(turns: [])
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(DemoManifest.self, from: data)
    }

    static func saveManifest(_ manifest: DemoManifest) throws {
        try prepare()
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    static func audioURL(fileName: String) -> URL {
        rootURL.appendingPathComponent(fileName)
    }

    static func saveAudio(_ data: Data, fileName: String) throws -> String {
        try prepare()
        let url = audioURL(fileName: fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    static func deleteAll() throws {
        if FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.removeItem(at: rootURL)
        }
        try prepare()
        try saveManifest(DemoManifest(turns: []))
    }
}
