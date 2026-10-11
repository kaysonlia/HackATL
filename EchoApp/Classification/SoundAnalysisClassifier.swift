import AVFoundation
import EchoCore
import SoundAnalysis

/// A classifier fed mono audio that reports sound group scores per window (spec §3.2).
/// Implemented by Apple's SoundAnalysis (foreground) and YAMNet on the CPU (background).
protocol SoundClassifier: AnyObject {
    var onFrame: ((ClassificationFrame) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    /// Debug: raw label scores per window start, delivered just before `onFrame`.
    var onLabels: ((Int64, [String: Double]) -> Void)? { get set }
    /// Appends the next block of mono samples (continuous with the previous call).
    func analyze(_ mono: [Float])
}

/// Apple's built-in sound classifier over the omni (W) channel. It fails in the background
/// (SNError 2: its feature extractor isn't allowed to run there), so the pipeline swaps in YAMNet.
/// Not thread-safe: call `analyze` from one serial queue; results arrive synchronously on it.
final class SoundAnalysisClassifier: NSObject, SoundClassifier, SNResultsObserving, @unchecked Sendable {
    private let analyzer: SNAudioStreamAnalyzer
    private let format: AVAudioFormat
    private let mapper: LabelMapper
    private let sampleRate: Double
    /// Capture sample index of this classifier's first sample, so window starts stay on the capture timeline.
    private let startSample: Int64
    private var framePosition: AVAudioFramePosition = 0

    var onFrame: ((ClassificationFrame) -> Void)?
    var onError: ((Error) -> Void)?
    var onLabels: ((Int64, [String: Double]) -> Void)?

    init(sampleRate: Double, mapper: LabelMapper, startSample: Int64 = 0) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw ResourceError.malformed("unsupported sample rate \(sampleRate)")
        }
        self.format = format
        self.sampleRate = sampleRate
        self.mapper = mapper
        self.startSample = startSample
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
        let start = startSample + Int64((result.timeRange.start.seconds * sampleRate).rounded())
        onLabels?(start, labels)
        onFrame?(ClassificationFrame(windowStart: start, groupScores: mapper.groupScores(labels)))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) { onError?(error) }
}
