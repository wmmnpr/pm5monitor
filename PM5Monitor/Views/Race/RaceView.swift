import SwiftUI

struct RaceView: View {
    @ObservedObject var raceService: RaceService
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var cameraManager: CameraManager

    @State private var previousMetrics: RowingMetrics?

    var body: some View {
        ZStack {
            // Camera background
            if cameraManager.isRunning {
                CameraPreviewView(session: cameraManager.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Race content
            VStack(spacing: 0) {
                // Race track visualization
                RaceTrackView(
                    participants: raceService.participants,
                    myProgress: raceService.myProgress,
                    targetDistance: Double(raceService.currentRace?.targetDistance ?? 5000)
                )
                .frame(height: 200)
                .background(.ultraThinMaterial)

                Spacer()

                // Countdown overlay
                if case .countdown(let seconds) = raceService.raceState {
                    CountdownView(seconds: seconds)
                }

                Spacer()

                // Bottom metrics panel
                RaceMetricsPanel(
                    metrics: bleManager.currentMetrics,
                    progress: raceService.myProgress
                )
            }

            // Finish overlay
            if case .finished(let position) = raceService.raceState {
                RaceFinishedOverlay(position: position)
            }
        }
        .onChange(of: bleManager.currentMetrics) { newMetrics in
            sendUpdate(metrics: newMetrics)
        }
        .onAppear {
            cameraManager.startSession()
        }
    }

    private func sendUpdate(metrics: RowingMetrics) {
        guard raceService.raceState.isRacing else { return }

        // Validate metrics
        guard raceService.validateMetrics(metrics, previous: previousMetrics) else {
            return
        }

        previousMetrics = metrics

        Task {
            try? await raceService.sendUpdate(
                participantId: "current-user", // Would come from auth
                metrics: metrics
            )
        }
    }
}

// MARK: - Race Track View

struct RaceTrackView: View {
    let participants: [RaceParticipant]
    let myProgress: RaceProgress?
    let targetDistance: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Track background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.2))
                    .frame(height: 40)
                    .padding(.horizontal, 20)
                    .offset(y: geometry.size.height / 2 - 20)

                // Finish line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 3, height: 60)
                    .position(x: geometry.size.width - 30, y: geometry.size.height / 2)

                Text("FINISH")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .position(x: geometry.size.width - 30, y: geometry.size.height / 2 - 40)

                // Participants
                ForEach(Array(sortedParticipants.enumerated()), id: \.element.id) { index, participant in
                    ParticipantBoat(
                        participant: participant,
                        isMe: participant.id == "current-user",
                        position: calculatePosition(
                            progress: participant.progress(toward: targetDistance),
                            width: geometry.size.width
                        ),
                        verticalOffset: CGFloat(index) * 25
                    )
                }

                // My boat (if not in participants list)
                if let progress = myProgress {
                    MyBoat(
                        progress: progress,
                        position: calculatePosition(
                            progress: progress.percentComplete,
                            width: geometry.size.width
                        )
                    )
                }
            }
        }
    }

    private var sortedParticipants: [RaceParticipant] {
        participants.sorted { $0.distance > $1.distance }
    }

    private func calculatePosition(progress: Double, width: CGFloat) -> CGFloat {
        let trackStart: CGFloat = 40
        let trackEnd = width - 40
        let trackLength = trackEnd - trackStart
        return trackStart + (trackLength * CGFloat(progress))
    }
}

struct ParticipantBoat: View {
    let participant: RaceParticipant
    let isMe: Bool
    let position: CGFloat
    let verticalOffset: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Text(participant.displayName.prefix(8))
                .font(.caption2)
                .foregroundColor(isMe ? .cyan : .white)

            Image(systemName: "figure.rowing")
                .font(.title2)
                .foregroundColor(isMe ? .cyan : .white)
                .scaleEffect(x: -1, y: 1)
        }
        .position(x: position, y: 60 + verticalOffset)
    }
}

struct MyBoat: View {
    let progress: RaceProgress
    let position: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Text("YOU")
                .font(.caption2.bold())
                .foregroundColor(.cyan)

            Image(systemName: "figure.rowing")
                .font(.title)
                .foregroundColor(.cyan)
                .scaleEffect(x: -1, y: 1)

            Text("\(Int(progress.distance))m")
                .font(.caption2)
                .foregroundColor(.cyan)
        }
        .position(x: position, y: 100)
    }
}

// MARK: - Countdown View

struct CountdownView: View {
    let seconds: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: 150, height: 150)

            Text("\(seconds)")
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(.cyan)
        }
    }
}

// MARK: - Race Metrics Panel

struct RaceMetricsPanel: View {
    let metrics: RowingMetrics
    let progress: RaceProgress?

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            if let progress = progress {
                ProgressView(value: progress.percentComplete)
                    .tint(.cyan)
                    .padding(.horizontal)
                    .padding(.top, 8)

                HStack {
                    Text("\(Int(progress.distance))m")
                    Spacer()
                    Text("\(Int(progress.targetDistance))m")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            }

            // Metrics grid
            HStack(spacing: 0) {
                RaceMetricBox(
                    title: "PACE",
                    value: metrics.formattedPace,
                    unit: "/500m"
                )

                Divider()
                    .frame(height: 60)

                RaceMetricBox(
                    title: "WATTS",
                    value: "\(metrics.watts)",
                    unit: "W"
                )

                Divider()
                    .frame(height: 60)

                RaceMetricBox(
                    title: "S/M",
                    value: "\(metrics.strokeRate)",
                    unit: ""
                )

                Divider()
                    .frame(height: 60)

                RaceMetricBox(
                    title: "POS",
                    value: progress.map { "\($0.positionInRace)" } ?? "-",
                    unit: progress.map { "/\($0.totalParticipants)" } ?? ""
                )
            }
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }
}

struct RaceMetricBox: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))

                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Race Finished Overlay

struct RaceFinishedOverlay: View {
    let position: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Position
                Text(positionText)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(positionColor)

                Text(positionLabel)
                    .font(.title)
                    .foregroundColor(.white)

                // Medal
                Image(systemName: medalIcon)
                    .font(.system(size: 80))
                    .foregroundColor(positionColor)

                Spacer()
                    .frame(height: 40)

                // Continue button
                Button {
                    // Navigate back
                } label: {
                    Text("View Results")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(width: 200, height: 50)
                        .background(Color.white)
                        .cornerRadius(25)
                }
            }
        }
    }

    private var positionText: String {
        switch position {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(position)th"
        }
    }

    private var positionLabel: String {
        switch position {
        case 1: return "WINNER!"
        case 2: return "Second Place"
        case 3: return "Third Place"
        default: return "Finished"
        }
    }

    private var positionColor: Color {
        switch position {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .white
        }
    }

    private var medalIcon: String {
        switch position {
        case 1: return "medal.fill"
        case 2: return "medal.fill"
        case 3: return "medal.fill"
        default: return "checkmark.circle.fill"
        }
    }
}

#Preview {
    RaceView(
        raceService: RaceService(),
        bleManager: BLEManager(),
        cameraManager: CameraManager()
    )
}
