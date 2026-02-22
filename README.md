<p align="center">
  <img src="Textures/icon_framed.png" alt="SparkPoint" width="188 " height="188" />
</p>

<h1 align="center">SparkPoint</h1>

<p align="center">
  Cast rings, cooldown arcs, and class resources — all around your cursor.
</p>

<p align="center">
  <!-- Replace with real badges after CurseForge/Wago projects are created -->
  <img alt="WoW Version" src="https://img.shields.io/badge/WoW-12.x%20Midnight-blue" />
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green" />
</p>

<!-- TODO: replace with a real GIF or screenshot banner once recorded -->

---

## Features

### Cast Ring

A progress ring that fills around your cursor as you cast. Shows:

- Cast progress with a moving spark
- **Latency arc** — a red indicator showing your network lag baked into the cast bar
- **Interrupt flash** — brief error overlay when a cast is interrupted or fails
- Optional **spell name text** above the ring (font, size, color, offsets all configurable)
- Configurable fill color, background opacity, glow, spark color, and frame overlay opacity
- Reverse fill direction for channeled spells

### Inner Ring Slots

Up to **3 concentric inner rings** inside the cast ring, each assignable to a data provider:

- **GCD** — tracks the global cooldown after instant casts
- More providers planned

### Class Resource

Displays your class-specific resource directly on your cursor in two modes:

| Mode     | Description                             |
| -------- | --------------------------------------- |
| **Pips** | Visual pip icons for each resource unit |
| **Text** | Numeric value                           |

**Pip mode — supported classes:**
Paladin · Death Knight · Rogue · Druid · Arcane Mage · Windwalker Monk · Warlock · Evoker · Enhancement Shaman

**Text mode — additionally:**
Demon Hunter · Shadow Priest · Balance Druid · Elemental Shaman

### Decorative Ring

A stylized rotating ring rendered around the cursor. Supports multiple texture variants, optional class-color tinting, and rotation speed control.

### Spell Icon

Displays the icon of the spell currently being cast, positioned below the ring. Optionally shows a **cast progress swipe** (cooldown-style overlay).

### Visibility Control

Each module can independently follow the global rule or use its own:

- Always
- In Combat
- Out of Combat
- Has Target
- While Casting

---

## Installation

### Via Addon Manager

SparkPoint will be available on CurseForge and Wago.io. Install via CurseForge App, Wago App, or any compatible addon manager.

### Manual

1. Download the latest `.zip` from the [GitHub Releases](../../releases) page.
2. Extract to `World of Warcraft/_retail_/Interface/AddOns/`.
3. The result should be `Interface/AddOns/SparkPoint/SparkPoint.toc`.
4. Launch WoW and enable the addon in the character select screen.

---

## Configuration

### Slash Commands

| Command                | Action                                      |
| ---------------------- | ------------------------------------------- |
| `/sp` or `/sparkpoint` | Open the Settings Panel                     |
| `/sp unlock`           | Unlock position for manual drag placement   |
| `/sp lock`             | Lock position (or right-click the anchor)   |
| `/sp reset`            | Reset position to default (cursor-attached) |

### Settings Panel

Open via `/sp`. All settings are in the standard Blizzard Settings Panel under **Spark Point**:

- **General** — cursor attachment, anchor offsets, global visibility mode
- **Cast Ring** — radius, colors, opacity, spark, latency, spell text
- **Inner Ring Slots** — assign providers and colors to each of the 3 inner slots
- **Class Resource** — mode (pips/text), font, offsets, scale, opacity, visibility
- **Decorative Ring** — texture, color, size, rotation, visibility
- **Spell Icon** — size, offsets, cast progress swipe

---

## Compatibility

- **WoW version:** 12.x (Midnight)
- **No external libraries** required (no Ace3, no LibStub)
- Lightweight — event-driven, no persistent OnUpdate loops

---

## License

[MIT](LICENSE)
