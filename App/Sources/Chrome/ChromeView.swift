import SwiftUI
import ResponseMapping

/// A theme as the picker shows it: a small preview of its canvas and ink.
struct ThemeSwatch: Identifiable {
    let id: String
    let name: String
    let background: Color
    let edge: Color
    let inks: [Color]
    let glows: Bool

    init(_ t: Theme) {
        func c(_ v: RGBA) -> Color { Color(red: Double(v.r), green: Double(v.g), blue: Double(v.b)) }
        id = t.id
        name = t.name
        background = c(t.background)
        edge = c(t.backgroundEdge)
        inks = t.palette.map(c)
        glows = t.glowStrength > 0.2
    }
}

/// State the controls show, fed by the canvas.
final class ChromeModel: ObservableObject {
    @Published var canUndo = false
    @Published var isEmpty = true
    @Published var showThemes = false
    /// Fade mode: plain lines dissolve after release.
    @Published var fadeOn = false
    @Published var themeID = Theme.base.id
    /// Icon and capsule colors follow the theme, so they stay visible on light canvases.
    @Published var iconColor = Color(red: 1.0, green: 0.95, blue: 0.86)
    @Published var capsuleColor = Color.white.opacity(0.06)
    var swatches: [ThemeSwatch] = []

    var onUndo: () -> Void = {}
    var onClear: () -> Void = {}
    var onShare: () -> Void = {}
    var onPickTheme: (String) -> Void = { _ in }
    var onToggleFade: () -> Void = {}
    /// The controls changed size (the swatch row opened or closed).
    var onResize: () -> Void = {}

    func apply(_ t: Theme) {
        themeID = t.id
        let light = t.backgroundLuminance > 0.5
        let icon = light ? t.ink : t.sparkle
        iconColor = Color(red: Double(icon.r), green: Double(icon.g), blue: Double(icon.b))
        capsuleColor = light ? Color.black.opacity(0.06) : Color.white.opacity(0.06)
    }
}

/// The controls (spec: App chrome): theme, Undo, Clear and Save/Share, small, in one
/// corner. The hosting view is sized to these controls only, so they never take touches
/// meant for the canvas.
struct ChromeView: View {
    @ObservedObject var model: ChromeModel

    // Fixed metrics, so the hosting frame can be computed exactly (the controls must
    // be exactly as big as they look: anything outside the frame can't be tapped, and
    // anything inside it would block the canvas).
    static let button: CGFloat = 38, buttonGap: CGFloat = 6, capsulePad: CGFloat = 5
    static let swatch: CGFloat = 34, swatchGap: CGFloat = 10, rowPad: CGFloat = 8, rowGap: CGFloat = 8

    static func size(buttons: Int, swatches: Int, open: Bool) -> CGSize {
        let bar = CGSize(width: CGFloat(buttons) * button + CGFloat(buttons - 1) * buttonGap + 2 * capsulePad,
                         height: button + 2 * capsulePad)
        guard open, swatches > 0 else { return CGSize(width: bar.width + 4, height: bar.height + 4) }
        let row = CGSize(width: CGFloat(swatches) * swatch + CGFloat(swatches - 1) * swatchGap + 2 * rowPad,
                         height: swatch + 2 * rowPad)
        // +4 leaves room for the selection ring drawn just outside each swatch.
        return CGSize(width: max(bar.width, row.width) + 4, height: bar.height + rowGap + row.height + 4)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Self.rowGap) {
            HStack(spacing: Self.buttonGap) {
                ChromeButton(symbol: "paintpalette", label: "Theme", color: model.iconColor) {
                    model.showThemes.toggle()
                    model.onResize()
                }
                ChromeButton(symbol: "wind", label: model.fadeOn ? "Fade mode, on" : "Fade mode, off",
                             color: model.iconColor, highlighted: model.fadeOn, action: model.onToggleFade)
                ChromeButton(symbol: "arrow.uturn.backward", label: "Undo", color: model.iconColor, action: model.onUndo)
                    .disabled(!model.canUndo)
                ChromeButton(symbol: "trash", label: "Clear", color: model.iconColor, action: model.onClear)
                    .disabled(model.isEmpty)
                ChromeButton(symbol: "square.and.arrow.up", label: "Save or share", color: model.iconColor,
                             action: model.onShare)
                    .disabled(model.isEmpty)
            }
            .padding(Self.capsulePad)
            .background(Capsule().fill(model.capsuleColor))
            .overlay(Capsule().stroke(model.iconColor.opacity(0.12), lineWidth: 0.5))

            if model.showThemes {
                HStack(spacing: Self.swatchGap) {
                    ForEach(model.swatches) { s in
                        SwatchView(swatch: s, selected: s.id == model.themeID, ring: model.iconColor)
                            .onTapGesture { model.onPickTheme(s.id) }
                            .accessibilityLabel("\(s.name) theme")
                            .accessibilityAddTraits(s.id == model.themeID ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(Self.rowPad)
                .background(Capsule().fill(model.capsuleColor))
                .overlay(Capsule().stroke(model.iconColor.opacity(0.12), lineWidth: 0.5))
                .transition(.opacity)
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

private struct ChromeButton: View {
    let symbol: String
    let label: String
    let color: Color
    /// A toggle that is on (fade mode) gets a soft disc behind its icon.
    var highlighted = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color.opacity(enabled ? (highlighted ? 1 : 0.8) : 0.25))
                .frame(width: ChromeView.button, height: ChromeView.button)
                .background(Circle().fill(color.opacity(highlighted ? 0.18 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A round preview: the theme's canvas with a short squiggle in each of its ink colors.
private struct SwatchView: View {
    let swatch: ThemeSwatch
    let selected: Bool
    let ring: Color

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [swatch.background, swatch.edge], center: .center,
                                         startRadius: 4, endRadius: 22))
            ForEach(Array(swatch.inks.prefix(3).enumerated()), id: \.offset) { k, ink in
                Squiggle(offset: CGFloat(k - (min(3, swatch.inks.count) - 1)) * 5)
                    .stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .shadow(color: swatch.glows ? ink.opacity(0.9) : .clear, radius: 2.5)
            }
        }
        .frame(width: ChromeView.swatch, height: ChromeView.swatch)
        .clipShape(Circle())
        .overlay(Circle().stroke(ring.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 2 : 0.5).padding(-3))
        .contentShape(Circle())
    }
}

private struct Squiggle: Shape {
    let offset: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = r.midY + offset
        p.move(to: CGPoint(x: r.minX + 7, y: y + 3))
        p.addCurve(to: CGPoint(x: r.maxX - 7, y: y - 3),
                   control1: CGPoint(x: r.midX - 4, y: y - 8), control2: CGPoint(x: r.midX + 4, y: y + 8))
        return p
    }
}
