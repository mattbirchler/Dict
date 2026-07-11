import Foundation
import Testing
@testable import Dict_app

@MainActor
struct AppleSpeechTranscriptionServiceTests {
    @Test func rmsOfSilenceIsZero() {
        let silence = [Float](repeating: 0, count: 512)
        #expect(AppleSpeechTranscriptionService.rms(silence) == 0)
    }

    @Test func rmsOfConstantSignal() {
        let ones = [Float](repeating: 0.5, count: 100)
        // RMS of a constant 0.5 signal is 0.5.
        #expect(abs(AppleSpeechTranscriptionService.rms(ones) - 0.5) < 0.0001)
    }

    @Test func rmsOfEmptyIsZero() {
        #expect(AppleSpeechTranscriptionService.rms([]) == 0)
    }

    @Test func normalizedEnergyIsClampedAndMonotonic() {
        #expect(AppleSpeechTranscriptionService.normalizedEnergy(rms: 0) == 0)
        let mid = AppleSpeechTranscriptionService.normalizedEnergy(rms: 0.1)
        let hi = AppleSpeechTranscriptionService.normalizedEnergy(rms: 0.5)
        #expect(mid > 0)
        #expect(hi >= mid)
        #expect(hi <= 1)
        // Very loud input clamps to 1, never above.
        #expect(AppleSpeechTranscriptionService.normalizedEnergy(rms: 5) == 1)
    }

    @Test func plainTextExtractsCharacters() {
        let attributed = AttributedString("hello world")
        #expect(AppleSpeechTranscriptionService.plainText(attributed) == "hello world")
    }

    @Test func startsNotReadyAndNotRecording() {
        let service = AppleSpeechTranscriptionService()
        #expect(service.isReady == false)
        #expect(service.isRecording == false)
        #expect(service.needsDownload == false)
    }
}
