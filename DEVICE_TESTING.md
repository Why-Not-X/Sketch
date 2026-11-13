# Device testing checklist

Everything here needs a real iPhone or iPad. The Simulator can't measure latency, frame drops, battery or haptics, and it fakes at most two touches. Record results in STATUS.md, per device.

Devices the spec asks for: a ProMotion iPhone (120 Hz), a 60 Hz iPhone if you have one, and an iPad.

## 0. Set up

1. Plug in the device, unlock it, and select it in Xcode's device menu.
2. **For performance numbers, use a Release build.** Debug code is about 20× slower in the hot paths (measured: a full ink rebuild takes 26 ms in Debug and 1.3 ms in Release).
   - Product → Scheme → Edit Scheme… → Run → Info → Build Configuration → **Release**.
   - Run → Arguments → add `-hud` so the measurement overlay shows in Release.
3. For everything else (gestures, haptics) Debug is fine. It shows the HUD by default.

## 1. Latency (M1)

1. Run with `-hud`. Draw for 30 s: taps, slow strokes, fast strokes.
2. Read the HUD:
   - `down→screen p50 / p95 / max`: touch-down to the frame on screen.
   - `move→screen p50 / p95`: the newest finger sample to the frame on screen.
   - The Hz line shows the frame rate actually reached. A ProMotion iPhone should say about 120.
3. Write down the numbers per device. Spec target: the reaction is on the next frame (about 8.3 ms at 120 Hz, 16.7 ms at 60 Hz, plus display scan-out).
4. Optional, more precise: Xcode → Product → Profile → "Points of Interest". Each touch is a `TouchToPresent` interval and each frame is a `Frame` interval.

## 2. Worst case (M8): particle spam and the cap

Launch the Release build with **`-stress`**, and separately with **`-stress-cap`**, and keep the device still. Each run:

- draws 20 strokes (about 8.5 s)
- then for 20 s alternates triple taps (G3) with five-finger splashes (G23)
- `-stress-cap` also floods particles to hold the 3,000 cap

At the end, the perf log prints `STRESS RESULT …`. Read it in Xcode's debug console, or in Console.app filtered by subsystem `TouchWhiteboard`, category `perf`. Write down:

- `dropped N` out of `frames`: frames presented later than 1.5× the target frame time
- `skipped`: frames skipped because the GPU was still busy
- `cpu p95 / max`: CPU time per frame. The budget is 8.3 ms at 120 Hz.
- `peak particles`, and `lowest spawn scale` (1 means no degradation was needed)

**Pass (spec M8):** no sustained dropped frames at the particle cap. If it fails, send the numbers. The next step would be moving rendering off the main thread or lowering the cap.

## 3. Idle and battery (M8)

1. Release build. Draw something, then leave the device alone.
2. Within 5 s: motes drift and the HUD shows about 30 Hz. After about 35 s the canvas dims.
3. Touch anywhere, including a button: full brightness and full rate come back right away.
4. Battery: Xcode → Debug navigator (⌘7) → **Energy Impact**. Compare idle (expect Low) with active drawing. For a longer check, leave the app idle for 15 minutes and note the battery percentage before and after.

## 4. Haptics (M6), iPhone only

Debug build is fine. Check each one feels right, and note anything too strong, weak or mushy:

| Gesture | Should feel like |
|---|---|
| Tap | light tick |
| Double tap | tick then a soft thud |
| Triple tap | a burst that tails off |
| Long press (hold) | swell building while you hold |
| Release after hold | snap, then settling |
| Drawing | paper-like texture, stronger and sharper when faster, **stops the instant you lift** |
| Flick | snap, then a light tick each time the comet hits an edge |
| Scribble | rough texture |
| Circle | burst |
| Zigzag | crackle |
| Slingshot | swell while stretching, snap on release |
| Rhythm taps | a heartbeat pulse at your tempo for about 8 s |
| Orbit | a pulse once per full circle |

Tune in `Engine/Tools/make_base_response_set.py`, in the `PALETTE` and `HAPTICS` tables. Run it, then rebuild.

**iPad:** run anything and confirm there are no errors. Haptics are skipped and visuals are boosted 1.2×.

## 5. System-gesture conflicts (R8), iPad

For each gesture, does the app get it, or does iPadOS take it?

| Gesture | Try | Possible conflict | Result |
|---|---|---|---|
| G22 three-finger tap | tap with 3 fingers | iPadOS editing menu (the app opts out) | |
| G22 three-finger swipe | quick 3-finger swipe left or right | undo/redo swipe (the app opts out) | |
| G23 palm splash | tap with 4 or 5 fingers | multitasking gestures | |
| G24 gather | pinch 5 fingers together | **five-finger pinch to Home** | |
| G24 spread | spread 5 fingers | five-finger spread | |
| G30 edge | touch near each edge, swipe in from each edge | Home, Control Center, notifications, Slide Over, Stage Manager | |

Settings → Multitasking & Gestures → "Gestures" (four- and five-finger) can be switched off by the user, but an app can't turn it off. Test with it on, which is the default.

## 6. Thresholds worth a real-finger check

These are guesses tuned only on synthetic traces:
- **Rhythm (G4):** a natural rhythm counts, not too eagerly.
- **Circle (G10):** a hand-drawn circle snaps; a rough loop that isn't round doesn't.
- **Spiral (G11):** about 1.5 turns triggers it.
- **Zigzag (G12):** three quick corners turn into lightning; a wavy line doesn't.
- **Flick (G8):** quick short strokes fly; normal fast drawing doesn't.
- **Scribble (G9):** erases when you mean it; doesn't when you shade.
- **Shape fill (G29):** a closed shape fills; a stroke that ends near its start without closing doesn't.
- **Touch a stroke (G27):** tapping on a line plucks it; tapping beside it doesn't.
- **Two fingers (G17–G21):** drag, pinch, rotate and orbit are each told apart reliably.
- **Swipe versus rake:** a three-finger swipe isn't mistaken for a rake, and the reverse.
