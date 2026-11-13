"""Generates Sources/ResponseMapping/Resources/BaseResponseSet.json.

Appendix A (gesture library) is the source of truth for the text columns; the
`effects` blocks are the tunable visual recipes. Edit here and re-run:
    python3 Tools/make_base_response_set.py
"""
import json, os, random

A = [  # id, visual, haptics, persistence, inherits
 ("G1","Ripple ring from the touch point with a bright core dot. Ring expands to about 120 pt, ease-out, about 0.6 s.",["Tick"],"Short","Contact size sets ring size"),
 ("G2","A second, larger ring chases the first, plus a brief flash at the center. Rings reach about 250 pt; the second starts about 80 ms after the first.",["Tick","Thud"],"Short","Location"),
 ("G3","Particle burst (about 24 particles) outward, with a ring. Particles fly out with drag and fade.",["Burst"],"Medium","Location"),
 ("G4","Ring pulses at the last tap point, repeating at the tapped tempo. Keeps pulsing about 8 s, each pulse slightly dimmer; tapping elsewhere moves it.",["Pulse"],"Ambient","Tempo"),
 ("G5","Glow pools under the finger and grows into a soft orb. Orb grows and slowly breathes; faint particles drift inward.",["Swell"],"Ambient","Hold time sets orb size and brightness"),
 ("G6","Orb releases as a shockwave ring. Expands fast then slows; strength scales with hold time (capped around 2 s).",["Snap","Settle"],"Medium","Hold time sets shockwave size"),
 ("G7","Ink line with a soft glow, tapered ends and a brighter sparkle at the stroke head. Line thins as speed rises; the head sparkle trails slightly behind the finger.",["Texture"],"Ink","Speed sets width; direction"),
 ("G8","Stroke detaches and keeps flying as a comet. Carries momentum, slows with drag, bounces softly off screen edges, then fades.",["Snap","Tick"],"Medium","Velocity and direction"),
 ("G9","Ink under the scribble dissolves into particles (works as an eraser). Particles drift upward and fade as the scribble passes over them.",["Texture"],"Instant","Scribble area; speed sets dissolve rate"),
 ("G10","Loop snaps into a clean ring and sends out 3 concentric echo rings; the ring stays as ink. Echoes expand and fade about 150 ms apart.",["Burst"],"Medium","Circle size sets echo distance"),
 ("G11","Inward: nearby ink and particles are pulled into a vortex that ends in a flash. Outward: a swirl bursts away from the center.",["Swell","Settle"],"Medium","Direction and number of turns set intensity"),
 ("G12","Stroke turns into a jagged electric arc with small branching sparks. Arc flickers and crackles for about 1 s.",["Crackle"],"Short","Speed sets spark count"),
 ("G13","Anchor at the first tap with an elastic line to the finger. Line stretches and glows; on release it snaps back and launches particles toward the anchor.",["Swell","Snap"],"Short","Stretch distance sets launch force"),
 ("G14","The glowing orb follows the finger and pulls nearby particles along; nearby ink is tugged. Pulled items lag with spring physics; tugged ink springs back to rest on release.",["Soft rumble"],"Ambient","Drag speed sets pull strength"),
 ("G15","Ink blooms at that point like a blot soaking into paper. Blot grows while you dwell, with soft feathered edges.",["Soft rumble"],"Ink","Dwell time sets blot size"),
 ("G16","Two ripples linked by a glowing filament that pulses once. Filament brightens as the rings expand.",["Tick"],"Short","Distance between fingers sets filament length and ring size"),
 ("G17","A ribbon fills the space between the fingers, with a gradient edge. Ribbon width follows the finger gap and stretches or twists as it changes.",["Texture"],"Ink","Finger gap sets ribbon width"),
 ("G18","Nearby ink and particles are pulled toward the pinch center, with a flash when the pinch finishes. Compression speeds up as the fingers close; the finish is a quick implosion.",["Swell"],"Short","Pinch speed sets pull and flash strength"),
 ("G19","Shockwave expands from the center; nearby ink ripples like water. Ink wobbles outward, then springs back to rest.",["Thud"],"Medium","Spread speed sets shockwave size"),
 ("G20","Swirl field around the midpoint; particles orbit and ink twists slightly. Keeps spinning with momentum after release, then slows to a stop.",["Soft rumble"],"Medium","Angular velocity"),
 ("G21","Held finger glows as a core; the orbiting finger leaves a circular trail that becomes a ring. Particles keep orbiting the core for a few seconds after release.",["Pulse"],"Medium","Radius and orbit speed"),
 ("G22","Tap: three linked ripples form a triangle. Swipe: a wave sweeps across the screen in the swipe direction; it nudges ink slightly and fades at the far edge.",["Burst","Texture"],"Short","Swipe direction and speed"),
 ("G23","Large splash from the center point of the fingers, with a brief full-canvas flash. Big radial burst (more particles than G3) and a subtle screen pulse.",["Thud","Burst"],"Medium","Finger count sets splash size"),
 ("G24","Gather: all ink on screen is sucked into one glowing orb at the center. Spread: the orb explodes outward and the ink is restored.",["Swell","Snap","Settle"],"Ink","Gather speed"),
 ("G25","Ripples hop between the touch points, linked by thin lightning-like lines. Each hop gets brighter as the tempo rises.",["Tick"],"Short","Tempo sets brightness and chain length"),
 ("G26","One ink line per finger, with a faint shimmer between the lines. Lines keep the finger spacing; the shimmer travels with the stroke heads.",["Texture"],"Ink","Finger spacing sets line spacing"),
 ("G27","The stroke rings like a plucked string; a glow travels both ways from the touch point. Wave decays along the stroke; the stroke wobbles, then returns to rest.",["Tick","Settle"],"Short","Tap position sets wave origin; stroke length sets ring time"),
 ("G28","Spark burst at the crossing; the older stroke ripples briefly. Sparks fly off along both stroke directions.",["Tick"],"Instant","Crossing speed sets spark count"),
 ("G29","Glow floods into the enclosed area from the closing point. Flood spreads fast, then settles to a faint pulse; the fill stays.",["Swell","Thud"],"Ink","Area sets flood time; draw speed sets brightness"),
 ("G30","Edge glows like a bumper and a wave pushes in from that edge. Wave travels about a third of the screen; nearby ink ripples.",["Thud"],"Short","Speed; position along the edge"),
 ("G31","A soft halo blooms at the lift point and fades. Bloom size follows speed at lift; fast lifts leave a short trail.",["Tick"],"Short","Speed at lift sets size and trail"),
 ("G32","Canvas breathes: faint drifting motes, ink shimmers softly, everything dims after about 30 s. Very slow motion, with the frame rate throttled to save battery.",["None"],"Ambient","Existing ink and the last touch location"),
]

