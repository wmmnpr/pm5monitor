import SwiftUI
import UIKit

struct RaceView: View {
    @ObservedObject var raceService: RaceService
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var networkService: NetworkService
    var currentUserId: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var previousMetrics: RowingMetrics?
    @State private var raceStartTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showDebugLog = false

    private var targetDistance: Int {
        networkService.currentRace?.targetDistance ?? raceService.currentRace?.targetDistance ?? 2000
    }

    private var serverParticipants: [ServerRaceParticipant] {
        networkService.currentRace?.participants ?? []
    }

    private var entryFee: String {
        networkService.currentLobby?.entryFee ?? "0"
    }

    private var formattedEntryFee: String {
        let weiString = entryFee
        guard let wei = Double(weiString) else { return "FREE" }
        if wei == 0 { return "FREE" }
        let eth = wei / 1_000_000_000_000_000_000
        if eth < 0.001 {
            return String(format: "%.6f ETH", eth)
        } else {
            return String(format: "%.4f ETH", eth)
        }
    }

    private var isRaceFinished: Bool {
        if case .finished = raceService.raceState {
            return true
        }
        return false
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Race info header - use player's race time
                    RaceInfoHeader(
                        targetDistance: targetDistance,
                        entryFee: formattedEntryFee,
                        elapsedTime: elapsedTime
                    )

                    // Race lanes - fills remaining space with safe area padding for notch
                    if !serverParticipants.isEmpty {
                        MultiRacerLaneView(
                            participants: serverParticipants,
                            currentUserId: currentUserId,
                            currentUserDistance: bleManager.currentMetrics.distance,
                            targetDistance: Double(targetDistance)
                        )
                        .padding(.leading, geometry.safeAreaInsets.leading + 16)
                        .padding(.trailing, geometry.safeAreaInsets.trailing + 16)
                        .padding(.bottom, 16)
                    } else {
                        RaceTrackView(
                            participants: raceService.participants,
                            myProgress: raceService.myProgress,
                            targetDistance: Double(targetDistance),
                            myEquipmentType: raceService.myEquipmentType
                        )
                        .padding(.leading, geometry.safeAreaInsets.leading + 16)
                        .padding(.trailing, geometry.safeAreaInsets.trailing + 16)
                        .padding(.bottom, 16)
                    }
                }

                // Countdown overlay
                if case .countdown(let seconds) = raceService.raceState {
                    CountdownOverlay(seconds: seconds)
                }

                // Finish overlay
                if case .finished(let position) = raceService.raceState {
                    RaceFinishedOverlay(
                        position: position,
                        participants: serverParticipants
                    ) {
                        raceService.unsubscribe()
                        networkService.clearRaceState()
                    }
                }

                // Debug log overlay
                if showDebugLog {
                    VStack {
                        Spacer()
                        DebugLogView(logs: bleManager.debugLog)
                    }
                }

