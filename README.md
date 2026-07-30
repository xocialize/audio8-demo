# Audio8 Demo — a reference & metrics harness for MLXEngine

A macOS app that drives [Audio8-TTS-Preview-0.6b](https://huggingface.co/Audio8/Audio8-TTS-Preview-0.6b)
on Apple Silicon through [MLXEngine](https://github.com/xocialize/mlx-engine-swift), and
**measures every run**. The audio is the by-product; the measurements are the point.

It exists as a worked example of the consumer side of MLXEngine — model store, registration,
preparation, admission, streaming, eviction — with the instrumentation you need to tell whether
a port is actually behaving.

<!-- Add a screenshot here when convenient. -->

## What it does

| Pane | |
|---|---|
| **Synthesize** | Six reference voices + your own clip, the reference sampler's controls, quantified output level |
| **Sweep** | 6 voices × 3 prompt lengths, deterministic decoding — a regression baseline two builds can be compared on |
| **Long-form** | Sentence-chunked synthesis via [TTSOrchestratorKit](https://github.com/xocialize/tts-orchestrator-kit), with a one-shot A/B |
| **History** | Per-run table, aggregates, JSON + CSV export |
| **Engine** | Governor budget/charge/reserve, GPU pool, and a declared-vs-measured footprint check |

## Why the metrics are shaped the way they are

Every number here was added because something was wrong and nobody could see it:

- **Level in dBFS, not "it sounds fine".** A silent render reads −∞. That is the failure class
  this app was built to make impossible to miss.
- **Resident floor and transient reported separately**, floor measured post-load and pre-run.
  Measuring after a run folds the transient into the floor.
- **MLX-accounted *and* process `phys_footprint` side by side.** They disagree by a large factor;
  showing one hides the disagreement.
- **Declared vs measured footprint, with the over-run flagged red.** The engine's governor
  reserves the declared `peakActivationBytes` process-wide, so an under-declaration silently
  mis-sizes admission for every other model. This app caught exactly that, three times.
- **A first run is always an outlier.** Cold RTF was 1.80 against a steady-state 1.11 — measure
  once and you would report the model as slow. The history keeps every run so the warm-up curve
  is visible rather than averaged away.

## Requirements

- macOS 26+ on Apple Silicon
- Xcode 26+
- ~2.6 GB of disk for the model weights (downloaded on first run)

## First run

1. Open `Audio8 Demo.xcodeproj` and set your own signing team (the project ships with none).
2. Build and run.
3. **Settings → choose a models folder.** The app is sandboxed, so it needs an explicit grant;
   pointing several apps at one folder is what stops each of them downloading its own copy.
4. **Download & load** (~2.6 GB, from `mlx-community/Audio8-TTS-Preview-0.6b-bf16`).
5. Synthesize, or run the Sweep for a baseline.

The download is gated behind explicit consent rather than starting on launch.

## Dependencies

All public:

| | |
|---|---|
| [mlx-engine-swift](https://github.com/xocialize/mlx-engine-swift) | the engine |
| [mlx-audio8-tts-swift](https://github.com/xocialize/mlx-audio8-tts-swift) | the model package |
| [tts-orchestrator-kit](https://github.com/xocialize/tts-orchestrator-kit) | long-form chunking |
| [LoggingKit](https://github.com/xocialize/LoggingKit) | logging |

## Design tokens

`Design/DesignTokens.swift` holds the app's entire design vocabulary — no view hardcodes a
colour, size, or spacing value. The values come from Apple's macOS 26/27 UI kit in Figma; the
file records which Figma variable each one maps to, and why colours resolve to system semantics
rather than the kit's dark-only literals.

## Attribution

The six reference voice clips in `Resources/Voices/` are from the
[Audio8-TTS SGLang Space](https://huggingface.co/spaces/Audio8/Audio8-TTS-Preview-0.6b-SGLang)
(Apache-2.0), reused unmodified so that runs are comparable against that reference
implementation. Audio8's name and logo are their trademarks and are not redistributed here.

## License

Apache-2.0. See [LICENSE](LICENSE).
