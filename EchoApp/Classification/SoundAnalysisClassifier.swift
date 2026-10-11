import AVFoundation
import EchoCore
import SoundAnalysis

/// A classifier fed mono audio that reports sound group scores per window (spec §3.2).
/// Lets another model (e.g. a TFLite YAMNet) be swapped in without touching the pipeline.
protocol SoundClassifier: AnyObject {
    var onFrame: ((ClassificationFrame) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    /// Appends the next block of mono samples (continuous with the previous call).
    func analyze(_ mono: [Float])
}

/// Apple's built-in sound classifier over the omni (W) channel.
/// Not thread-safe: call `analyze` from one serial queue; results arrive synchronously on it.
final class SoundAnalysisClassifier: NSObject, SoundClassifier, SNResultsObserving, @unchecked Sendable {
    private let analyzer: SNAudioStreamAnalyzer
    private let format: AVAudioFormat
    private let mapper: LabelMapper
    private let sampleRate: Double
    private var framePosition: AVAudioFramePosition = 0

    var onFrame: ((ClassificationFrame) -> Void)?
    var onError: ((Error) -> Void)?

    init(sampleRate: Double, mapper: LabelMapper) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw ResourceError.malformed("unsupported sample rate \(sampleRate)")
        }
        self.format = format
        self.sampleRate = sampleRate
        self.mapper = mapper
        analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(sampleRate))
        request.overlapFactor = 0.5
        super.init()
        try analyzer.add(request, withObserver: self)
    }

    func analyze(_ mono: [Float]) {
        guard !mono.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mono.count)),
              let dest = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(mono.count)
        mono.withUnsafeBufferPointer { dest.update(from: $0.baseAddress!, count: mono.count) }
        analyzer.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(mono.count)
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        var labels: [String: Double] = [:]
        for c in result.classifications { labels[c.identifier] = c.confidence }
        let start = Int64((result.timeRange.start.seconds * sampleRate).rounded())
        onFrame?(ClassificationFrame(windowStart: start, groupScores: mapper.groupScores(labels)))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) { onError?(error) }
}
