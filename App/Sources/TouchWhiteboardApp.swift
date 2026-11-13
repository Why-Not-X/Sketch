import UIKit

/// UIKit app lifecycle. The canvas needs a real view controller as the window's root,
/// because only the root controller decides which screen-edge system gestures are
/// deferred (R8, G30) and whether the home indicator hides. SwiftUI chrome (M7) is
/// added as a child controller on top.
/// The scene and its delegate are declared in Info.plist (UIApplicationSceneManifest).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = CanvasViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class CanvasViewController: UIViewController {
    override func loadView() { view = CanvasView() }

    // R8: system edge gestures (home, Control Center, notification shade) need a
    // second swipe while the canvas is up, so a first edge touch reaches G30.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
}
