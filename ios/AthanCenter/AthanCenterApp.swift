import SwiftUI

@main
struct AthanCenterApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if store.configured {
                    ContentView()
                } else {
                    ServerSetupView()
                }
            }
            .environmentObject(store)
            .preferredColorScheme(store.theme.dark ? .dark : .light)
        }
    }
}
