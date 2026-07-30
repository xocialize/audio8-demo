//  DesignTokens.swift
//  The app's ENTIRE design vocabulary. Every color, size, spacing, radius, and type
//  style used anywhere in the UI resolves through this file.
//
//  SOURCE: Figma `Demo Apps` (LGwpgABHRfxj47V8uCmkwK) — Apple's macOS 26/27 UI kit.
//  Variables read from node 9:937; the grouped-form geometry from node 0:112.
//
//  COLOR POLICY, stated because it is a judgement call and not a shortcut: the kit's label
//  and background values are EXACTLY the macOS system semantics —
//      Labels/Primary   #ffffffd9  ==  NSColor.labelColor           (white @ 85%)
//      Labels/Secondary #ffffff8c  ==  NSColor.secondaryLabelColor  (white @ 55%)
//      Window Background #1e1e1e   ==  NSColor.windowBackgroundColor (dark)
//  The kit only publishes its DARK values. Hardcoding them would pin the app to dark mode and
//  break Increase Contrast, so where a system semantic provably equals the token we use the
//  semantic and record the Figma value beside it. Only genuinely brand-specific values
//  (the accents) are carried as literals.
//
//  Everything structural — radii, control heights, insets, the type ramp — now comes from the
//  kit rather than from estimates, which is where it differed from the first pass.
//
//  RULE: no view may hardcode a color, font size, or spacing value. If a view needs a
//  value that isn't here, add it here first. That constraint is what makes the Figma
//  retrofit a one-file change instead of a hunt.

import SwiftUI

enum Tokens {

    // MARK: - Color
    //
    // System semantic colors adapt to light/dark, increased contrast, and the user's
    // accent choice for free. A Figma retrofit replaces these with `Color(red:green:blue:)`
    // literals (or an asset catalog) under the same names.

    enum Color {
        /// Primary reading text.
        static let label = SwiftUI.Color.primary
        /// Supporting text: captions, units, secondary metrics.
        static let secondaryLabel = SwiftUI.Color.secondary
        /// De-emphasized text: placeholders, disabled affordances.
        static let tertiaryLabel = SwiftUI.Color(nsColor: .tertiaryLabelColor)

        /// Figma `Accents/Blue` #0091ff. Uses the system accent so the user's chosen accent
        /// and accessibility settings still apply — the kit value is the default-blue stand-in.
        static let accent = SwiftUI.Color.accentColor
        /// The kit's literal blue, for surfaces that must match the design exactly.
        static let accentFigma = SwiftUI.Color(red: 0x00 / 255, green: 0x91 / 255, blue: 0xff / 255)
        /// Hairlines and card borders.
        static let separator = SwiftUI.Color(nsColor: .separatorColor)

        /// Panel/card fill that sits on top of a window material.
        static let surface = SwiftUI.Color(nsColor: .controlBackgroundColor)
        /// A subtler fill for nested content (metric tiles inside a card).
        static let surfaceElevated = SwiftUI.Color(nsColor: .windowBackgroundColor)

        // Status — used by the engine-state pill and metric validity marks.
        static let ready = SwiftUI.Color.green
        static let working = SwiftUI.Color.orange
        /// Figma `Accents/Red` #ff4245.
        static let failure = SwiftUI.Color(red: 0xff / 255, green: 0x42 / 255, blue: 0x45 / 255)
        /// Audio level in a healthy range (see `Tokens.Audio.healthyFloorDBFS`).
        static let levelHealthy = SwiftUI.Color.green
        /// Audio level present but low.
        static let levelLow = SwiftUI.Color.yellow
        /// Effectively silent — the failure this app exists to catch.
        static let levelSilent = SwiftUI.Color.red
    }

    // MARK: - Typography
    //
    // Named by ROLE, not by size, so the Figma type ramp maps onto these names.
    // `.monospacedDigit()` on every numeric style is deliberate: metrics update live and
    // proportional digits make the numbers jitter, which reads as instability.

    enum Font {
        /// Not in the kit (its window titles are a separate component); kept for the app's own
        /// screen headers and marked as such rather than pretending it is kit-derived.
        static let screenTitle = SwiftUI.Font.system(size: 22, weight: .semibold)
        /// Figma `Body/Emphasized` — SF Pro Semibold 13 / line height 16.
        static let sectionTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        /// Figma `Headline/Regular` — SF Pro Bold 13 / line height 16.
        static let headline = SwiftUI.Font.system(size: 13, weight: .bold)
        /// Figma `Global/Font Size` 13.
        static let body = SwiftUI.Font.system(size: 13)
        /// Figma `Subheadline/Regular` — SF Pro Regular 11 / line height 14.
        static let caption = SwiftUI.Font.system(size: 11)

