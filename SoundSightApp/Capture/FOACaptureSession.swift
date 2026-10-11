import AVFoundation

enum CaptureError: LocalizedError {
    case noMicrophone
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No built-in microphone was found."
        case .cannotAddInput: "The microphone input couldn't be added to the capture session."
        case .cannotAddOutput: "The audio output couldn't be added to the capture session."
        }
    }
}

/// Audio-only AVCaptureSession delivering 4-channel FOA buffers, or mono when FOA is unsupported (spec §3.1, §8).
final class FOACaptureSession: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "soundsight.capture.session")
    private let bufferQueue = DispatchQueue(label: "soundsight.capture.buffers")
    private var configured = false
    /// False when the device can't capture FOA and the session fell back to mono.
    private(set) var foaEnabled = false
    /// Debug: what the audio connection reports about rotation, for the probe diagnostics.
    private(set) var connectionNote = ""

    /// Called on the buffer queue for every converted chunk.
    var onChunk: (@Sendable (FOAChunk) -> Void)?
    /// Called once, on the buffer queue, with the first buffer's format.
    var onFormat: (@Sendable (String) -> Void)?
    private var reportedFormat = false

    /// Builds the session once. Checks `canAdd…` first because AVFoundation raises an
    /// uncatchable NSInvalidArgumentException on commit for invalid configurations.
    func configure() throws {
        guard !configured else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else { throw CaptureError.noMicrophone }
        let input = try AVCaptureDeviceInput(device: device)
        let foa = input.isMultichannelAudioModeSupported(.firstOrderAmbisonics)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)
        if foa { input.multichannelAudioMode = .firstOrderAmbisonics }
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CaptureError.cannotAddOutput
        }
        session.addOutput(output)
        // FOA mode requires the 4-channel layout tag; any other mode requires the default tag.
        if foa { output.spatialAudioChannelLayoutTag = kAudioChannelLayoutTag_HOA_ACN_SN3D | 4 }
        output.setSampleBufferDelegate(self, queue: bufferQueue)
        foaEnabled = foa
        configured = true
        // Debug: does the audio connection expose a rotation (FOA may follow device orientation)?
        if let connection = output.connection(with: .audio) {
            let angles = [0.0, 90, 180, 270].filter { connection.isVideoRotationAngleSupported(CGFloat($0)) }
            connectionNote = "audio connection rotation supported: \(angles.isEmpty ? "none" : angles.map { "\(Int($0))" }.joined(separator: ","))"
        }
    }

    func start() { sessionQueue.async { self.session.startRunning() } }
    func stop() { sessionQueue.async { self.session.stopRunning() } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !reportedFormat {
            reportedFormat = true
            onFormat?(FOABufferAdapter.describe(sampleBuffer))
        }
        if let chunk = FOABufferAdapter.chunk(from: sampleBuffer) { onChunk?(chunk) }
    }
}
