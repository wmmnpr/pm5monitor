import SwiftUI
import AVFoundation
import Vision

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top: Camera with pose overlay
                ZStack {
                    CameraPreviewView(session: camera.session)
                        .ignoresSafeArea(edges: .top)

                    PoseOverlayView(poses: camera.detectedPoses)

                    // Connection status overlay
                    if !ble.isConnected {
                        VStack {
                            Spacer()
                            ConnectionOverlay(ble: ble)
                                .padding()
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                // Bottom: Watts display
                WattsDisplayView(watts: ble.currentWatts, isConnected: ble.isConnected)
                    .frame(height: 200)
            }
        }
        .onAppear {
            camera.startSession()
        }
        .onDisappear {
            camera.stopSession()
        }
    }
}

// MARK: - Watts Display

struct WattsDisplayView: View {
    let watts: Int
    let isConnected: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(white: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 8) {
                Text("\(watts)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundColor(wattsColor)
                    .minimumScaleFactor(0.5)

                Text("WATTS")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
            }
        }
    }

    var wattsColor: Color {
        if !isConnected { return .gray }
        if watts < 100 { return .green }
        if watts < 200 { return .yellow }
        if watts < 300 { return .orange }
        return .red
    }
}

// MARK: - Connection Overlay

struct ConnectionOverlay: View {
    @ObservedObject var ble: BLEManager

    var body: some View {
        VStack(spacing: 16) {
            if ble.isScanning {
                if ble.devices.isEmpty {
                    ProgressView()
                        .tint(.white)
                    Text("Scanning for PM5...")
                        .foregroundColor(.white)
                } else {
                    Text("Select your PM5")
                        .font(.headline)
                        .foregroundColor(.white)

                    ForEach(ble.devices, id: \.identifier) { device in
                        Button {
                            ble.connect(to: device)
                        } label: {
                            HStack {
                                Image(systemName: "figure.rower")
                                Text(device.name ?? "Unknown")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                }
            } else if ble.isConnecting {
                ProgressView()
                    .tint(.white)
                Text("Connecting...")
                    .foregroundColor(.white)
            } else {
                Button {
                    ble.startScanning()
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Connect to PM5")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Pose Overlay

struct PoseOverlayView: View {
    let poses: [DetectedPose]

    var body: some View {
        GeometryReader { geometry in
            ForEach(poses.indices, id: \.self) { index in
                PoseView(pose: poses[index], size: geometry.size)
            }
        }
    }
}

struct PoseView: View {
    let pose: DetectedPose
    let size: CGSize

    // Body connections for skeleton
    let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // Torso
        (.neck, .root),
        (.leftShoulder, .rightShoulder),
        (.leftHip, .rightHip),
        // Left arm
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        // Right arm
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        // Left leg
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        // Right leg
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        // Shoulders to neck
        (.leftShoulder, .neck),
        (.rightShoulder, .neck),
        // Hips to root
        (.leftHip, .root),
        (.rightHip, .root),
    ]

    var body: some View {
        ZStack {
            // Draw skeleton lines
            ForEach(connections.indices, id: \.self) { index in
                let connection = connections[index]
                if let from = pose.points[connection.0],
                   let to = pose.points[connection.1] {
                    Path { path in
                        path.move(to: transformPoint(from))
                        path.addLine(to: transformPoint(to))
                    }
                    .stroke(Color.green, lineWidth: 3)
                }
            }

            // Draw joint points
            ForEach(Array(pose.points.keys), id: \.rawValue) { joint in
                if let point = pose.points[joint] {
                    Circle()
                        .fill(jointColor(joint))
                        .frame(width: 12, height: 12)
                        .position(transformPoint(point))
                }
            }
        }
    }

    func transformPoint(_ point: CGPoint) -> CGPoint {
        // Vision coordinates are normalized (0-1) with origin at bottom-left
        // Need to flip Y and scale to view size
        CGPoint(
            x: point.x * size.width,
            y: (1 - point.y) * size.height
        )
    }

    func jointColor(_ joint: VNHumanBodyPoseObservation.JointName) -> Color {
        switch joint {
        case .nose, .leftEye, .rightEye, .leftEar, .rightEar:
            return .cyan
        case .leftShoulder, .leftElbow, .leftWrist:
            return .yellow
        case .rightShoulder, .rightElbow, .rightWrist:
            return .orange
        case .leftHip, .leftKnee, .leftAnkle:
            return .blue
        case .rightHip, .rightKnee, .rightAnkle:
            return .purple
        default:
            return .green
        }
    }
}

// MARK: - Detected Pose Model

struct DetectedPose {
    var points: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
}

#Preview {
    ContentView()
}
