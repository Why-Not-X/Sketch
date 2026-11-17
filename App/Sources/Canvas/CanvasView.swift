import UIKit
import ResponseMapping
import GestureEngine

/// Full-screen Metal-backed canvas. Captures raw touches with the four `touches*`
/// overrides (no gesture recognizers: they delay and cancel, which fights R1).
final class CanvasView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    let controller: CanvasController
    private let hud = UILabel()

    init() {
        controller = CanvasController()
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isOpaque = true
        controller.attach(to: metalLayer)
        if Diagnostics.enabled {
            hud.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            hud.textColor = UIColor(white: 1, alpha: 0.55)
            hud.numberOfLines = 0
            hud.isUserInteractionEnabled = false
            addSubview(hud)
            controller.latency.onReport = { [weak self] text in self?.hud.text = text }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            contentScaleFactor = window.screen.scale
            controller.setMaxFPS(window.screen.maximumFramesPerSecond)
            controller.start()
            DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
        } else {
            controller.stop()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = contentScaleFactor
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        controller.resize(to: bounds.size, scale: Float(scale))
        let inset = safeAreaInsets
        // Leaves the top-right corner to the controls.
        hud.frame = CGRect(x: inset.left + 12, y: inset.top + 8, width: bounds.width - inset.left - inset.right - 190, height: 120)
    }

    // R8: opt out of iPadOS three-finger editing gestures (undo/redo swipe, copy/paste
    // pinch) so G22 reaches the canvas. Applies while the canvas is first responder.
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }
    override var canBecomeFirstResponder: Bool { true }

    #if DEBUG
    // Shake to undo, a debug shortcut alongside the Undo button (Simulator: Device → Shake).
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { controller.undo() }
    }
    #endif

    // MARK: Touches. Kept minimal: queue events, start the latency clock, return.

    /// Called on every canvas touch-down (the controls close the theme row).
    var onTouchBegan: (() -> Void)?

    /// Keeps the debug HUD readable on light themes.
    func applyTheme(_ theme: Theme) {
        hud.textColor = theme.backgroundLuminance > 0.5 ? UIColor(white: 0, alpha: 0.5) : UIColor(white: 1, alpha: 0.55)
    }

    // Only touches that began on the canvas itself. Touches on the controls (a subview)
    // that the controls don't consume travel up the responder chain to here; without
    // this filter every button tap also drew a tap ripple on the canvas.
    private func own(_ touches: Set<UITouch>) -> Set<UITouch> {
        touches.allSatisfy({ $0.view === self }) ? touches : touches.filter { $0.view === self }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let mine = own(touches)
        guard !mine.isEmpty else { return }
        controller.wake()
        onTouchBegan?()
        for t in mine { controller.latency.touchDown(at: t.timestamp) }
        controller.input.handle(mine, event: event, phase: .began, in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let mine = own(touches)
        guard !mine.isEmpty else { return }
        controller.input.handle(mine, event: event, phase: .moved, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let mine = own(touches)
        guard !mine.isEmpty else { return }
        controller.input.handle(mine, event: event, phase: .ended, in: self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let mine = own(touches)
        guard !mine.isEmpty else { return }
        controller.input.handle(mine, event: event, phase: .cancelled, in: self)
    }
}