# Visual recipes (built so far: M2 gestures). Radii in points, times in seconds.
EFFECTS = {
 "G1": [
  {"kind":"ring","radius":120,"startRadius":6,"duration":0.6,"thickness":2.5,"intensity":0.9,"color":"glow","easing":"easeOut",
   "radiusScale":{"source":"magnitude","inMin":6,"inMax":30,"outMin":0.85,"outMax":1.4}},
  {"kind":"dot","radius":7,"duration":0.35,"intensity":1.2,"color":"sparkle"}],
 "G2": [
  {"kind":"ring","radius":250,"startRadius":12,"duration":0.75,"delay":0.08,"thickness":3.5,"intensity":1.0,"color":"glow","easing":"easeOut"},
  {"kind":"flash","radius":70,"duration":0.18,"intensity":0.9,"color":"sparkle","easing":"linear"}],
 "G3": [
  {"kind":"burst","radius":150,"duration":1.6,"count":24,"intensity":1.0,"color":"sparkle"},
  {"kind":"ring","radius":170,"startRadius":10,"duration":0.8,"thickness":3,"intensity":0.9,"color":"glow","easing":"easeOut"}],
 "G4": [
  {"kind":"pulse","radius":90,"startRadius":8,"duration":8,"thickness":3,"intensity":0.9,"color":"glow","easing":"easeOut",
   "persistence":"Long","replaces":True,"perTouch":False}],
 "G5": [
  {"kind":"orb","radius":95,"startRadius":14,"intensity":1.0,"color":"glow",
   "radiusScale":{"source":"magnitude","inMin":0.4,"inMax":2.5,"outMin":0.45,"outMax":1.0},
   "intensityScale":{"source":"magnitude","inMin":0.4,"inMax":2.0,"outMin":0.5,"outMax":1.0}},
  {"kind":"motesInward","radius":95,"count":14,"intensity":0.5,"color":"sparkle"}],
 "G6": [
  {"kind":"shockwave","radius":280,"startRadius":20,"duration":1.1,"thickness":7,"intensity":1.0,"color":"glow","easing":"fastThenSlow",
   "radiusScale":{"source":"magnitude","inMin":0.4,"inMax":2.0,"outMin":0.5,"outMax":1.0},
   "intensityScale":{"source":"magnitude","inMin":0.4,"inMax":2.0,"outMin":0.6,"outMax":1.0}},
  {"kind":"flash","radius":60,"duration":0.2,"intensity":0.8,"color":"sparkle","easing":"linear"}],
 # --- M3: single-finger depth ---
 "G8": [
  {"kind":"comet","radius":9,"duration":2.6,"intensity":1.1,"color":"sparkle","count":90}],
 "G9": [
  {"kind":"dissolve","radius":18,"duration":1.1,"count":3,"intensity":0.8,"color":"ink","persistence":"Ambient"}],
 "G10": [
  {"kind":"ring","radius":150,"startRadius":60,"duration":0.9,"thickness":3,"intensity":0.8,"color":"glow","easing":"easeOut",
   "radiusScale":{"source":"size","inMin":30,"inMax":200,"outMin":0.6,"outMax":1.8}},
  {"kind":"ring","radius":190,"startRadius":60,"duration":0.9,"delay":0.15,"thickness":2.5,"intensity":0.6,"color":"glow","easing":"easeOut",
   "radiusScale":{"source":"size","inMin":30,"inMax":200,"outMin":0.6,"outMax":1.8}},
  {"kind":"ring","radius":230,"startRadius":60,"duration":0.9,"delay":0.30,"thickness":2,"intensity":0.45,"color":"glow","easing":"easeOut",
   "radiusScale":{"source":"size","inMin":30,"inMax":200,"outMin":0.6,"outMax":1.8}}],
 "G11": [
  {"kind":"vortex","radius":160,"duration":1.1,"count":70,"intensity":1.0,"color":"sparkle","condition":"magnitudePositive",
   "radiusScale":{"source":"size","inMin":40,"inMax":200,"outMin":0.7,"outMax":1.4},
   "intensityScale":{"source":"magnitude","inMin":1.5,"inMax":4,"outMin":0.8,"outMax":1.3,"absolute":True}},
  {"kind":"flash","radius":90,"duration":0.35,"delay":1.0,"intensity":1.2,"color":"sparkle","easing":"linear","condition":"magnitudePositive"},
  {"kind":"twist","radius":220,"duration":1.2,"intensity":1.4,"condition":"magnitudePositive",
   "radiusScale":{"source":"size","inMin":40,"inMax":200,"outMin":0.8,"outMax":1.5}},
  {"kind":"pull","radius":220,"duration":1.2,"intensity":0.45,"condition":"magnitudePositive",
   "radiusScale":{"source":"size","inMin":40,"inMax":200,"outMin":0.8,"outMax":1.5}},
  {"kind":"vortex","radius":200,"duration":1.4,"count":70,"intensity":1.0,"color":"glow","condition":"magnitudeNegative",
   "radiusScale":{"source":"size","inMin":40,"inMax":200,"outMin":0.8,"outMax":1.6},
   "intensityScale":{"source":"magnitude","inMin":1.5,"inMax":4,"outMin":0.8,"outMax":1.3,"absolute":True}},
  {"kind":"ring","radius":220,"startRadius":20,"duration":1.0,"thickness":4,"intensity":0.6,"color":"glow","easing":"fastThenSlow","condition":"magnitudeNegative"}],
 "G12": [
  {"kind":"arc","radius":5,"duration":1.0,"thickness":2.2,"intensity":1.2,"color":"sparkle"},
  {"kind":"burst","radius":60,"duration":0.6,"count":14,"intensity":1.0,"color":"sparkle",
   "intensityScale":{"source":"speed","inMin":300,"inMax":2000,"outMin":0.7,"outMax":1.3}}],
 "G13": [
  {"kind":"tether","radius":0,"thickness":2.5,"intensity":0.9,"color":"glow","persistence":"Ambient",
   "intensityScale":{"source":"magnitude","inMin":20,"inMax":300,"outMin":0.6,"outMax":1.3}},
  {"kind":"launch","radius":220,"duration":1.2,"count":22,"intensity":1.0,"color":"sparkle","spawnOn":"end",
   "radiusScale":{"source":"magnitude","inMin":20,"inMax":300,"outMin":0.4,"outMax":1.6}}],
 "G14": [
  {"kind":"orb","radius":60,"startRadius":45,"intensity":0.9,"color":"glow","persistence":"Ambient"},
  {"kind":"trail","radius":10,"count":40,"intensity":0.45,"color":"glow","persistence":"Ambient"},
  {"kind":"pull","radius":130,"intensity":0.28,"persistence":"Ambient"}],
 "G15": [
  {"kind":"blot","radius":26,"persistence":"Ambient",
   "radiusScale":{"source":"magnitude","inMin":0.3,"inMax":2.0,"outMin":0.25,"outMax":1.0}}],
 # --- M4: multi-finger ---
 "G16": [
  {"kind":"ring","radius":110,"startRadius":6,"duration":0.7,"thickness":2.5,"intensity":0.9,"color":"glow","easing":"easeOut","at":"eachTouch",
   "radiusScale":{"source":"size","inMin":30,"inMax":300,"outMin":0.7,"outMax":1.5}},
  {"kind":"filament","radius":0,"duration":0.8,"thickness":2,"intensity":1.0,"color":"sparkle"}],
 "G17": [
  {"kind":"ribbon","radius":0,"intensity":0.3,"persistence":"Ambient"}],
 "G18": [
  {"kind":"pull","radius":240,"intensity":0.35,"persistence":"Ambient",
   "intensityScale":{"source":"magnitude","inMin":1,"inMax":0.3,"outMin":0,"outMax":1}},
  {"kind":"motesInward","radius":160,"count":30,"intensity":0.6,"color":"sparkle","persistence":"Ambient"},
  {"kind":"ring","radius":4,"startRadius":140,"duration":0.3,"thickness":3,"intensity":1.0,"color":"sparkle","easing":"easeOut","spawnOn":"end",
   "intensityScale":{"source":"speed","inMin":50,"inMax":800,"outMin":0.6,"outMax":1.4}},
  {"kind":"flash","radius":70,"duration":0.25,"delay":0.22,"intensity":1.1,"color":"sparkle","easing":"linear","spawnOn":"end",
   "intensityScale":{"source":"speed","inMin":50,"inMax":800,"outMin":0.6,"outMax":1.4}}],
 "G19": [
  {"kind":"shockwave","radius":320,"startRadius":20,"duration":1.1,"thickness":5,"intensity":0.9,"color":"glow","easing":"fastThenSlow",
   "radiusScale":{"source":"speed","inMin":50,"inMax":800,"outMin":0.6,"outMax":1.4}},
  {"kind":"ripple","radius":420,"startRadius":10,"duration":1.4,"intensity":1.0,
   "radiusScale":{"source":"speed","inMin":50,"inMax":800,"outMin":0.6,"outMax":1.4}}],
 "G20": [
  {"kind":"twist","radius":220,"intensity":0.6,"persistence":"Ambient",
   "radiusScale":{"source":"size","inMin":30,"inMax":200,"outMin":0.8,"outMax":1.6},
   "intensityScale":{"source":"magnitude","inMin":0,"inMax":3.2,"outMin":0.05,"outMax":1.0,"absolute":True}},
  {"kind":"orbitSwarm","radius":110,"duration":2.8,"count":36,"intensity":0.8,"color":"sparkle",
   "radiusScale":{"source":"size","inMin":30,"inMax":200,"outMin":0.6,"outMax":1.4}}],
 "G21": [
  {"kind":"orb","radius":34,"startRadius":10,"intensity":0.9,"color":"glow","at":"origin","persistence":"Ambient"},
  {"kind":"trail","radius":9,"count":50,"intensity":0.55,"color":"sparkle","persistence":"Ambient"},
  {"kind":"ring","radius":100,"startRadius":100,"duration":2.5,"thickness":3,"intensity":0.8,"color":"glow","easing":"linear","at":"origin","spawnOn":"end",
   "radiusScale":{"source":"size","inMin":0,"inMax":100,"outMin":0,"outMax":1}},
  {"kind":"orbitSwarm","radius":100,"duration":3.2,"count":30,"intensity":0.8,"color":"sparkle","at":"origin","spawnOn":"end",
   "radiusScale":{"source":"size","inMin":0,"inMax":100,"outMin":0,"outMax":1}}],
 "G22": [
  {"kind":"ring","radius":100,"startRadius":6,"duration":0.7,"thickness":2.5,"intensity":0.9,"color":"glow","easing":"easeOut","at":"eachTouch","condition":"began"},
  {"kind":"filament","radius":0,"duration":0.9,"thickness":2,"intensity":1.0,"color":"sparkle","condition":"began"},
  {"kind":"sweep","radius":0,"duration":0.9,"thickness":6,"intensity":0.9,"color":"glow","condition":"fired"},
  {"kind":"wave","radius":0,"duration":0.9,"intensity":1.0,"condition":"fired"}],
 "G23": [
  {"kind":"flash","radius":1600,"duration":0.35,"intensity":0.22,"color":"glow","easing":"linear"},
  {"kind":"burst","radius":320,"duration":2.2,"count":80,"intensity":1.1,"color":"sparkle",
   "radiusScale":{"source":"magnitude","inMin":4,"inMax":5,"outMin":1.0,"outMax":1.3}},
  {"kind":"shockwave","radius":420,"startRadius":30,"duration":1.2,"thickness":8,"intensity":0.9,"color":"glow","easing":"fastThenSlow",
   "radiusScale":{"source":"magnitude","inMin":4,"inMax":5,"outMin":1.0,"outMax":1.3}},
  {"kind":"ripple","radius":700,"startRadius":20,"duration":1.3,"intensity":0.7}],
 "G24": [
  {"kind":"pull","radius":3000,"intensity":0.97,"persistence":"Ambient","condition":"magnitudePositive",
   "intensityScale":{"source":"magnitude","inMin":0,"inMax":1,"outMin":0,"outMax":1}},
  {"kind":"orb","radius":46,"startRadius":10,"intensity":1.1,"color":"glow","persistence":"Ink","spawnOn":"end",
   "condition":"magnitudePositive","keySlot":9,"perTouch":False},
  {"kind":"shockwave","radius":900,"startRadius":20,"duration":1.4,"thickness":10,"intensity":1.0,"color":"glow","easing":"fastThenSlow",
   "spawnOn":"end","condition":"magnitudeNegative"},
  {"kind":"burst","radius":500,"duration":2.0,"count":120,"intensity":1.1,"color":"sparkle","spawnOn":"end","condition":"magnitudeNegative"},
  {"kind":"flash","radius":160,"duration":0.3,"intensity":1.2,"color":"sparkle","easing":"linear",
   "spawnOn":"end","condition":"magnitudeNegative","keySlot":9,"perTouch":False,"replaces":True}],
 "G25": [
  {"kind":"ring","radius":70,"startRadius":5,"duration":0.5,"thickness":2,"intensity":0.8,"color":"glow","easing":"easeOut",
   "intensityScale":{"source":"tempo","inMin":3,"inMax":12,"outMin":0.7,"outMax":1.5}},
  {"kind":"arc","radius":4,"duration":0.35,"thickness":1.6,"intensity":1.0,"color":"sparkle",
   "intensityScale":{"source":"tempo","inMin":3,"inMax":12,"outMin":0.7,"outMax":1.5}}],
 "G26": [
  {"kind":"shimmer","radius":3,"count":60,"intensity":0.5,"color":"sparkle","persistence":"Ambient","perTouch":False}],
 # --- M5: contextual and idle ---
 "G27": [
  {"kind":"pluck","radius":7,"duration":1.0,"thickness":2.5,"intensity":1.0,"color":"glow",
   "durationScale":{"source":"magnitude","inMin":50,"inMax":800,"outMin":0.6,"outMax":1.8}},
  {"kind":"dot","radius":6,"duration":0.3,"intensity":1.0,"color":"sparkle"}],
 "G28": [
  {"kind":"crossSparks","radius":55,"duration":0.45,"count":16,"intensity":1.0,"color":"sparkle",
   "intensityScale":{"source":"speed","inMin":200,"inMax":2000,"outMin":0.7,"outMax":1.4}},
  {"kind":"ripple","radius":90,"startRadius":2,"duration":0.5,"intensity":0.6}],
 "G29": [
  {"kind":"fill","radius":0,"intensity":0.16},
  {"kind":"halo","radius":160,"startRadius":10,"duration":0.55,"intensity":0.9,"color":"glow","easing":"easeOut",
   "radiusScale":{"source":"size","inMin":50,"inMax":400,"outMin":0.6,"outMax":2.5},
   "intensityScale":{"source":"speed","inMin":100,"inMax":1500,"outMin":0.7,"outMax":1.3}},
  {"kind":"pulse","radius":40,"startRadius":8,"duration":3.0,"thickness":2,"intensity":0.35,"color":"glow","at":"origin","persistence":"Medium"}],
 "G30": [
  {"kind":"bumper","radius":90,"duration":0.6,"thickness":5,"intensity":1.0,"color":"glow"},
  {"kind":"sweep","radius":280,"duration":0.7,"thickness":4,"intensity":0.6,"color":"glow"},
  {"kind":"wave","radius":280,"duration":0.7,"intensity":0.8}],
 "G32": [
  {"kind":"drift","radius":0,"count":5,"intensity":0.35,"color":"sparkle","persistence":"Ambient","perTouch":False}],
 "G31": [
  {"kind":"halo","radius":26,"startRadius":8,"duration":0.7,"intensity":0.55,"color":"glow","easing":"easeOut",
   "radiusScale":{"source":"speed","inMin":0,"inMax":2000,"outMin":0.7,"outMax":1.8},
   "trail":{"count":5,"minSpeed":400,"secondsOfTravel":0.06}}],
}

