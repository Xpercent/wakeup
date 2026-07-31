import AVFoundation
import Vision

final class PushUpCounter: NSObject, ObservableObject {
    @Published private(set) var count = 0
    @Published private(set) var status = "Position your whole upper body in frame"
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.frames")
    private var phase: Phase = .up
    private var lastRep = Date.distantPast
    private enum Phase { case up, down }

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
              let leftWrist = try? pose.recognizedPoint(.leftWrist),
              let rightWrist = try? pose.recognizedPoint(.rightWrist),
              leftShoulder.confidence > 0.35, rightShoulder.confidence > 0.35,
              leftWrist.confidence > 0.35, rightWrist.confidence > 0.35 else { return }
        let shoulderY = (leftShoulder.location.y + rightShoulder.location.y) / 2
        let wristY = (leftWrist.location.y + rightWrist.location.y) / 2
        let delta = shoulderY - wristY
        DispatchQueue.main.async {
            self.status = "Keep shoulders and wrists visible"
            if self.phase == .up && delta < 0.04 { self.phase = .down; self.status = "Down - push back up" }
            if self.phase == .down && delta > 0.12 && Date().timeIntervalSince(self.lastRep) > 0.8 {
                self.phase = .up; self.lastRep = Date(); self.count += 1; self.status = "Rep counted"
            }
        }
    }
}
