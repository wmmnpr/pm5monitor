import SwiftUI
import AVFoundation
import Vision

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            // Full screen camera with pose overlay
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            PoseOverlayView(poses: camera.detectedPoses)
                .ignoresSafeArea()

            // Translucent overlays
            VStack {
                Spacer()

                // Force curve at bottom-left
                HStack {
                    ForceCurveView(forceData: ble.forceHistory)
                        .frame(width: 150, height: 100)
                        .padding()

                    Spacer()

                    // Watts display at bottom-right
                    WattsOverlayView(watts: ble.currentWatts, isConnected: ble.isConnected)
                        .padding()
                }
                .padding(.bottom, 30)
            }

            // Connection overlay when not connected
            if !ble.isConnected {
                VStack {
                    Spacer()
                    ConnectionOverlay(ble: ble)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 150)
                }
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

// MARK: - Translucent Watts Overlay

struct WattsOverlayView: View {
    let watts: Int
    let isConnected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("\(watts)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(wattsColor)

            Text("WATTS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.4))
                .background(.ultraThinMaterial.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
    }

    var wattsColor: Color {
        if !isConnected { return .white.opacity(0.5) }
        if watts < 100 { return .green }
        if watts < 200 { return .yellow }
        if watts < 300 { return .orange }
        return .red
    }
}

// MARK: - Force Curve View

struct ForceCurveView: View {
    let forceData: [Double]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.4))
                .background(.ultraThinMaterial.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("FORCE")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.7))

                GeometryReader { geometry in
                    if forceData.isEmpty {
                        // Placeholder curve
                        Path { path in
                            let width = geometry.size.width
                            let height = geometry.size.height
                            path.move(to: CGPoint(x: 0, y: height))
                            path.addQuadCurve(
                                to: CGPoint(x: width, y: height),
                                control: CGPoint(x: width * 0.4, y: height * 0.3)
                            )
                        }
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                    } else {
                        // Actual force curve
                        ForceCurvePath(data: forceData, size: geometry.size)
                            .stroke(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 2
                            )

                        // Fill under curve
                        ForceCurvePath(data: forceData, size: geometry.size, closed: true)
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.4), .blue.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            }
            .padding(10)
        }
    }
}

struct ForceCurvePath: Shape {
    let data: [Double]
    let size: CGSize
    var closed: Bool = false

    func path(in rect: CGRect) -> Path {
        guard data.count > 1 else {
            return Path()
        }

        let maxForce = data.max() ?? 1
        let stepX = size.width / CGFloat(data.count - 1)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))

        for (index, force) in data.enumerated() {
            let x = CGFloat(index) * stepX
            let y = size.height - (CGFloat(force / maxForce) * size.height * 0.9)
            if index == 0 {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        if closed {
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }

        return path
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
                            .background(Color.blue.opacity(0.8))
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
                    .background(Color.blue.opacity(0.8))
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

    let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.neck, .root),
        (.leftShoulder, .rightShoulder),
        (.leftHip, .rightHip),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        (.leftShoulder, .neck),
        (.rightShoulder, .neck),
        (.leftHip, .root),
        (.rightHip, .root),
    ]

    var body: some View {
        ZStack {
            ForEach(connections.indices, id: \.self) { index in
                let connection = connections[index]
                if let from = pose.points[connection.0],
                   let to = pose.points[connection.1] {
                    Path { path in
                        path.move(to: transformPoint(from))
                        path.addLine(to: transformPoint(to))
                    }
                    .stroke(Color.green.opacity(0.8), lineWidth: 3)
                }
            }

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