        /// A headline metric value (the big number on a tile).
        static let metricValue = SwiftUI.Font.system(size: 24, weight: .medium).monospacedDigit()
        /// The unit/label under a metric value.
        static let metricLabel = SwiftUI.Font.system(size: 10, weight: .medium)
        /// Table cells and inline numbers.
        static let metricInline = SwiftUI.Font.system(size: 12).monospacedDigit()
        /// Transcripts, JSON, and anything where alignment carries meaning.
        static let mono = SwiftUI.Font.system(size: 11, design: .monospaced)
    }

    // MARK: - Spacing (4pt base grid)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        /// Figma `Button/Radius` and `Global/Radius` = 6. Controls, chips, small buttons.
        static let control: CGFloat = 6
        /// Figma Form Group = 12. Grouped containers and cards. (The first pass guessed 10.)
        static let container: CGFloat = 12
        static let large: CGFloat = 14
    }

    // MARK: - Layout

    enum Layout {
        static let sidebarWidth: CGFloat = 260
        static let inspectorWidth: CGFloat = 340
        /// The inspector is resizable in an HSplitView; cap it so dragging cannot swallow
        /// the composer.
        static let inspectorMaxWidth: CGFloat = 460
        static let minWindowWidth: CGFloat = 1080
        static let minWindowHeight: CGFloat = 720
        /// Sized so TWO tiles fit inside `inspectorWidth` minus padding — at 132 they did
        /// not, which is why the grid silently fell back to a wider layout.
        static let metricTileMinWidth: CGFloat = 140
        static let hairline: CGFloat = 1

        // Kit geometry (node 9:937 variables + node 0:112 form group).
        /// Figma `Global/Height` — standard control height.
        static let controlHeight: CGFloat = 24
        /// Figma form row height.
        static let rowHeight: CGFloat = 42
        /// Figma `Fields/Inset - Left|Right`.
        static let fieldInset: CGFloat = 8
        /// Figma `Popup/Inset - Left`.
        static let popupInset: CGFloat = 12
        /// Figma `Button/Padding - Horizontal`.
        static let buttonPaddingHorizontal: CGFloat = 16
        /// Figma form-group horizontal padding.
        static let groupPadding: CGFloat = 10
    }

    // MARK: - Audio thresholds
    //
    // Not styling — these are the app's judgement calls about what "good output" means,
    // and they belong with the vocabulary because the UI colors by them. A silent stem
    // reads −∞ dBFS; that is the class of failure this app is built to make obvious.

    enum Audio {
        /// Below this, treat the render as silent/failed.
        static let silenceFloorDBFS: Double = -60
        /// Above this RMS, the level is in the expected band for speech.
        static let healthyFloorDBFS: Double = -30
        /// Above this peak, clipping is likely.
        static let clippingCeilingDBFS: Double = -0.5
    }

    // MARK: - Symbols
    //
    // Centralized so the icon set is auditable in one place and swappable for exported
    // Figma assets (which must be committed as real asset bytes, never hand-drawn).

    enum Symbol {
        static let generate = "waveform.circle.fill"
        static let play = "play.fill"
        static let stop = "stop.fill"
        static let save = "square.and.arrow.down"
        static let voice = "person.wave.2.fill"
        static let upload = "square.and.arrow.up"
        static let metrics = "chart.bar.xaxis"
        static let history = "clock.arrow.circlepath"
        static let settings = "gearshape"
        static let export = "arrow.up.doc"
        static let clear = "trash"
        static let engine = "cpu"
        static let memory = "memorychip"
        static let benchmark = "stopwatch"
        static let cancel = "xmark.circle.fill"
    }
}

// MARK: - Shared view treatments

extension View {
    /// The standard card — the kit's grouped-container treatment: surface fill, hairline
    /// border, container radius (12).
    func cardSurface() -> some View {
        self
            .background(Tokens.Color.surface,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.container))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.container)
                    .strokeBorder(Tokens.Color.separator, lineWidth: Tokens.Layout.hairline)
            )
    }
}
