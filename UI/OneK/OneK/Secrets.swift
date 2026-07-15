import Foundation

enum Secrets {
    /// Preferred: set `OPENAI_API_KEY` in your Xcode scheme (Run → Arguments → Environment Variables).
    /// Fallback: paste a key into `localDebugKey` for local runs only — do not commit real keys.
    private static let localDebugKey = ""

    static var openAIAPIKey: String {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty {
            return env
        }
        return localDebugKey
    }
}
