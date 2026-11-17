import SwiftUI

@main
struct MasjidCenterApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.setupComplete {
                    ContentView()
                } else {
                    SetupView()
                }
            }
            .environmentObject(store)
            .preferredColorScheme(store.theme.dark ? .dark : .light)
            .task { store.requestLocationPermissionOnce() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.requestLocationPermissionOnce() }
            }
        }
    }
}
