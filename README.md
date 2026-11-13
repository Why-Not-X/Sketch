# Touch Whiteboard

A blank canvas where every touch gets an instant reaction. Native Swift, Metal and Core Haptics. Progress is tracked in `STATUS.md`.

## Run it on your iPhone or iPad

1. Plug the device into the Mac with a cable and unlock it.
2. Double-click `TouchWhiteboard.xcodeproj` to open it in Xcode.
3. In the left sidebar, click the blue **TouchWhiteboard** project, then **Signing & Capabilities**. Under **Team**, pick your Apple ID. If it isn't listed, choose "Add an Account…".
4. In the device menu at the top of the window, pick your iPhone or iPad.
5. Press **⌘R**. The first time, the device may ask you to trust the developer: open Settings → General → VPN & Device Management and tap Trust.

The debug HUD at the top left shows the measured frame rate, touch-to-screen latency and the last gestures recognized. In debug builds, shake the device to undo (the Undo button arrives with M7).

## Scripted demos (Simulator)

Add a launch argument under Product → Scheme → Edit Scheme… → Run → Arguments:

- `-demo`: taps, holds, rhythm and a stroke (G1 to G7, G31)
- `-demo3`: scribble, circle, spiral, zigzag, flick, slingshot, hold-drag and dwell (G8 to G15)
- `-demo4`: multi-finger, injected (G16 to G26); the Simulator itself can only fake two touches
- `-demo5`: touch and cross a stroke, close a shape, edge touches, then idle (G27 to G30, G32)

In debug builds every recognized gesture is also logged (subsystem `TouchWhiteboard`, category `gestures`).

## Layout

- `Engine/`: Swift Package (`GestureEngine`, `InkModel`, `ResponseMapping`), pure Swift. Test with `cd Engine && swift test`.
- `App/Sources/`: touch capture (`Input/`), frame loop (`Canvas/`), Metal (`Renderer/`), latency measurement (`Diagnostics/`).
