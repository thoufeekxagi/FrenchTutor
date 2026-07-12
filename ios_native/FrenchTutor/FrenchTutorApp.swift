import SwiftUI

let geminiApiKey: String = {
    guard let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
          !key.isEmpty else {
        fatalError("GEMINI_API_KEY missing. Set it in Secrets.xcconfig and link it as the project's base configuration file.")
    }
    return key
}()

@main
struct FrenchTutorApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
