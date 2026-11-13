import SwiftUI

@main
struct TouchWhiteboardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        ZStack {
            // The canvas fills the whole screen; safe areas apply to controls only (M7).
            CanvasRepresentable()
                .ignoresSafeArea()
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> CanvasView { CanvasView() }
    func updateUIView(_ uiView: CanvasView, context: Context) {}
}
