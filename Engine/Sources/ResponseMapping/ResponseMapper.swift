import GestureEngine

/// Response mapper layer: turns GestureEvents into visual and haptic commands using
/// the active ResponseSet. Holds no gesture logic, only the data-driven mapping.
///
/// - began / fired: spawn every effect in the definition.
/// - changed: update the definition's keyed (ambient) effects.
/// - ended / cancelled: release them. One-shot effects run out on their own.
public final class ResponseMapper {
    public var set: ResponseSet
    public var hapticsAvailable: Bool

    public init(set: ResponseSet, hapticsAvailable: Bool) {
        self.set = set
        self.hapticsAvailable = hapticsAvailable
    }

    public func map(_ e: GestureEvent,
                    visual: (EffectCommand) -> Void,
                    haptic: (HapticCommand) -> Void) {
        guard let def = set.response(for: e.gesture) else { return }
        let boost: Float = hapticsAvailable ? 1 : set.visualBoostWhenNoHaptics

        switch e.phase {
        case .began, .fired:
            for (slot, spec) in def.effects.enumerated() where (spec.spawnOn ?? .start) == .start && passes(spec, e) {
                let s = spawn(spec, slot: slot, def: def, event: e, boost: boost)
                visual(.spawn(s))
                if let trail = spec.trail, e.speed >= trail.minSpeed, trail.count > 0 {
                    let length = e.speed * trail.secondsOfTravel
                    for k in 1...trail.count {
                        let f = Float(k) / Float(trail.count)
                        var t = s
                        t.key = 0
                        t.x -= e.directionX * length * f
                        t.y -= e.directionY * length * f
                        t.radius *= 1 - 0.6 * f
                        t.startRadius *= 1 - 0.6 * f
                        t.intensity *= 0.6 * (1 - f) + 0.1
                        visual(.spawn(t))
                    }
                }
            }
            if hapticsAvailable {
                for h in def.haptics where h != .none {
                    haptic(HapticCommand(name: h, phase: .play, intensity: 1, key: key(e, slot: 0, perTouch: true)))
                }
            }

        case .changed:
            for (slot, spec) in def.effects.enumerated() where isKeyed(spec, def) {
                let k = key(e, slot: spec.keySlot ?? slot, perTouch: spec.perTouch ?? true)
                let (x, y) = position(spec, e)
                visual(.update(key: k, x: x, y: y,
                               radius: radius(spec, e), intensity: intensity(spec, e, boost: boost)))
                if !e.touchPoints.isEmpty { visual(.updatePoints(key: k, points: e.touchPoints)) }
            }

        case .ended:
            // The trigger ended: ambient effects fade. Replacing effects (G4 pulse) run on.
            for (slot, spec) in def.effects.enumerated() where persistence(spec, def) == .ambient && (spec.spawnOn ?? .start) == .start {
                visual(.release(key: key(e, slot: spec.keySlot ?? slot, perTouch: spec.perTouch ?? true)))
            }
            for (slot, spec) in def.effects.enumerated() where spec.spawnOn == .end && passes(spec, e) {
                visual(.spawn(spawn(spec, slot: slot, def: def, event: e, boost: boost)))
            }

        case .cancelled:
            // A provisional gesture turned out wrong (R1): fade everything it keyed,
            // so a cancelled rhythm tap does not leave the pulse at a stroke's start.
            for (slot, spec) in def.effects.enumerated() where isKeyed(spec, def) && (spec.spawnOn ?? .start) == .start {
                visual(.release(key: key(e, slot: spec.keySlot ?? slot, perTouch: spec.perTouch ?? true)))
            }
        }
    }

    // MARK: Helpers

    private func passes(_ spec: EffectSpec, _ e: GestureEvent) -> Bool {
        switch spec.condition {
        case .none: return true
        case .magnitudePositive: return e.magnitude > 0
        case .magnitudeNegative: return e.magnitude < 0
        case .fired: return e.phase == .fired
        case .began: return e.phase == .began
        }
    }

    private func position(_ spec: EffectSpec, _ e: GestureEvent) -> (Float, Float) {
        spec.at == .origin ? (e.originX, e.originY) : (e.x, e.y)
    }

    /// The key a spec slot of a gesture uses, for canvas code that must address an
    /// effect directly (G24: clearing the gathered orb on undo).
    public func keyFor(_ gesture: GestureID, slot: Int, touchID: UInt16 = 0, perTouch: Bool = false) -> UInt64 {
        key(GestureEvent(gesture: gesture, phase: .began, timestamp: 0, x: 0, y: 0, touchID: touchID),
            slot: slot, perTouch: perTouch)
    }

    private func persistence(_ spec: EffectSpec, _ def: ResponseDefinition) -> Persistence {
        spec.persistence ?? def.persistence
    }

    private func isKeyed(_ spec: EffectSpec, _ def: ResponseDefinition) -> Bool {
        (persistence(spec, def) == .ambient && (spec.spawnOn ?? .start) == .start) || spec.replaces == true
    }

    /// gesture index | slot | touch. Stable because gesture IDs never change.
    func key(_ e: GestureEvent, slot: Int, perTouch: Bool) -> UInt64 {
        let touch: UInt64 = perTouch ? UInt64(e.touchID) + 1 : 0
        return (UInt64(e.gesture.index + 1) << 32) | (UInt64(slot) << 16) | touch
    }

    private func value(_ source: ScaleSource, _ e: GestureEvent) -> Float {
        switch source {
        case .magnitude: return e.magnitude
        case .speed: return e.speed
        case .tempo: return e.tempo
        case .size: return e.size
        }
    }

    private func radius(_ spec: EffectSpec, _ e: GestureEvent) -> Float {
        spec.radius * (spec.radiusScale.map { $0.factor(for: value($0.source, e)) } ?? 1)
    }

    private func intensity(_ spec: EffectSpec, _ e: GestureEvent, boost: Float) -> Float {
        (spec.intensity ?? 1) * boost * (spec.intensityScale.map { $0.factor(for: value($0.source, e)) } ?? 1)
    }

    private func spawn(_ spec: EffectSpec, slot: Int, def: ResponseDefinition,
                       event e: GestureEvent, boost: Float) -> EffectSpawn {
        let p = persistence(spec, def)
        let keyed = isKeyed(spec, def) || spec.keySlot != nil
        let r = radius(spec, e)
        let scale = spec.radius > 0 ? r / spec.radius : 1
        let (x, y) = position(spec, e)
        return EffectSpawn(
            key: keyed ? key(e, slot: spec.keySlot ?? slot, perTouch: spec.perTouch ?? true) : 0,
            kind: spec.kind,
            x: x, y: y,
            radius: r,
            startRadius: (spec.startRadius ?? 0) * scale,
            duration: (spec.duration ?? p.fadeDuration).map { d in
                d * Double(spec.durationScale.map { $0.factor(for: value($0.source, e)) } ?? 1)
            },
            delay: spec.delay ?? 0,
            thickness: spec.thickness ?? 3,
            intensity: intensity(spec, e, boost: boost),
            count: spec.count ?? 0,
            color: spec.color ?? .glow,
            easing: spec.easing ?? .easeOut,
            persistence: p,
            tempo: e.tempo,
            directionX: e.directionX, directionY: e.directionY,
            speed: e.speed,
            magnitude: e.magnitude,
            size: e.size,
            originX: e.originX, originY: e.originY,
            points: e.touchPoints,
            atEachPoint: spec.at == .eachTouch
        )
    }
}
