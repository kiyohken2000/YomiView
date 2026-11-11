import SwiftUI

@main
struct YomiViewApp: App {
    var body: some Scene {
        WindowGroup {
            ReaderView()
        }
        .defaultSize(width: 900, height: 1100)
    }
}
