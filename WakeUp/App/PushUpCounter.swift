import AVFoundation
import Vision

final class PushUpCounter: NSObject, ObservableObject {
    @Published private(set) var count = 0
    @Published private(set) var status = "Position your whole upper body in frame"
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.frames")
    private var phase: Phase = .ready
    private var lastRep = Date.distantPast
    private var highestShoulderY: CGFloat = 0
    private var lowestShoulderY: CGFloat = 1
    private enum Phase { case ready, down }

    func start() async {
        guard !session.isRunning else { return }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard allowed else { await MainActor.run { self.status = "Camera permission is required" }; return }
        session.beginConfiguration(); session.sessionPreset = .high
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front), let input = try? AVCaptureDeviceInput(device: camera) else { return }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true; output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration(); queue.async { self.session.startRunning() }
    }
}

extension PushUpCounter: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored).perform([request])
        guard let pose = request.results?.first,
              let leftShoulder = try? pose.recognizedPoint(.leftShoulder),
              let rightShoulder = try? pose.recognizedPoint(.rightShoulder),
              leftShoulder.confidence > 0.35, rightShoulder.confidence > 0.35 else { return }
        let shoulderY = (leftShoulder.location.y + rightShoulder.location.y) / 2
        DispatchQueue.main.async {
            // Shoulder descent followed by a rise forms one repetition. The
            // reference range is learned from the person currently in frame.
            self.highestShoulderY = max(self.highestShoulderY, shoulderY)
            self.lowestShoulderY = min(self.lowestShoulderY, shoulderY)
            let movement: CGFloat = 0.055
            if self.phase == .ready && self.highestShoulderY - shoulderY > movement {
                self.phase = .down
                self.lowestShoulderY = shoulderY
                self.status = "Down detected - push up"
            } else if self.phase == .down {
                self.lowestShoulderY = min(self.lowestShoulderY, shoulderY)
                if shoulderY - self.lowestShoulderY > movement && Date().timeIntervalSince(self.lastRep) > 0.8 {
                    self.phase = .ready
                    self.lastRep = Date()
                    self.count += 1
                    self.highestShoulderY = shoulderY
                    self.status = "Rep counted"
                }
            }
        }
    }
}
