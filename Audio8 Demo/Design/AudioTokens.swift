//  AudioTokens.swift
//  The app's audio-domain constants, filed as an extension on the shared vocabulary.
//
//  The design vocabulary itself — every color, size, spacing, radius, and type style —
//  now comes from DesignScaffold (AB-D-0042: one design authority for the fleet). This
//  app carried a 202-line local `enum Tokens` that predated the package being published;
//  it has been deleted in favour of the package, and AB-A-0034 verified the package is a
//  strict superset of it apart from what is below.
//
//  These three thresholds are the ONLY thing the fork had that the package lacks — and
//  they were never design vocabulary. They are this app's judgement calls about what
//  "good output" means, and they live here because the UI colors by them: a silent stem
//  reads −∞ dBFS, and that is the class of failure this app exists to make obvious.
//  The colors they select (`Tokens.Color.levelHealthy` / `.levelLow` / `.levelSilent`)
//  ARE vocabulary and come from the package.
//
//  HOUSE RULE, inherited with the tokens: no view hardcodes a color, font size, or
//  spacing value. A value that is missing gets added to `Tokens` in DesignScaffold by a
//  bridge ask — never invented locally.

import DesignScaffold

extension Tokens {

    // MARK: - Audio thresholds

    enum Audio {
        /// Below this, treat the render as silent/failed.
        static let silenceFloorDBFS: Double = -60
        /// Above this RMS, the level is in the expected band for speech.
        static let healthyFloorDBFS: Double = -30
        /// Above this peak, clipping is likely.
        static let clippingCeilingDBFS: Double = -0.5
    }
}
