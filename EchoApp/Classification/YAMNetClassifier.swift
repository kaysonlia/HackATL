@preconcurrency import AVFoundation
import CoreML
import EchoCore

/// YAMNet (Google's open model, converted to Core ML) on the CPU, with the log-mel frontend in Swift.
/// Plain Core ML CPU inference keeps working in the background, where SoundAnalysis fails.
/// Not thread-safe: call `analyze` from one serial queue; results arrive synchronously on it.
final class YAMNetClassifier: SoundClassifier, @unchecked Sendable {
    /// Hop between windows in 16 kHz samples (0.5 s, matching the direction windows).
    static let hopLength = 8_000

    /// Loads the bundled network for CPU-only inference (allowed in the background).
    static func loadModel() throws -> MLModel {
        guard let url = Bundle.main.url(forResource: "YAMNet", withExtension: "mlmodelc") else {
            throw ResourceError.missing("YAMNet.mlmodelc")
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        return try MLModel(contentsOf: url, configuration: config)
    }

    private final class ConverterInput: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        var consumed = false
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    private let model: MLModel
    private let frontend: YAMNetFrontend
    private let mapper: LabelMapper
    private let sampleRate: Double
    private let startSample: Int64
    private let converter: AVAudioConverter
    private let inFormat: AVAudioFormat
    private let outFormat: AVAudioFormat
    /// 16 kHz samples not yet consumed, and the 16 kHz index of `pending[0]` since this classifier started.
    private var pending: [Float] = []
    private var pendingStart = 0

    var onFrame: ((ClassificationFrame) -> Void)?
    var onError: ((Error) -> Void)?
    var onLabels: ((Int64, [String: Double]) -> Void)?

    init(sampleRate: Double, model: MLModel, frontend: YAMNetFrontend, mapper: LabelMapper, startSample: Int64 = 0) throws {
        guard let inFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let outFormat = AVAudioFormat(standardFormatWithSampleRate: YAMNetFrontend.sampleRate, channels: 1),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw ResourceError.malformed("can't resample \(sampleRate) Hz to 16 kHz")
        }
        self.sampleRate = sampleRate
        self.model = model
        self.frontend = frontend
        self.mapper = mapper
        self.startSample = startSample
        self.inFormat = inFormat
        self.outFormat = outFormat
        self.converter = converter
    }

    func analyze(_ mono: [Float]) {
        pending += resample(mono)
        while pending.count >= YAMNetFrontend.windowLength {
            classify(Array(pending[0..<YAMNetFrontend.windowLength]), start16k: pendingStart)
            pending.removeFirst(Self.hopLength)
            pendingStart += Self.hopLength
        }
    }

    private func resample(_ mono: [Float]) -> [Float] {
        guard !mono.isEmpty,
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(mono.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: AVAudioFrameCount(Double(mono.count) * YAMNetFrontend.sampleRate / sampleRate) + 64)
        else { return [] }
        input.frameLength = AVAudioFrameCount(mono.count)
        mono.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: mono.count) }
        let source = ConverterInput(input)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if source.consumed {
                status.pointee = .noDataNow
                return nil
            }
            source.consumed = true
            status.pointee = .haveData
            return source.buffer
        }
        if let error { onError?(error) }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    private func classify(_ samples: [Float], start16k: Int) {
        do {
            let logMel = frontend.logMel(samples)
            let patch = try MLMultiArray(shape: [1, NSNumber(value: YAMNetFrontend.frames), NSNumber(value: YAMNetFrontend.mels)],
                                         dataType: .float32)
            logMel.withUnsafeBufferPointer { src in
                patch.dataPointer.assumingMemoryBound(to: Float.self).update(from: src.baseAddress!, count: logMel.count)
            }
            let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["patch": patch]))
            guard let scores = out.featureValue(for: "Identity")?.multiArrayValue else { return }
            var labels: [String: Double] = [:]
            for i in 0..<scores.count { labels[String(i)] = scores[i].doubleValue }
            let start = startSample + Int64((Double(start16k) * sampleRate / YAMNetFrontend.sampleRate).rounded())
            onLabels?(start, labels.filter { $0.value >= 0.05 })
            onFrame?(ClassificationFrame(windowStart: start, groupScores: mapper.groupScores(labels)))
        } catch {
            onError?(error)
        }
    }
}
