import SwiftUI
import UIKit

/// UIKit app lifecycle. The canvas needs a real view controller as the window's root,
/// because only the root controller decides which screen-edge system gestures are
/// deferred (R8, G30) and whether the home indicator hides. The SwiftUI controls sit
/// on top as a child controller.
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
    private var canvas: CanvasView { view as! CanvasView }
    private let chromeModel = ChromeModel()
    private lazy var chrome = UIHostingController(rootView: ChromeView(model: chromeModel))

    override func loadView() { view = CanvasView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let controller = canvas.controller
        // Every control tap also ends idle (R4: any touch interrupts it).
        chromeModel.onUndo = { controller.noteControlTouch(); controller.undo() }
        chromeModel.onClear = { controller.noteControlTouch(); controller.clear() }
        chromeModel.onShare = { [weak self] in controller.noteControlTouch(); self?.share() }
        controller.onInkStateChange = { [weak chromeModel] canUndo, isEmpty in
            chromeModel?.canUndo = canUndo
            chromeModel?.isEmpty = isEmpty
        }

        // v2 themes: the picker lists every theme; picking one cross-fades the canvas.
        chromeModel.swatches = controller.themes.map(ThemeSwatch.init)
        chromeModel.apply(controller.theme)
        canvas.applyTheme(controller.theme)
        chromeModel.onPickTheme = { id in controller.noteControlTouch(); controller.setTheme(id: id) }
        controller.onThemeChange = { [weak self] theme in
            self?.chromeModel.apply(theme)
            self?.canvas.applyTheme(theme)
        }
        chromeModel.onResize = { [weak self] in
            controller.noteControlTouch()
            self?.view.setNeedsLayout()
        }
        // Touching the canvas closes the theme row.
        canvas.onTouchBegan = { [weak self] in
            guard let self, self.chromeModel.showThemes else { return }
            self.chromeModel.showThemes = false
            self.view.setNeedsLayout()
        }

        addChild(chrome)
        chrome.view.backgroundColor = .clear
        chrome.safeAreaRegions = []   // the frame is already placed inside the safe area
        view.addSubview(chrome.view)
        chrome.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Top-right corner, inside the safe area. The hosting view is only as big as the
        // buttons, so it can't take touches meant for the canvas.
        let size = ChromeView.size(buttons: 4, swatches: chromeModel.swatches.count, open: chromeModel.showThemes)
        let inset = view.safeAreaInsets
        chrome.view.frame = CGRect(x: view.bounds.width - inset.right - size.width - 12,
                                   y: inset.top + 8, width: size.width, height: size.height)
    }

    /// Save/Share: a PNG of the ink on the base background, through the share sheet.
    private func share() {
        guard let image = canvas.controller.exportImage() else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Touch Whiteboard \(stamp).png")
        guard let data = UIImage(cgImage: image).pngData(), (try? data.write(to: url)) != nil else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad shows the sheet as a popover from the Share button.
        sheet.popoverPresentationController?.sourceView = chrome.view
        sheet.popoverPresentationController?.sourceRect = chrome.view.bounds
        present(sheet, animated: true)
    }

    // R8: system edge gestures (home, Control Center, notification shade) need a
    // second swipe while the canvas is up, so a first edge touch reaches G30.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
}