# --- Haptic palette (Appendix B starting recipes; tune on a real iPhone) ---
def T(t, i, sh): return {"type": "transient", "time": t, "intensity": i, "sharpness": sh}
def C(t, d, i, sh): return {"type": "continuous", "time": t, "duration": d, "intensity": i, "sharpness": sh}
_rng = random.Random(7)
_crackle, _t = [], 0.0
while _t < 0.9:
    _crackle.append(T(round(_t, 3), round(_rng.uniform(0.25, 0.9), 2), round(_rng.uniform(0.6, 1.0), 2)))
    _t += _rng.uniform(0.02, 0.09)
PALETTE = {
 "Tick":        {"events": [T(0, 0.4, 0.7)]},
 "Thud":        {"events": [T(0, 0.9, 0.2)]},
 "Snap":        {"events": [T(0, 1.0, 1.0)]},
 "Soft rumble": {"events": [C(0, 30, 0.25, 0.1)], "held": True},
 "Swell":       {"events": [C(0, 30, 1.0, 0.3)], "held": True,
                 "intensityCurve": [[0, 0.1], [0.6, 0.8]]},
 "Pulse":       {"events": [T(0, 0.7, 0.4), T(0.12, 0.5, 0.3)]},
 "Texture":     {"events": [C(0, 30, 0.5, 0.5)], "held": True},
 "Burst":       {"events": [T(0, 1.0, 0.8), T(0.05, 0.8, 0.7), T(0.12, 0.6, 0.6), T(0.21, 0.45, 0.5),
                            T(0.32, 0.32, 0.45), T(0.45, 0.2, 0.4)]},
 "Crackle":     {"events": _crackle},
 "Settle":      {"events": [C(0, 0.4, 0.6, 0.3)], "intensityCurve": [[0, 1.0], [0.4, 0.0]]},
}

