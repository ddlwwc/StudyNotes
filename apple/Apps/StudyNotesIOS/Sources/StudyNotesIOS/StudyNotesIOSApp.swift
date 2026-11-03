#if os(iOS)
import SwiftUI

@main
struct StudyNotesIOSApp: App {
    @State private var model = IOSAppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task {
                    await model.start()
                }
        }
    }
}
#else
import Foundation

@main
struct StudyNotesIOSHost {
    static func main() {
        print("StudyNotes iOS UI builds with the iOS SDK.")
    }
}
#endif
