#!/usr/bin/env python3
"""Assert the stylesheets agree with glass-tokens.json.

One file owns the glass numbers. Change the token, then the stylesheets,
and this gate proves they still agree. Blur My Shell settings are checked
by the desktop installer against the same tokens.
"""
import json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from check_contrast import alphas_from_stylesheets, menus_from_stylesheets

tokens = json.loads((pathlib.Path(__file__).parent / "glass-tokens.json").read_text())
for name, alpha in sorted(alphas_from_stylesheets().items()):
    assert alpha == tokens["window_alpha"], f"{name} window alpha {alpha} != token {tokens['window_alpha']}"
for name, (plate, _wash) in sorted(menus_from_stylesheets().items()):
    assert plate == tokens["menu_plate_alpha"], f"{name} menu plate {plate} != token {tokens['menu_plate_alpha']}"
print(f"OK: window {tokens['window_alpha']}, menu plate {tokens['menu_plate_alpha']} — stylesheets agree with glass-tokens.json.")
