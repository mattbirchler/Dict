# SpeechAnalyzer / SpeechTranscriber — macOS 26 (Tahoe) API Reference

Verified against Apple's documentation JSON + WWDC25 session 277 + full-code
community ports on 2026-07-11. Supporting reference for
`AppleSpeechTranscriptionService`.

Framework: `import Speech` (+ `AVFoundation`). All APIs macOS 26.0+.

## Pipeline
`AVAudioEngine` mic tap → `AVAudioPCMBuffer` → `AVAudioConverter` (to analyzer
format) → `AnalyzerInput(buffer:)` → yielded into `AsyncStream<AnalyzerInput>`
→ `SpeechAnalyzer.start(inputSequence:)` → read `transcriber.results`
(`AsyncSequence`) → `SpeechTranscriber.Result` (`.text: AttributedString`,
`.isFinal: Bool`).

## Construction
```swift
let transcriber = SpeechTranscriber(
    locale: Locale(identifier: "en-US"),
    transcriptionOptions: [],            // Set, not array
    reportingOptions: [.volatileResults],// partial + finalized; omit → finalized only
    attributeOptions: []                 // [.audioTimeRange], [.transcriptionConfidence]
)
let analyzer = SpeechAnalyzer(modules: [transcriber])   // final actor; options: optional
```

## Asset install (`AssetInventory`)
```swift
// supportedLocales = downloadable+installed; installedLocales = on device.
guard await SpeechTranscriber.supportedLocales.contains(where: {
    $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else { throw ... }
if await SpeechTranscriber.installedLocales.contains(where: {
    $0.identifier(.bcp47) == locale.identifier(.bcp47) }) { return }   // already present
if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
    // request.progress is Progress (NSProgressReporting) — observe fractionCompleted
    try await request.downloadAndInstall()
}   // nil => nothing to install
```
`AssetInventory.reserve(locale:)` pins an installed model against reclamation
(cap: `maximumReservedLocales`); `release(reservedLocale:)` frees it.

## Feeding audio
```swift
let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

let engine = AVAudioEngine()
let tapFormat = engine.inputNode.outputFormat(forBus: 0)
let converter = AVAudioConverter(from: tapFormat, to: analyzerFormat!)
engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, when in
    guard let converted = convert(buffer, using: converter, to: analyzerFormat!) else { return }
    inputBuilder.yield(AnalyzerInput(buffer: converted))   // yield is sync, Sendable-safe
}
try engine.start()
// stop: engine.inputNode.removeTap(onBus: 0); engine.stop(); inputBuilder.finish()
```
Sample-rate-aware conversion:
```swift
func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter,
             to format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    var supplied = false; var err: NSError?
    converter.convert(to: out, error: &err) { _, status in
        if supplied { status.pointee = .noDataNow; return nil }
        supplied = true; status.pointee = .haveData; return buffer
    }
    return err == nil ? out : nil
}
```

## Reading results
```swift
// transcriber.results: some Sendable & AsyncSequence<SpeechTranscriber.Result, any Error>
// Result: { text: AttributedString; alternatives: [AttributedString]; range: CMTimeRange;
//           isFinal: Bool; resultsFinalizationTime: CMTime }
var finalized = AttributedString()
for try await result in transcriber.results {
    if result.isFinal { finalized += result.text }
    // else volatile/partial: preview = finalized + result.text
}
// plain text: String(result.text.characters)
```

## Lifecycle
```swift
try await analyzer.start(inputSequence: inputSequence)
try await analyzer.finalizeAndFinishThroughEndOfInput()   // flush + end (normal stop)
await analyzer.cancelAndFinishNow()                        // discard mid-stream (cancel)
try await analyzer.prepareToAnalyze(in: analyzerFormat)    // optional preheat
```
Typical stop: `engine.stop()` + `removeTap` → `inputBuilder.finish()` →
`finalizeAndFinishThroughEndOfInput()`; the results loop then completes.

## Authorization / Info.plist
- Fully on-device; no network except first-time asset download.
- Microphone required: `NSMicrophoneUsageDescription` + `com.apple.security.device.audio-input`.
  Both already present in this project.
- Speech-recognition authorization is **uncertain** for the new API — Apple's
  sample drives it without `SFSpeechRecognizer.requestAuthorization`. This
  project already requests it and has `NSSpeechRecognitionUsageDescription`, so
  no change needed either way. If an asset/locale call throws an auth error at
  runtime, the existing PermissionChecker flow already covers it.

## Concurrency
- `SpeechAnalyzer` is a `final actor` (not main-actor). `await` its methods from
  any context. `AnalyzerInput` and `Result` are `Sendable`.
- Tap callback runs on a realtime audio thread: do NOT `await` there. Convert
  synchronously and `inputBuilder.yield(...)`. Keep it allocation-light.
- Timestamp gotcha: prefer `AnalyzerInput(buffer:)` (let the analyzer time it)
  over hand-rolled `bufferStartTime` to avoid `SFSpeechErrorDomain` code 2
  ("timestamp overlaps") from float drift.

## Corrections
- No `AnalyzerInputConverter` type — use `AVAudioConverter` + `AnalyzerInput(buffer:)`.
- Option params are `Set`, not arrays.
- `bestAvailableAudioFormat` is a static async method on `SpeechAnalyzer`, returns optional.
