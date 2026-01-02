import SwiftUI

struct RaceView: View {
    @ObservedObject var raceService: RaceService
    @ObservedObject var bleManager: BLEManager

    @State private var previousMetrics: RowingMetrics?

    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Race header with distance info
                RaceHeaderView(
                    targetDistance: raceService.currentRace?.targetDistance ?? 2000,
                    currentDistance: bleManager.currentMetrics.distance
                )

                // Race track visualization
                RaceTrackView(
                    participants: raceService.participants,
                    myProgress: raceService.myProgress,
                    targetDistance: Double(raceService.currentRace?.targetDistance ?? 2000)
                )
                .frame(height: 180)
                .padding(.vertical, 8)

                // Main metrics display
                MainRaceMetrics(
                    metrics: bleManager.currentMetrics,
                    targetDistance: Double(raceService.currentRace?.targetDistance ?? 2000)
                )

                Spacer()

                // Bottom metrics panel
                BottomMetricsPanel(
                    metrics: bleManager.currentMetrics,
                    progress: raceService.myProgress
                )
            }

            // Countdown overlay
            if case .countdown(let seconds) = raceService.raceState {
                CountdownOverlay(seconds: seconds)
            }

            // Finish overlay
            if case .finished(let position) = raceService.raceState {
                RaceFinishedOverlay(position: position)
            }
        }
        .onChange(of: bleManager.currentMetrics) { newMetrics in
            sendUpdate(metrics: newMetrics)
        }
    }

    private func sendUpdate(metrics: RowingMetrics) {
        guard raceService.raceState.isRacing else { return }

        guard raceService.validateMetrics(metrics, previous: previousMetrics) else {
            return
        }

        previousMetrics = metrics

        Task {
            try? await raceService.sendUpdate(
                participantId: "current-user",
                metrics: metrics
            )
        }
    }
}

// MARK: - Race Header View

struct RaceHeaderView: View {
    let targetDistance: Int
    let currentDistance: Double

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("RACE")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(RaceDistance.fromMeters(targetDistance).displayName)
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("REMAINING")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("\(max(0, targetDistance - Int(currentDistance)))m")
                    .font(.title2.bold())
                    .foregroundColor(.cyan)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
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
                // Track lanes
                ForEach(0..<max(1, sortedParticipants.count + 1), id: \.self) { index in
                    let yPosition = laneYPosition(for: index, in: geometry.size.height)

                    // Lane line
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(height: 2)
                        .position(x: geometry.size.width / 2, y: yPosition)
                }

                // Start line
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 2, height: geometry.size.height)
                    .position(x: 30, y: geometry.size.height / 2)

                // Finish line
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        Rectangle()
                            .fill(i % 2 == 0 ? Color.white : Color.black)
                            .frame(width: 8, height: 15)
                    }
                }
                .position(x: geometry.size.width - 20, y: geometry.size.height / 2)

                // My boat
                if let progress = myProgress {
                    BoatView(
                        name: "YOU",
                        position: calculateXPosition(progress: progress.percentComplete, width: geometry.size.width),
                        yPosition: laneYPosition(for: 0, in: geometry.size.height),
                        color: .cyan,
                        isMe: true
                    )
                }

                // Other participants
                ForEach(Array(sortedParticipants.enumerated()), id: \.element.id) { index, participant in
                    BoatView(
                        name: String(participant.displayName.prefix(6)),
                        position: calculateXPosition(
                            progress: participant.progress(toward: targetDistance),
                            width: geometry.size.width
                        ),
                        yPosition: laneYPosition(for: index + 1, in: geometry.size.height),
                        color: .white,
                        isMe: false
                    )
                }
            }
        }
        .background(Color.black)
    }

    private var sortedParticipants: [RaceParticipant] {
        participants.filter { $0.id != "current-user" }.sorted { $0.distance > $1.distance }
    }

    private func laneYPosition(for index: Int, in height: CGFloat) -> CGFloat {
        let laneCount = max(2, sortedParticipants.count + 1)
        let laneHeight = height / CGFloat(laneCount)
        return (CGFloat(index) + 0.5) * laneHeight
    }

    private func calculateXPosition(progress: Double, width: CGFloat) -> CGFloat {
        let trackStart: CGFloat = 40
        let trackEnd = width - 30
        let trackLength = trackEnd - trackStart
        return trackStart + (trackLength * CGFloat(min(1.0, progress)))
    }
}

