import SwiftUI

struct RaceView: View {
    @ObservedObject var raceService: RaceService
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var networkService: NetworkService
    var currentUserId: String

    @State private var previousMetrics: RowingMetrics?

    private var targetDistance: Int {
        networkService.currentRace?.targetDistance ?? raceService.currentRace?.targetDistance ?? 2000
    }

    private var serverParticipants: [ServerRaceParticipant] {
        networkService.currentRace?.participants ?? []
    }

    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Race header with distance info
                RaceHeaderView(
                    targetDistance: targetDistance,
                    currentDistance: bleManager.currentMetrics.distance
                )

                // Race track visualization - use server participants if available
                if !serverParticipants.isEmpty {
                    MultiRacerLaneView(
                        participants: serverParticipants,
                        currentUserId: currentUserId,
                        currentUserDistance: bleManager.currentMetrics.distance,
                        targetDistance: Double(targetDistance)
                    )
                    .frame(height: CGFloat(max(2, serverParticipants.count)) * 45)
                    .padding(.vertical, 8)
                } else {
                    RaceTrackView(
                        participants: raceService.participants,
                        myProgress: raceService.myProgress,
                        targetDistance: Double(targetDistance),
                        myEquipmentType: raceService.myEquipmentType
                    )
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }

                // Main metrics display
                MainRaceMetrics(
                    metrics: bleManager.currentMetrics,
                    targetDistance: Double(targetDistance)
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
        // Allow updates if in local race state OR if there's an active server race
        let isInRace = raceService.raceState.isRacing || networkService.currentRace?.status == "active"
        guard isInRace else { return }

        guard raceService.validateMetrics(metrics, previous: previousMetrics) else {
            return
        }

        previousMetrics = metrics

        Task {
            // Send to local race service
            try? await raceService.sendUpdate(
                participantId: currentUserId,
                metrics: metrics
            )

            // Send to network server for real-time sync with other racers
            if let raceId = networkService.currentRace?.id {
                await networkService.sendRaceUpdate(
                    raceId: raceId,
                    oderId: currentUserId,
                    distance: metrics.distance,
                    pace: metrics.pace,
                    watts: metrics.watts
                )
            }
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

// MARK: - Race Track View (ErgRace Style)

struct RaceTrackView: View {
    let participants: [RaceParticipant]
    let myProgress: RaceProgress?
    let targetDistance: Double
    var myEquipmentType: EquipmentType = .rower

    private let laneColors: [Color] = [
        Color(red: 0.1, green: 0.3, blue: 0.5),  // Dark blue
        Color(red: 0.15, green: 0.35, blue: 0.55), // Slightly lighter
    ]

    var body: some View {
        GeometryReader { geometry in
            let laneCount = max(2, allRacers.count)
            let laneHeight = geometry.size.height / CGFloat(laneCount)

            ZStack {
                // Lane backgrounds (alternating water colors)
                VStack(spacing: 0) {
                    ForEach(0..<laneCount, id: \.self) { index in
                        Rectangle()
                            .fill(laneColors[index % 2])
                            .frame(height: laneHeight)
                    }
                }

                // Distance markers
                ForEach(distanceMarkers, id: \.self) { marker in
                    let xPos = calculateXPosition(progress: marker / targetDistance, width: geometry.size.width)

                    VStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 1, height: geometry.size.height)

                        Text("\(Int(marker))m")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .position(x: xPos, y: geometry.size.height / 2)
                }

                // Lane dividers
                ForEach(0..<laneCount, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: geometry.size.width, height: 1)
                            .position(x: geometry.size.width / 2, y: CGFloat(index) * laneHeight)
                    }
                }

                // Start line
                Rectangle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 3, height: geometry.size.height)
                    .position(x: 35, y: geometry.size.height / 2)

                // Finish line (checkered pattern)
                HStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { col in
                        VStack(spacing: 0) {
                            ForEach(0..<Int(laneCount * 2), id: \.self) { row in
                                Rectangle()
                                    .fill((row + col) % 2 == 0 ? Color.white : Color.black)
                                    .frame(width: 6, height: laneHeight / 2)
                            }
                        }
                    }
                }
                .position(x: geometry.size.width - 18, y: geometry.size.height / 2)

                // Racers
                ForEach(Array(allRacers.enumerated()), id: \.element.id) { index, racer in
                    let progress = racer.isMe ?
                        (myProgress?.percentComplete ?? 0) :
                        racer.progress(toward: targetDistance)

                    RacerView(
                        racer: racer,
                        xPosition: calculateXPosition(progress: progress, width: geometry.size.width),
                        laneHeight: laneHeight,
                        laneIndex: index
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var allRacers: [RacerDisplayInfo] {
        var racers: [RacerDisplayInfo] = []

        // Add self first
        racers.append(RacerDisplayInfo(
            id: "me",
            displayName: "YOU",
            equipmentType: myEquipmentType,
            distance: myProgress?.distance ?? 0,
            isMe: true
        ))

        // Add other participants
        for participant in participants where participant.id != "current-user" {
            racers.append(RacerDisplayInfo(
                id: participant.id,
                displayName: participant.displayName,
                equipmentType: participant.equipmentType,
                distance: participant.distance,
                isMe: false
            ))
        }

        return racers
    }

    private var distanceMarkers: [Double] {
        let interval: Double
        if targetDistance <= 500 {
            interval = 100
        } else if targetDistance <= 2000 {
            interval = 250
        } else {
            interval = 500
        }

        var markers: [Double] = []
        var current = interval
        while current < targetDistance {
            markers.append(current)
            current += interval
        }
        return markers
    }

    private func calculateXPosition(progress: Double, width: CGFloat) -> CGFloat {
        let trackStart: CGFloat = 40
        let trackEnd = width - 25
        let trackLength = trackEnd - trackStart
        return trackStart + (trackLength * CGFloat(min(1.0, progress)))
    }
}

struct RacerDisplayInfo: Identifiable {
    let id: String
    let displayName: String
    let equipmentType: EquipmentType
    let distance: Double
    let isMe: Bool

    func progress(toward target: Double) -> Double {
        guard target > 0 else { return 0 }
        return distance / target
    }
}

struct RacerView: View {
    let racer: RacerDisplayInfo
    let xPosition: CGFloat
    let laneHeight: CGFloat
    let laneIndex: Int

    private var equipmentColor: Color {
        switch racer.equipmentType {
        case .rower: return .cyan
        case .bike: return .orange
        case .ski: return .purple
        }
    }

    var body: some View {
        let yPosition = (CGFloat(laneIndex) + 0.5) * laneHeight

        HStack(spacing: 6) {
            // Equipment icon in circle
            ZStack {
                Circle()
                    .fill(racer.isMe ? equipmentColor : Color.white.opacity(0.9))
                    .frame(width: 32, height: 32)

                Image(systemName: racer.equipmentType.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(racer.isMe ? .white : equipmentColor)
            }

            // Name tag
            Text(racer.isMe ? "YOU" : String(racer.displayName.prefix(5)))
                .font(.system(size: 11, weight: racer.isMe ? .bold : .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(racer.isMe ? equipmentColor : Color.gray.opacity(0.7))
                .cornerRadius(4)
        }
        .position(x: xPosition, y: yPosition)
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
            MetricBox(title: "CALORIES", value: "\(metrics.calories)")
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
        bleManager: BLEManager(),
        networkService: NetworkService.shared,
        currentUserId: "preview-user"
    )
}
