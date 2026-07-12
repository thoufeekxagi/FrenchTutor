import SwiftUI

let geminiApiKey: String = {
    guard let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
          !key.isEmpty else {
        fatalError("GEMINI_API_KEY missing. Set it in Secrets.xcconfig and link it as the project's base configuration file.")
    }
    return key
}()

/// OpenRouter powers the lesson-brain (Q&A, writing grading, quiz feedback).
/// Unlike Gemini, a missing key is not fatal — labs simply show an "AI feedback unavailable" banner.
let openRouterApiKey: String = {
    (Bundle.main.object(forInfoDictionaryKey: "OPENROUTER_API_KEY") as? String) ?? ""
}()

@main
struct FrenchTutorApp: App {
    init() {
        #if DEBUG
        ContentService.shared.assertAllContentDecodes()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
