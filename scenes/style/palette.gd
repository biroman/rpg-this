class_name Palette
extends RefCounted
## The whole game's colour scheme, in one place.
##
## Flat pastel on warm paper, after Mini Motorways: nothing is metallic, nothing
## is glossy, and every surface is a single authored colour that the light only
## brightens or shades. The world is light and the ink is dark, so text and
## crosshairs are near-black rather than white - the reverse of the usual
## first-person convention, and the reason the HUD carries no drop shadows.
##
## Scenes have to inline their colours as literals, so this is not the only copy
## of these numbers. It is the reference one: if a value here and a value in a
## `.tscn` disagree, this file is right.

# --- paper --------------------------------------------------------------

## Ground, cards, panels. The colour the whole game sits on.
const CREAM := Color("f6f1e7")
## The ground's other checker square. Barely a shade off `CREAM` on purpose.
const CREAM_ALT := Color("f1ebde")
## Grid lines, hairline rules, panel borders.
const CREAM_LINE := Color("e3dbc9")

# --- sky and land -------------------------------------------------------

const SKY := Color("a9d9ea")
const SKY_PALE := Color("d9edf5")
const SAGE := Color("c8ddbc")

# --- ink ----------------------------------------------------------------

## Body text, crosshair, dark props.
const INK := Color("23262c")
## Labels, secondary text, the wind dial.
const INK_SOFT := Color("7b818d")

# --- accents ------------------------------------------------------------

const CORAL := Color("f4526e")
const CRIMSON := Color("d6335c")
const NAVY := Color("3b4a6b")
const AMBER := Color("fbbf45")
const ORANGE := Color("f0803c")

## Accents dark enough to read as text on `CREAM`. `AMBER` and `CORAL` are for
## surfaces the light falls on; these are for type.
const AMBER_INK := Color("af7102")
const CORAL_INK := Color("c73a55")
