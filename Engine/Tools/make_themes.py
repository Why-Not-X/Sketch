"""Generates the v2 theme files: Sources/ResponseMapping/Resources/theme-<id>.json.

Base is built into the app (Theme.base, the v1 look) and is not a file. Every field
left out of a theme here falls back to Base. Edit and re-run:
    python3 Tools/make_themes.py
"""
import json, os

THEMES = [
 {"id": "neon", "name": "Neon", "order": 1,
  "background": [0.030, 0.012, 0.055], "backgroundEdge": [0.004, 0.0, 0.012], "vignette": 0.7,
  "palette": [[1.0, 0.16, 0.72], [0.12, 0.88, 1.0], [0.62, 1.0, 0.18], [1.0, 0.55, 0.08]],
  "inkMode": "perStroke", "glowFromInk": True, "glowStrength": 0.9, "glowFalloff": 1.5, "coreScale": 0.7,
  "sparkle": [1.0, 0.92, 1.0], "sparkleSize": 26, "effectPalette": True, "sprite": "star", "blend": "add"},
 {"id": "neon-echoes", "name": "Neon Echoes", "order": 2,
  "background": [0.012, 0.016, 0.055], "backgroundEdge": [0.0, 0.0, 0.012], "vignette": 0.75,
  "palette": [[0.12, 0.88, 1.0], [1.0, 0.16, 0.72], [0.55, 0.4, 1.0], [0.62, 1.0, 0.18]],
  "inkMode": "perStroke", "glowFromInk": True, "glowStrength": 0.85, "glowFalloff": 1.6, "coreScale": 0.7,
  "sparkle": [0.9, 1.0, 1.0], "sparkleSize": 24, "effectPalette": True, "sprite": "star", "blend": "add",
  "echo": {"count": 3, "delay": 0.12, "growth": 0.3, "fade": 0.55,
           "strokeCopies": 2, "strokeTravel": 28, "strokeDuration": 1.1}},
 {"id": "chalk", "name": "Chalk", "order": 3,
  "background": [0.12, 0.18, 0.15], "backgroundEdge": [0.05, 0.08, 0.07], "vignette": 0.9,
  "palette": [[0.93, 0.93, 0.87]], "inkMode": "single",
  "glow": [0.85, 0.92, 0.86], "glowStrength": 0.07, "glowFalloff": 3.0, "coreScale": 1.15, "texture": "chalk",
  "sparkle": [0.95, 0.95, 0.9], "sparkleSize": 14, "sprite": "dust", "blend": "add", "particleGravity": 140},
 {"id": "paper", "name": "Paper", "order": 4,
  "background": [0.965, 0.945, 0.895], "backgroundEdge": [0.88, 0.85, 0.78], "vignette": 0.55,
  "palette": [[0.09, 0.11, 0.21]], "inkMode": "single",
  "glow": [0.16, 0.22, 0.42], "glowStrength": 0.0, "glowFalloff": 2.0, "coreScale": 1.1,
  "sparkle": [0.12, 0.14, 0.28], "sparkleSize": 12, "sprite": "graphite", "blend": "over", "particleGravity": 40},
 {"id": "aurora", "name": "Aurora", "order": 5,
  "background": [0.018, 0.03, 0.085], "backgroundEdge": [0.0, 0.004, 0.02], "vignette": 0.7,
  "palette": [[0.32, 1.0, 0.68], [0.18, 0.84, 0.95], [0.58, 0.45, 1.0], [0.95, 0.5, 0.88]],
  "inkMode": "alongStroke", "glowFromInk": True, "glowStrength": 0.6, "glowFalloff": 1.3, "coreScale": 0.9,
  "sparkle": [0.85, 1.0, 0.95], "sparkleSize": 22, "effectPalette": True, "sprite": "soft", "blend": "add"},
]

out_dir = os.path.join(os.path.dirname(__file__), "..", "Sources", "ResponseMapping", "Resources")
ids = set()
for t in THEMES:
    assert t["id"] not in ids and t["id"] != "base"
    ids.add(t["id"])
    assert 1 <= len(t["palette"]) <= 4
    path = os.path.join(out_dir, "theme-%s.json" % t["id"])
    with open(path, "w") as f:
        json.dump(t, f, indent=1)
        f.write("\n")
    print("wrote", os.path.normpath(path))