                // Debug log toggle button
                VStack {
                    HStack {
                        Button {
                            showDebugLog.toggle()
                        } label: {
                            Image(systemName: showDebugLog ? "terminal.fill" : "terminal")
                                .font(.title2)
                                .foregroundColor(showDebugLog ? .cyan : .white.opacity(0.6))
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                        }
                        .padding(.leading, 16)
                        .padding(.top, 50)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            setLandscapeOrientation()
        }
        .onDisappear {
            stopTimer()
            restorePortraitOrientation()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                setLandscapeOrientation()
            }
        }
        .onChange(of: raceService.raceState) { newState in
            if case .racing = newState {
                startRaceTimer()
            } else if case .finished = newState {
                stopTimer()
            }
        }
        .onChange(of: bleManager.currentMetrics) { newMetrics in
            sendUpdate(metrics: newMetrics)
        }
        .supportedOrientations(.landscape)
    }

    private func startRaceTimer() {
        guard raceStartTime == nil else { return }
        raceStartTime = Date()
        elapsedTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let start = raceStartTime, !isRaceFinished {
                elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func setLandscapeOrientation() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
    }

    private func restorePortraitOrientation() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
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
            pace: myProgress?.currentPace ?? 0,
            isMe: true
        ))

        // Add other participants
        for participant in participants where participant.id != "current-user" {
            racers.append(RacerDisplayInfo(
                id: participant.id,
                displayName: participant.displayName,
                equipmentType: participant.equipmentType,
                distance: participant.distance,
                pace: participant.pace,
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
    let pace: Double
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

    private var formattedPace: String {
        guard racer.pace > 0 else { return "-:--" }
        let minutes = Int(racer.pace) / 60
        let seconds = Int(racer.pace) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedDistance: String {
        return "\(Int(racer.distance))m"
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

            // Name and metrics
            VStack(alignment: .leading, spacing: 1) {
                Text(racer.isMe ? "YOU" : String(racer.displayName.prefix(6)).uppercased())
                    .font(.system(size: 10, weight: racer.isMe ? .bold : .medium))
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Text(formattedDistance)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.yellow)

                    Text(formattedPace)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(racer.isMe ? equipmentColor.opacity(0.9) : Color.black.opacity(0.7))
            .cornerRadius(4)
        }
        .position(x: xPosition, y: yPosition)
        .animation(.easeInOut(duration: 0.3), value: xPosition)
    }
}

// MARK: - Race Info Header

struct RaceInfoHeader: View {
    let targetDistance: Int
    let entryFee: String
    let elapsedTime: TimeInterval

    private var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let tenths = Int((elapsedTime.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    private var distanceDisplay: String {
        RaceDistance.fromMeters(targetDistance).displayName
    }

    var body: some View {
        HStack(spacing: 0) {
            // Distance
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.cyan)
                Text(distanceDisplay)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)

            // Elapsed Time (center, larger)
            VStack(spacing: 2) {
                Text("TIME")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
                Text(formattedTime)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
            }
            .frame(maxWidth: .infinity)

            // Entry Fee
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.green)
                Text(entryFee)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
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
    let participants: [ServerRaceParticipant]
    let onDismiss: () -> Void

    private var sortedParticipants: [ServerRaceParticipant] {
        participants.sorted { p1, p2 in
            // Sort by position (finished first), then by distance (for unfinished)
            if let pos1 = p1.position, let pos2 = p2.position {
                return pos1 < pos2
            } else if p1.position != nil {
                return true
            } else if p2.position != nil {
                return false
            } else {
                return p1.distance > p2.distance
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header with user's position
                HStack(spacing: 16) {
                    Image(systemName: medalIcon)
                        .font(.system(size: 40))
                        .foregroundColor(positionColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(positionText)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(positionColor)
                        Text(positionLabel)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    if position <= 3 {
                        Text("Prize pool distributed!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                // Results header
                Text("RACE RESULTS")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                // Results list
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(sortedParticipants) { participant in
                            ParticipantResultRow(participant: participant)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Return home button
                Button {
                    onDismiss()
                } label: {
                    Text("Return Home")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .cornerRadius(25)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
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

// MARK: - Participant Result Row

struct ParticipantResultRow: View {
    let participant: ServerRaceParticipant

    var body: some View {
        HStack(spacing: 12) {
            // Position
            ZStack {
                Circle()
                    .fill(positionColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Text(positionText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(positionColor)
            }

            // Name and bot indicator
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(participant.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    if participant.isBot == true {
                        Text("BOT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                // Pace
                Text(formattedPace)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            // Finish time
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedFinishTime)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(participant.isFinished ? .white : .white.opacity(0.5))
                // Watts
                Text("\(participant.watts)W")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var positionText: String {
        if let pos = participant.position {
            return "\(pos)"
        }
        return "-"
    }

    private var positionColor: Color {
        switch participant.position {
        case 1: return .yellow
        case 2: return Color(.systemGray)
        case 3: return .orange
        default: return .white.opacity(0.6)
        }
    }

    private var formattedFinishTime: String {
        guard let finishTimeMs = participant.finishTime else {
            return "--:--.-"
        }
        let totalSeconds = finishTimeMs / 1000.0
        let minutes = Int(totalSeconds) / 60
        let seconds = totalSeconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    private var formattedPace: String {
        let paceSeconds = participant.pace
        if paceSeconds <= 0 { return "-:--/500m" }
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return String(format: "%d:%02d/500m", minutes, seconds)
    }
}

// MARK: - Orientation Lock Modifier

struct SupportedOrientationsModifier: ViewModifier {
    let orientations: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear {
                OrientationManager.shared.lock(orientations)
            }
            .onDisappear {
                OrientationManager.shared.unlock()
            }
    }
}

extension View {
    func supportedOrientations(_ orientations: UIInterfaceOrientationMask) -> some View {
        modifier(SupportedOrientationsModifier(orientations: orientations))
    }
}

class OrientationManager {
    static let shared = OrientationManager()
    var lockedOrientation: UIInterfaceOrientationMask?

    func lock(_ orientation: UIInterfaceOrientationMask) {
        lockedOrientation = orientation
        // Force update
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
    }

    func unlock() {
        lockedOrientation = nil
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
