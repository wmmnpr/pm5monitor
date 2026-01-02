import AVFoundation
import Vision
import UIKit

class CameraManager: NSObject, ObservableObject {

    @MainActor @Published var detectedPoses: [DetectedPose] = []
    @MainActor @Published var isRunning: Bool = false

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "pose.processing", qos: .userInitiated)

    private var poseRequest: VNDetectHumanBodyPoseRequest?

    override init() {
        super.init()
        setupPoseDetection()
        setupCamera()
    }

    private func setupPoseDetection() {
        poseRequest = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard error == nil,
                  let observations = request.results as? [VNHumanBodyPoseObservation] else {
                return
            }

            let poses = observations.compactMap { observation -> DetectedPose? in
                self?.extractPose(from: observation)
            }

            Task { @MainActor [weak self] in
                self?.detectedPoses = poses
            }
        }
    }

    private func extractPose(from observation: VNHumanBodyPoseObservation) -> DetectedPose? {
        var pose = DetectedPose()

        let joints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .leftEye, .rightEye, .leftEar, .rightEar,
            .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
            .neck, .root
        ]

        for joint in joints {
            if let point = try? observation.recognizedPoint(joint),
               point.confidence > 0.3 {
                pose.points[joint] = CGPoint(x: point.location.x, y: point.location.y)
            }
        }

        return pose.points.isEmpty ? nil : pose
    }

    private func setupCamera() {
        // Check permission first
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.configureSession()
                    }
                }
            }
        default:
            break
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Use front camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Set video orientation
        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
    }

    func startSession() {
        guard !session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.startRunning()
            Task { @MainActor [weak self] in
                self?.isRunning = true
            }
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.stopRunning()
            Task { @MainActor [weak self] in
                self?.isRunning = false
            }
        }
    }
}

// MARK: - Video Delegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let poseRequest = poseRequest else {
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([poseRequest])
        } catch {
            print("Pose detection error: \(error)")
        }
    }
}