struct BoatView: View {
    let name: String
    let position: CGFloat
    let yPosition: CGFloat
    let color: Color
    let isMe: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.rowing")
                .font(isMe ? .title2 : .body)
                .foregroundColor(color)
                .scaleEffect(x: -1, y: 1)

            Text(name)
                .font(isMe ? .caption.bold() : .caption2)
                .foregroundColor(color)
        }
        .position(x: position, y: yPosition)
    }
}

// MARK: - Main Race Metrics

struct MainRaceMetrics: View {
    let metrics: RowingMetrics
    let targetDistance: Double

    var body: some View {
        VStack(spacing: 24) {
            // Large time display
            VStack(spacing: 4) {
                Text("TIME")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(metrics.formattedElapsedTime)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: min(1.0, metrics.distance / targetDistance))
                    .tint(.cyan)
                    .scaleEffect(y: 2)

                HStack {
                    Text("\(Int(metrics.distance))m")
                        .foregroundColor(.cyan)
                    Spacer()
                    Text("\(Int(targetDistance))m")
                        .foregroundColor(.gray)
                }
                .font(.caption)
            }
            .padding(.horizontal, 32)

            // Distance display
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text("DISTANCE")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(Int(metrics.distance))")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("meters")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                VStack(spacing: 4) {
                    Text("PACE")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(metrics.formattedPace)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("/500m")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
    }
}

// MARK: - Bottom Metrics Panel

struct BottomMetricsPanel: View {
    let metrics: RowingMetrics
    let progress: RaceProgress?

    var body: some View {
        HStack(spacing: 0) {
            MetricBox(title: "WATTS", value: "\(metrics.watts)")
            Divider().frame(height: 50).background(Color.gray)
            MetricBox(title: "S/M", value: "\(metrics.strokeRate)")
            Divider().frame(height: 50).background(Color.gray)
            MetricBox(title: "STROKES", value: "\(metrics.strokeCount)")
            Divider().frame(height: 50).background(Color.gray)
            MetricBox(
                title: "POSITION",
                value: progress.map { "\($0.positionInRace)/\($0.totalParticipants)" } ?? "-"
            )
        }
        .padding(.vertical, 16)
        .background(Color(.systemGray6).opacity(0.5))
    }
}

struct MetricBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Countdown Overlay

struct CountdownOverlay: View {
    let seconds: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("GET READY")
                    .font(.title2)
                    .foregroundColor(.gray)

                Text("\(seconds)")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundColor(.cyan)

                Text(seconds == 1 ? "ROW!" : "")
                    .font(.largeTitle.bold())
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - Race Finished Overlay

struct RaceFinishedOverlay: View {
    let position: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Medal/trophy icon
                Image(systemName: medalIcon)
                    .font(.system(size: 80))
                    .foregroundColor(positionColor)

                // Position
                Text(positionText)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(positionColor)

                Text(positionLabel)
                    .font(.title)
                    .foregroundColor(.white)

                if position <= 3 {
                    Text("Prize pool distributed!")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }

                Spacer()
                    .frame(height: 40)

                Button {
                    // Navigate back to results
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
        case 2: return Color(.systemGray)
        case 3: return .orange
        default: return .white
        }
    }

    private var medalIcon: String {
        switch position {
        case 1: return "trophy.fill"
        case 2: return "medal.fill"
        case 3: return "medal.fill"
        default: return "checkmark.circle.fill"
        }
    }
}

#Preview {
    RaceView(
        raceService: RaceService(),
        bleManager: BLEManager()
    )
}
