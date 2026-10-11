import Accelerate
import Foundation

/// YAMNet's log-mel frontend (models/research/audioset/yamnet/features.py) in Swift, so the converted
/// YAMNet network can run in the background without TensorFlow or SoundAnalysis.
/// 16 kHz audio → 25 ms periodic-Hann frames every 10 ms → |512-point FFT| → 64 mel bands
/// (125–7500 Hz, TensorFlow's weight matrix) → log(mel + 0.001). One 0.975 s window gives one 96×64 patch.
public final class YAMNetFrontend: @unchecked Sendable {
    public static let sampleRate = 16_000.0
    public static let frameLength = 400
    public static let hopLength = 160
    public static let fftLength = 512
    public static let frames = 96
    public static let mels = 64
    /// Samples in one patch: 400 + 95 × 160 = 15 600 (0.975 s).
    public static let windowLength = frameLength + (frames - 1) * hopLength
    static let bins = fftLength / 2 + 1
    static let logOffset: Float = 0.001

    private let melWeights: [Float]  // bins × mels, row-major
    private let window: [Float]
    private let dft: vDSP.DiscreteFourierTransform<Float>

    public init(melWeights: [Float]) throws {
        guard melWeights.count == Self.bins * Self.mels else {
            throw ResourceError.malformed("mel matrix needs \(Self.bins)×\(Self.mels) weights, got \(melWeights.count)")
        }
        self.melWeights = melWeights
        // tf.signal.hann_window(periodic=True): 0.5 − 0.5·cos(2πn/N).
        window = (0..<Self.frameLength).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(Self.frameLength))) }
        dft = try vDSP.DiscreteFourierTransform(count: Self.fftLength, direction: .forward,
                                               transformType: .complexComplex, ofType: Float.self)
    }

    /// Loads `yamnet_mel.json` (`{"weights": [bins × mels]}`) from the package bundle.
    public static func bundled() throws -> YAMNetFrontend {
        guard let url = Bundle.module.url(forResource: "yamnet_mel", withExtension: "json") else {
            throw ResourceError.missing("yamnet_mel.json")
        }
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let weights = root["weights"] as? [Double] else {
            throw ResourceError.malformed("yamnet_mel.json needs a \"weights\" array")
        }
        return try YAMNetFrontend(melWeights: weights.map(Float.init))
    }

    /// `samples`: `windowLength` samples at 16 kHz. Returns `frames × mels` log-mel values, row-major.
    public func logMel(_ samples: [Float]) -> [Float] {
        precondition(samples.count >= Self.windowLength, "need \(Self.windowLength) samples")
        let zeros = [Float](repeating: 0, count: Self.fftLength)
        var magnitudes = [Float](repeating: 0, count: Self.frames * Self.bins)
        var frame = [Float](repeating: 0, count: Self.fftLength)
        for f in 0..<Self.frames {
            let start = f * Self.hopLength
            for i in 0..<Self.frameLength { frame[i] = samples[start + i] * window[i] }
            let out = dft.transform(real: frame, imaginary: zeros)
            for b in 0..<Self.bins {
                magnitudes[f * Self.bins + b] = (out.real[b] * out.real[b] + out.imaginary[b] * out.imaginary[b]).squareRoot()
            }
        }
        var mel = [Float](repeating: 0, count: Self.frames * Self.mels)
        vDSP_mmul(magnitudes, 1, melWeights, 1, &mel, 1, vDSP_Length(Self.frames), vDSP_Length(Self.mels), vDSP_Length(Self.bins))
        return mel.map { log($0 + Self.logOffset) }
    }
}

/// YAMNet tables: class index → sound group (`yamnet_to_group.json`) and per-group thresholds.
public struct YAMNetResources: Sendable {
    public let mapper: LabelMapper
    public let thresholds: GroupThresholds

    public static func bundled() throws -> YAMNetResources {
        func load(_ name: String) throws -> Data {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
                throw ResourceError.missing("\(name).json")
            }
            return try Data(contentsOf: url)
        }
        return YAMNetResources(mapper: try LabelMapper(json: load("yamnet_to_group")),
                               thresholds: try GroupThresholds(json: load("yamnet_thresholds")))
    }
}
