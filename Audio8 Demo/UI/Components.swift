//  Components.swift
//  Reusable presentation pieces. Every value comes from `Tokens` — see DesignTokens.swift
//  for why nothing here hardcodes a color or size.

import SwiftUI

/// A single headline measurement. `emphasis` colors the value when the number itself
/// carries a verdict (a silent render, a clipped peak).
struct MetricTile: View {
    let value: String
    let label: String
    var unit: String?
    var emphasis: Color = Tokens.Color.label
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Tokens.Font.metricValue)
                    .foregroundStyle(emphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(Tokens.Font.metricLabel)
                        .foregroundStyle(Tokens.Color.secondaryLabel)
                }
            }
            Text(label.uppercased())
                .font(Tokens.Font.metricLabel)
                .foregroundStyle(Tokens.Color.secondaryLabel)
            if let caption {
                Text(caption)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.tertiaryLabel)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Space.m)
        .cardSurface()
    }
}

/// Section wrapper: a titled group with consistent spacing.
struct Section<Content: View>: View {
    let title: String
    var systemImage: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Tokens.Color.secondaryLabel)
                }
                Text(title)
                    .font(Tokens.Font.sectionTitle)
                    .foregroundStyle(Tokens.Color.label)
                Spacer()
                if let trailing { trailing }
            }
            content
        }
    }
}

/// Engine status pill — the app's single source of "what is the engine doing right now".
struct EngineStatusPill: View {
    let state: Audio8Bench.EngineState

    private var tint: Color {
        switch state {
        case .ready: Tokens.Color.ready
        case .failed: Tokens.Color.failure
        case .idle: Tokens.Color.secondaryLabel
        default: Tokens.Color.working
        }
    }

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(state.label)
                .font(Tokens.Font.caption)
                .foregroundStyle(Tokens.Color.secondaryLabel)
                .lineLimit(1)
        }
        .padding(.horizontal, Tokens.Space.s)
        .padding(.vertical, Tokens.Space.xs)
        .background(Tokens.Color.surfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Color.separator, lineWidth: Tokens.Layout.hairline))
    }
}

/// A labeled slider with a live numeric readout, clamped to the reference
/// implementation's validated range.
struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var format: String = "%.2f"
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Tokens.Color.secondaryLabel)
                Spacer()
                Text(String(format: format, value))
                    .font(Tokens.Font.metricInline)
                    .foregroundStyle(Tokens.Color.label)
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
        }
        .help(help ?? "")
    }
}

/// Level meter that states the verdict in words as well as color — a silent render is
/// the failure this app exists to surface, so it should never be a subtle cue.
struct LevelIndicator: View {
    let rmsDBFS: Double
    let peakDBFS: Double
    let level: RunRecord.Level

    private var tint: Color {
        switch level {
        case .silent: Tokens.Color.levelSilent
        case .low: Tokens.Color.levelLow
        case .healthy: Tokens.Color.levelHealthy
        case .clipping: Tokens.Color.levelSilent
        }
    }

    private var verdict: String {
        switch level {
        case .silent: "SILENT"
        case .low: "Low"
        case .healthy: "OK"
        case .clipping: "CLIPPING"
        }
    }

    private func fmt(_ value: Double) -> String {
        value.isFinite ? String(format: "%.1f", value) : "−∞"
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Text(verdict)
                .font(Tokens.Font.metricLabel)
                .foregroundStyle(tint)
            Text("rms \(fmt(rmsDBFS)) · peak \(fmt(peakDBFS)) dBFS")
                .font(Tokens.Font.metricInline)
                .foregroundStyle(Tokens.Color.secondaryLabel)
        }
    }
}

extension Double {
    /// Bytes → MB/GB, chosen by magnitude so tables stay readable.
    static func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
