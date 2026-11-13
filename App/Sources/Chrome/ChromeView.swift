import SwiftUI

/// State the controls show, fed by the canvas.
final class ChromeModel: ObservableObject {
    @Published var canUndo = false
    @Published var isEmpty = true

    var onUndo: () -> Void = {}
    var onClear: () -> Void = {}
    var onShare: () -> Void = {}
}

/// V1 controls (spec: App chrome): Undo, Clear and Save/Share, small, in one corner.
/// The hosting view is sized to these buttons only, so they never take touches meant
/// for the canvas.
struct ChromeView: View {
    @ObservedObject var model: ChromeModel

    var body: some View {
        HStack(spacing: 6) {
            ChromeButton(symbol: "arrow.uturn.backward", label: "Undo", action: model.onUndo)
                .disabled(!model.canUndo)
            ChromeButton(symbol: "trash", label: "Clear", action: model.onClear)
                .disabled(model.isEmpty)
            ChromeButton(symbol: "square.and.arrow.up", label: "Save or share", action: model.onShare)
                .disabled(model.isEmpty)
        }
        .padding(5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .fixedSize()
    }
}

private struct ChromeButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                // Warm white, like the ink (D3).
                .foregroundStyle(Color(red: 1.0, green: 0.95, blue: 0.86).opacity(enabled ? 0.8 : 0.25))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
