import UIKit
import GestureEngine

/// Full-screen Metal-backed canvas. Captures raw touches with the four `touches*`
/// overrides (no gesture recognizers: they delay and cancel, which fights R1).
final class CanvasView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    let controller: CanvasController
    #if DEBUG
    private let hud = UILabel()
    #endif

    init() {
        controller = CanvasController()
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isOpaque = true
        controller.attach(to: metalLayer)
        #if DEBUG
        hud.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hud.textColor = UIColor(white: 1, alpha: 0.55)
        hud.numberOfLines = 0
        hud.isUserInteractionEnabled = false
        addSubview(hud)
        controller.latency.onReport = { [weak self] text in self?.hud.text = text }
        #endif
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            contentScaleFactor = window.screen.scale
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
        #if DEBUG
        let inset = safeAreaInsets
        // Leaves the top-right corner to the controls.
        hud.frame = CGRect(x: inset.left + 12, y: inset.top + 8, width: bounds.width - inset.left - inset.right - 190, height: 120)
        #endif
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller.wake()
        for t in touches { controller.latency.touchDown(at: t.timestamp) }
        controller.input.handle(touches, event: event, phase: .began, in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller.input.handle(touches, event: event, phase: .moved, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller.input.handle(touches, event: event, phase: .ended, in: self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller.input.handle(touches, event: event, phase: .cancelled, in: self)
    }
}
