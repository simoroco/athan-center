import SwiftUI
import UIKit

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
            .onAppear { StatusBarPin.install() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.requestLocationPermissionOnce() }
            }
        }
    }
}

// MARK: - Status bar
// The door photo is dark in BOTH themes, so the system status bar (clock,
// carrier, battery) must always be light — with the light colorScheme iOS
// would draw it in black, invisible over the photo. UIHostingController takes
// the style from the root color scheme and exposes no override, so the root
// view controller is wrapped once in a container that pins .lightContent.

private final class StatusBarContainer: UIViewController {
    private let hosted: UIViewController

    init(hosting hosted: UIViewController) {
        self.hosted = hosted
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hosted)
        hosted.view.frame = view.bounds
        hosted.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosted.view)
        hosted.didMove(toParent: self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}

private enum StatusBarPin {
    /// Wraps every window's root VC in the light-status-bar container. Idempotent.
    static func install() {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                guard let root = window.rootViewController,
                      !(root is StatusBarContainer) else { continue }
                window.rootViewController = StatusBarContainer(hosting: root)
            }
        }
    }
}