def cue(name, **kw):
    d = {"name": name}; d.update(kw); return d
speed_texture = {"source": "speed", "inMin": 0, "inMax": 2000, "outMin": 0.25, "outMax": 1.0}
speed_sharp = {"source": "speed", "inMin": 0, "inMax": 2000, "outMin": 0.3, "outMax": 0.8}
HAPTICS = {
 "G1":  [cue("Tick")],
 "G2":  [cue("Thud", delay=0.08)],                               # G1 already ticks (R1 layering)
 "G3":  [cue("Burst")],
 "G4":  [cue("Pulse", loopFor=8)],
 "G5":  [cue("Swell", follow={"source": "magnitude", "inMin": 0.4, "inMax": 2.5, "outMin": 0.1, "outMax": 0.8})],
 "G6":  [cue("Snap"), cue("Settle", delay=0.06)],
 "G7":  [cue("Texture", follow=speed_texture, followSharpness=speed_sharp, intensity=0.6)],
 "G8":  [cue("Snap"), cue("Tick", on="bounce", intensity=0.5)],
 "G9":  [cue("Texture", follow=speed_texture, followSharpness={"source": "speed", "inMin": 0, "inMax": 1500, "outMin": 0.8, "outMax": 1.0})],
 "G10": [cue("Burst")],
 "G11": [cue("Swell", condition="magnitudePositive", duration=0.6), cue("Settle", condition="magnitudeNegative")],
 "G12": [cue("Crackle")],
 "G13": [cue("Swell", follow={"source": "magnitude", "inMin": 20, "inMax": 300, "outMin": 0.1, "outMax": 0.8}),
         cue("Snap", on="end")],
 "G14": [cue("Soft rumble", follow={"source": "speed", "inMin": 0, "inMax": 1500, "outMin": 0.4, "outMax": 1.0})],
 "G15": [cue("Soft rumble", follow={"source": "magnitude", "inMin": 0.3, "inMax": 2.0, "outMin": 0.5, "outMax": 1.0})],
 "G16": [cue("Tick"), cue("Tick", delay=0.05)],
 "G17": [cue("Texture", follow=speed_texture, intensity=0.6)],
 "G18": [cue("Swell", follow={"source": "magnitude", "inMin": 1, "inMax": 0.3, "outMin": 0.1, "outMax": 0.8})],
 "G19": [cue("Thud")],
 "G20": [cue("Soft rumble", follow={"source": "tempo", "inMin": 0, "inMax": 6, "outMin": 0.4, "outMax": 1.0, "absolute": True})],
 "G21": [cue("Pulse", everyMagnitude=1)],
 "G22": [cue("Burst", condition="began"), cue("Texture", condition="fired", duration=0.35)],
 "G23": [cue("Thud"), cue("Burst", delay=0.1)],
 "G24": [cue("Swell", condition="magnitudePositive", follow={"source": "magnitude", "inMin": 0, "inMax": 1, "outMin": 0.1, "outMax": 0.8}),
         cue("Snap", on="end", condition="magnitudeNegative"), cue("Settle", on="end", condition="magnitudeNegative", delay=0.06)],
 "G25": [cue("Tick")],
 "G26": [cue("Texture", follow=speed_texture, intensity=0.7)],
 "G27": [cue("Tick"), cue("Settle", delay=0.05, intensity=0.6)],
 "G28": [cue("Tick", intensity=0.7)],
 "G29": [cue("Swell", duration=0.3), cue("Thud", delay=0.3)],
 "G30": [cue("Thud", intensity=0.5)],
 "G31": [cue("Tick", intensity=0.35)],
 "G32": [],
}

out = {
 "name": "Base",
 "theme": {
  "background": [0.043, 0.043, 0.051],
  "ink": [1.0, 0.95, 0.86],
  "glow": [1.0, 0.80, 0.58],
  "sparkle": [1.0, 0.97, 0.90],
  "glowStrength": 0.38, "sparkleSize": 22, "sparkleLag": 0.45},
 "visualBoostWhenNoHaptics": 1.2,
 "responses": {gid: {"visual": v, "haptics": h, "persistence": p, "inherits": i, "effects": EFFECTS.get(gid, []),
                     "hapticCues": HAPTICS[gid]}
               for gid, v, h, p, i in A},
 "hapticPalette": PALETTE,
}
assert len(out["responses"]) == 32
for gid, cues in HAPTICS.items():
    for c in cues: assert c["name"] in PALETTE, (gid, c)
path = os.path.join(os.path.dirname(__file__), "..", "Sources", "ResponseMapping", "Resources", "BaseResponseSet.json")
with open(path, "w") as f:
    json.dump(out, f, indent=1)
    f.write("\n")
print("wrote", os.path.normpath(path))
