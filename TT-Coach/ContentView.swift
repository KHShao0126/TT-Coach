import SwiftUI
import AVFoundation
import AVKit
import UIKit
import Vision

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var videoLibrary = VideoLibraryManager()

    @State private var isCoachingMode = false
    @State private var permissionMessage: String?
    @State private var isVideoLibraryPresented = false
    @State private var isClosingSession = false
    @State private var showSaveRecordingDialog = false
    @State private var isWaitingForLandscapeRecording = false
    @State private var calibrationPoints: [CGPoint] = []

    var body: some View {
        ZStack {
            if isCoachingMode {
                coachingView
            } else {
                homeView
            }

            if isClosingSession {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                ProgressView("處理錄影中...")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .foregroundStyle(.white)
            }
        }
        .alert("無法開啟相機", isPresented: Binding(
            get: { permissionMessage != nil },
            set: { isPresented in
                if !isPresented {
                    permissionMessage = nil
                }
            }
        )) {
            Button("確定", role: .cancel) { }
        } message: {
            Text(permissionMessage ?? "")
        }
        .confirmationDialog("是否儲存本次錄影？", isPresented: $showSaveRecordingDialog, titleVisibility: .visible) {
            Button("儲存") {
                closeCoachingMode(saveRecording: true)
            }

            Button("不儲存", role: .destructive) {
                closeCoachingMode(saveRecording: false)
            }

            Button("取消", role: .cancel) { }
        } message: {
            Text("關閉教練模式前，選擇是否保留剛剛錄下的影片。")
        }
        .sheet(isPresented: $isVideoLibraryPresented) {
            SavedVideosView(videoLibrary: videoLibrary)
        }
    }

    private var homeView: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.85), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay {
            VStack(spacing: 24) {
                Spacer()

                Text("TT-Coach")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)

                Text("Table Tennis Doubles Audio Coach")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.85))

                Spacer()

                Button {
                    resetCalibration()
                    cameraManager.requestPermissionAndStart { started in
                        if started {
                            isCoachingMode = true
                        } else {
                            permissionMessage = "請先允許相機與麥克風權限，才能進入 AI 教練模式。"
                        }
                    }
                } label: {
                    Text("開始")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 32)

                Button {
                    videoLibrary.refreshVideos()
                    isVideoLibraryPresented = true
                } label: {
                    Label("已儲存影片", systemImage: "film.stack")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 32)

                Text("按下開始後會開啟相機、進入 AI 教練模式；若手機直放，會提示先橫放再開始錄影")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.bottom, 40)
            }
        }
    }

    private var coachingView: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let bottomPadding = max(geometry.safeAreaInsets.bottom, 12)

            ZStack {
                Color.black
                    .ignoresSafeArea()

                CameraPreview(
                    session: cameraManager.session,
                    trackedPlayers: cameraManager.trackedPlayers,
                    captureDevice: cameraManager.captureDevice,
                    calibrationPoints: calibrationPoints,
                    completedCalibration: completedCalibration,
                    isCalibrationEnabled: isLandscape && !isCalibrationComplete && !cameraManager.isRecordingActive,
                    onCalibrationTap: handleCalibrationTap
                )
                .ignoresSafeArea()

                VStack(spacing: isLandscape ? 8 : 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 8) {
                            recordingStatusBadge
                            rallyStatusBadge
                        }

                        Spacer()

                        HStack(spacing: 12) {
                            if !cameraManager.isRecordingActive {
                                Button {
                                    resetCalibration()
                                } label: {
                                    Label("重設標定", systemImage: "arrow.counterclockwise")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.black.opacity(0.65))
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }

                            Button {
                                showSaveRecordingDialog = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                                    .shadow(radius: 4)
                            }
                            .disabled(isClosingSession)
                        }
                    }
                    .padding(.top, geometry.safeAreaInsets.top + 12)
                    .padding(.horizontal, 16)

                    HStack {
                        TrackingDebugPanel(
                            debugInfo: cameraManager.trackingDebugInfo,
                            rallyState: cameraManager.rallyState,
                            spatialStatus: cameraManager.playerAreaSpatialStatus,
                            calibrationStatus: calibrationStatusLabel
                        )
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 0)
                }

                if isWaitingForLandscapeRecording {
                    VStack {
                        Spacer()

                        VStack(spacing: 10) {
                            Text("請把手機水平放置")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)

                            Text("偵測到目前是直式，轉成橫式後會自動開始錄影。")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .background(Color.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 22))

                        Spacer()
                    }
                    .padding(24)
                }

                if isLandscape && !isCalibrationComplete {
                    VStack {
                        Spacer()

                        calibrationInstructionCard
                            .padding(.horizontal, 24)
                            .padding(.bottom, max(bottomPadding + 16, 32))
                    }
                }
            }
            .onAppear {
                syncRecordingState(forLandscape: isLandscape)
            }
            .onChange(of: isLandscape, initial: false) { _, newValue in
                syncRecordingState(forLandscape: newValue)
            }
            .onChange(of: calibrationPoints.count, initial: false) { _, _ in
                cameraManager.updatePlayerAreaCalibration(completedCalibration)
                syncRecordingState(forLandscape: isLandscape)
            }
        }
    }

    private var recordingStatusBadge: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(recordingBadgeColor)
                .frame(width: 10, height: 10)

            Text(recordingBadgeLabel)
                .font(.headline)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.65))
        .foregroundColor(.white)
        .clipShape(Capsule())
    }

    private var rallyStatusBadge: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(cameraManager.rallyState.tintColor)
                .frame(width: 10, height: 10)

            Text(cameraManager.rallyState.rawValue)
                .font(.headline)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.65))
        .foregroundColor(.white)
        .clipShape(Capsule())
    }

    private var calibrationInstructionCard: some View {
        VStack(spacing: 10) {
            Text(calibrationHeadline)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(calibrationDetail)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Color.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 22))
    }

    private var completedCalibration: PlayerAreaCalibration? {
        PlayerAreaCalibration(points: calibrationPoints)
    }

    private var isCalibrationComplete: Bool {
        completedCalibration != nil
    }

    private var calibrationStatusLabel: String {
        isCalibrationComplete ? "已標定" : "第 \(calibrationPoints.count)/4 點"
    }

    private var recordingBadgeLabel: String {
        if cameraManager.isRecordingActive {
            return "REC"
        }
        if isWaitingForLandscapeRecording {
            return "等待橫放"
        }
        if !isCalibrationComplete {
            return "等待標定"
        }
        return "待命"
    }

    private var recordingBadgeColor: Color {
        if cameraManager.isRecordingActive {
            return .red
        }
        return .orange
    }

    private var calibrationHeadline: String {
        if let nextCorner = CalibrationCorner(rawValue: calibrationPoints.count) {
            return "請點選跑動區域的\(nextCorner.title)"
        }
        return "跑動區域標定完成"
    }

    private var calibrationDetail: String {
        if isCalibrationComplete {
            return "已建立 normalized 跑動區域座標，可開始錄影。"
        }
        return "依序點選左上、右上、右下、左下四個角，系統會用這個區域估算球員左右、前後與站位漏洞。"
    }

    private func syncRecordingState(forLandscape isLandscape: Bool) {
        guard isCoachingMode else { return }

        if cameraManager.isRecordingActive {
            isWaitingForLandscapeRecording = false
            return
        }

        if !isLandscape {
            isWaitingForLandscapeRecording = true
            return
        }

        isWaitingForLandscapeRecording = false

        guard isCalibrationComplete else {
            cameraManager.rallyEnded()
            return
        }

        if isLandscape {
            cameraManager.startRecording()
        }
    }

    private func handleCalibrationTap(_ capturePoint: CGPoint) {
        guard !cameraManager.isRecordingActive else { return }
        guard calibrationPoints.count < 4 else { return }

        let clampedPoint = CGPoint(
            x: min(max(capturePoint.x, 0), 1),
            y: min(max(capturePoint.y, 0), 1)
        )
        calibrationPoints.append(clampedPoint)
    }

    private func resetCalibration() {
        calibrationPoints = []
        cameraManager.updatePlayerAreaCalibration(nil)
    }

    private func closeCoachingMode(saveRecording: Bool) {
        isClosingSession = true
        isWaitingForLandscapeRecording = false

        cameraManager.stopSession(saveRecording: saveRecording) { temporaryURL in
            if let temporaryURL, let savedVideo = videoLibrary.saveVideo(from: temporaryURL) {
                print("Saved video at \(savedVideo.url)")
            }

            isClosingSession = false
            isCoachingMode = false
        }
    }

}

struct TrackingDebugPanel: View {
    let debugInfo: TrackingDebugInfo
    let rallyState: RallyState
    let spatialStatus: PlayerAreaSpatialStatus
    let calibrationStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tracking Debug")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Text("rally: \(rallyState.rawValue)")
            Text("calibration: \(calibrationStatus)")
            Text("spacing: \(spatialStatus.spacingSummary)")
            Text("hole: \(spatialStatus.holeSummary)")
            Text("source: \(debugInfo.source)")
            Text("rectangles: \(debugInfo.rectangleCandidates)  bodyPose: \(debugInfo.bodyPoseCandidates)")
            Text("selected: \(debugInfo.selectedCandidates)  tracked: \(debugInfo.trackedPlayers)")
            Text("missed: \(debugInfo.missedFrames)")

            ForEach(debugInfo.trackedSummaries, id: \.self) { summary in
                Text(summary)
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white.opacity(0.94))
        .padding(12)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct TrackedPlayerBox: Identifiable, Equatable, Hashable {
    let id: String
    let label: String
    let boundingBox: CGRect
    let footPoint: CGPoint?
    let playerAreaPoint: CGPoint?
    let lateralPosition: String?
    let depthPosition: String?
    let isCurrentHitter: Bool

    init(
        id: String,
        label: String,
        boundingBox: CGRect,
        footPoint: CGPoint? = nil,
        playerAreaPoint: CGPoint? = nil,
        lateralPosition: String? = nil,
        depthPosition: String? = nil,
        isCurrentHitter: Bool = false
    ) {
        self.id = id
        self.label = label
        self.boundingBox = boundingBox
        self.footPoint = footPoint
        self.playerAreaPoint = playerAreaPoint
        self.lateralPosition = lateralPosition
        self.depthPosition = depthPosition
        self.isCurrentHitter = isCurrentHitter
    }
}

struct TrackingDebugInfo {
    var source = "none"
    var rectangleCandidates = 0
    var bodyPoseCandidates = 0
    var selectedCandidates = 0
    var trackedPlayers = 0
    var missedFrames = 0
    var trackedSummaries: [String] = []
}

enum RallyState: String {
    case start = "Rally start"
    case end = "Rally end"

    var tintColor: Color {
        switch self {
        case .start:
            return .green
        case .end:
            return .orange
        }
    }
}

private enum RallyFeedback: String, CaseIterable {
    case p1RecoverEarlier = "Player 1, recover earlier."
    case p2RecoverEarlier = "Player 2, recover earlier."
    case p1MoveOutAfterHitting = "Player 1, move out after hitting."
    case p2MoveOutAfterHitting = "Player 2, move out after hitting."
}

private final class RallyFeedbackSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    @discardableResult
    func speak(_ feedback: [RallyFeedback]) -> CFTimeInterval {
        guard !feedback.isEmpty else { return 0 }

        let estimatedDuration = (Double(feedback.count) * 2.1) + 0.4

        DispatchQueue.main.async {
            self.activateAudioSessionIfPossible()

            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }

            for item in feedback {
                let utterance = AVSpeechUtterance(string: item.rawValue)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = 0.48
                utterance.pitchMultiplier = 0.95
                utterance.postUtteranceDelay = 0.12
                self.synthesizer.speak(utterance)
            }
        }

        return estimatedDuration
    }

    func stop() {
        DispatchQueue.main.async {
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    private func activateAudioSessionIfPossible() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
            )
            try audioSession.setActive(true)
        } catch {
            print("Failed to activate feedback audio session: \(error)")
        }
    }
}

enum CalibrationCorner: Int, CaseIterable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    var title: String {
        switch self {
        case .topLeft:
            return "左上角"
        case .topRight:
            return "右上角"
        case .bottomRight:
            return "右下角"
        case .bottomLeft:
            return "左下角"
        }
    }
}

struct PlayerAreaSpatialStatus {
    var isCalibrated = false
    var spacingSummary = "未標定"
    var holeSummary = "未標定"

    static let uncalibrated = PlayerAreaSpatialStatus()
}

struct PlayerAreaCalibration: Equatable, Hashable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
    private let homographyCoefficients: [Double]

    init?(points: [CGPoint]) {
        guard points.count == 4 else { return nil }
        self.init(topLeft: points[0], topRight: points[1], bottomRight: points[2], bottomLeft: points[3])
    }

    init?(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        let source = [topLeft, topRight, bottomRight, bottomLeft]
        let destination = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1)
        ]

        guard let coefficients = Self.solveHomography(source: source, destination: destination) else { return nil }

        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.homographyCoefficients = coefficients
    }

    var orderedPoints: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    func normalizedPoint(forCapturePoint point: CGPoint) -> CGPoint? {
        guard homographyCoefficients.count == 8 else { return nil }

        let x = Double(point.x)
        let y = Double(point.y)
        let denominator = (homographyCoefficients[6] * x) + (homographyCoefficients[7] * y) + 1
        guard abs(denominator) > 0.000001 else { return nil }

        let mappedX = ((homographyCoefficients[0] * x) + (homographyCoefficients[1] * y) + homographyCoefficients[2]) / denominator
        let mappedY = ((homographyCoefficients[3] * x) + (homographyCoefficients[4] * y) + homographyCoefficients[5]) / denominator

        guard mappedX.isFinite, mappedY.isFinite else { return nil }
        return CGPoint(x: mappedX, y: mappedY)
    }

    private static func solveHomography(source: [CGPoint], destination: [CGPoint]) -> [Double]? {
        guard source.count == 4, destination.count == 4 else { return nil }

        var matrix = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)

        for index in 0..<4 {
            let sourcePoint = source[index]
            let destinationPoint = destination[index]

            let x = Double(sourcePoint.x)
            let y = Double(sourcePoint.y)
            let u = Double(destinationPoint.x)
            let v = Double(destinationPoint.y)

            matrix[index * 2] = [x, y, 1, 0, 0, 0, -(u * x), -(u * y), u]
            matrix[(index * 2) + 1] = [0, 0, 0, x, y, 1, -(v * x), -(v * y), v]
        }

        return solveLinearSystem(matrix)
    }

    private static func solveLinearSystem(_ augmentedMatrix: [[Double]]) -> [Double]? {
        var matrix = augmentedMatrix
        let dimension = 8

        for pivotIndex in 0..<dimension {
            var bestRow = pivotIndex
            var bestValue = abs(matrix[pivotIndex][pivotIndex])

            for row in (pivotIndex + 1)..<dimension {
                let candidate = abs(matrix[row][pivotIndex])
                if candidate > bestValue {
                    bestValue = candidate
                    bestRow = row
                }
            }

            guard bestValue > 0.0000001 else { return nil }

            if bestRow != pivotIndex {
                matrix.swapAt(bestRow, pivotIndex)
            }

            let pivot = matrix[pivotIndex][pivotIndex]
            for column in pivotIndex...dimension {
                matrix[pivotIndex][column] /= pivot
            }

            for row in 0..<dimension where row != pivotIndex {
                let factor = matrix[row][pivotIndex]
                guard factor != 0 else { continue }

                for column in pivotIndex...dimension {
                    matrix[row][column] -= factor * matrix[pivotIndex][column]
                }
            }
        }

        return (0..<dimension).map { matrix[$0][dimension] }
    }
}

struct SavedVideo: Identifiable, Hashable {
    let url: URL
    let createdAt: Date

    var id: URL { url }

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }
}

struct ReviewSession {
    let video: SavedVideo
    let duration: Double
    let trackFrames: [PlayerTrackFrame]
    let movementEvents: [MovementEvent]
    let suggestions: [ReviewSuggestion]
}

struct PlayerTrackFrame: Identifiable, Hashable {
    let id = UUID()
    let time: Double
    let players: [TrackedPlayerBox]
}

struct MovementEvent: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case closeSpacing
        case wideSpacing
        case crossover
        case deepRetreat
    }

    let id = UUID()
    let kind: Kind
    let startTime: Double
    let endTime: Double
    let playerLabel: String?
    let confidence: Double
    let title: String
    let detail: String

    var time: Double {
        (startTime + endTime) / 2
    }
}

struct ReviewSuggestion: Identifiable, Hashable {
    let id = UUID()
    let eventKind: MovementEvent.Kind
    let timeRange: ClosedRange<Double>
    let playerLabel: String?
    let confidence: Double
    let title: String
    let text: String
}

enum VideoReviewAnalyzer {
    private enum ReviewConstants {
        static let closeSpacingThreshold: CGFloat = 0.14
        static let wideSpacingThreshold: CGFloat = 0.4
        static let retreatDropThreshold: CGFloat = 0.12
        static let minimumEventDuration: Double = 0.35
        static let samplingStride = 2
    }

    static func analyze(video: SavedVideo) async -> ReviewSession {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: buildReviewSession(for: video))
            }
        }
    }

    private static func buildReviewSession(for video: SavedVideo) -> ReviewSession {
        let asset = AVURLAsset(url: video.url)
        let duration = normalizedDuration(from: asset.duration)

        guard
            let track = asset.tracks(withMediaType: .video).first,
            let reader = try? AVAssetReader(asset: asset)
        else {
            return ReviewSession(video: video, duration: duration, trackFrames: [], movementEvents: [], suggestions: [])
        }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            return ReviewSession(video: video, duration: duration, trackFrames: [], movementEvents: [], suggestions: [])
        }

        reader.add(output)
        guard reader.startReading() else {
            return ReviewSession(video: video, duration: duration, trackFrames: [], movementEvents: [], suggestions: [])
        }

        var trackFrames: [PlayerTrackFrame] = []
        var previousPlayers: [TrackedPlayerBox] = []
        var sampleIndex = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            autoreleasepool {
                sampleIndex += 1
                guard sampleIndex.isMultiple(of: ReviewConstants.samplingStride) else { return }

                guard
                    let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                else { return }

                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                guard timestamp.isFinite else { return }

                let players = detectPlayers(in: pixelBuffer, previousPlayers: previousPlayers)
                if !players.isEmpty {
                    previousPlayers = players
                }
                trackFrames.append(PlayerTrackFrame(time: timestamp, players: players))
            }
        }

        let movementEvents = buildMovementEvents(from: trackFrames)
        let suggestions = buildSuggestions(from: movementEvents)
        return ReviewSession(
            video: video,
            duration: duration,
            trackFrames: trackFrames,
            movementEvents: movementEvents,
            suggestions: suggestions
        )
    }

    private static func detectPlayers(
        in pixelBuffer: CVPixelBuffer,
        previousPlayers: [TrackedPlayerBox]
    ) -> [TrackedPlayerBox] {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try handler.perform([request])

            let observations = Array((request.results ?? [])
                .sorted { $0.boundingBox.midX < $1.boundingBox.midX }
                .prefix(2))

            let detectedPlayers = observations.enumerated().map { index, observation in
                let label = index == 0 ? "Player1" : "Player2"
                return TrackedPlayerBox(id: label, label: label, boundingBox: observation.boundingBox)
            }

            guard previousPlayers.count == 2, detectedPlayers.count == 2 else {
                return Array(detectedPlayers)
            }

            let firstOrderScore = matchingScore(previousPlayers: previousPlayers, candidates: detectedPlayers)
            let swappedCandidates = [
                TrackedPlayerBox(id: "Player1", label: "Player1", boundingBox: detectedPlayers[1].boundingBox),
                TrackedPlayerBox(id: "Player2", label: "Player2", boundingBox: detectedPlayers[0].boundingBox)
            ]
            let swappedOrderScore = matchingScore(previousPlayers: previousPlayers, candidates: swappedCandidates)

            return firstOrderScore >= swappedOrderScore ? Array(detectedPlayers) : swappedCandidates
        } catch {
            print("Failed to analyze review frame: \(error)")
            return []
        }
    }

    private static func buildMovementEvents(from frames: [PlayerTrackFrame]) -> [MovementEvent] {
        let pairedFrames = frames.compactMap { frame -> (PlayerTrackFrame, TrackedPlayerBox, TrackedPlayerBox)? in
            guard
                let player1 = frame.players.first(where: { $0.label == "Player1" }),
                let player2 = frame.players.first(where: { $0.label == "Player2" })
            else {
                return nil
            }

            return (frame, player1, player2)
        }

        guard !pairedFrames.isEmpty else { return [] }

        let baselinePlayer1Y = median(of: pairedFrames.map { $0.1.boundingBox.midY })
        let baselinePlayer2Y = median(of: pairedFrames.map { $0.2.boundingBox.midY })

        var events: [MovementEvent] = []
        events += collectIntervalEvents(from: pairedFrames) { frame, player1, player2 in
            let spacing = abs(player1.boundingBox.midX - player2.boundingBox.midX)
            guard spacing < ReviewConstants.closeSpacingThreshold else { return nil }

            let confidence = 1 - min(Double(spacing / ReviewConstants.closeSpacingThreshold), 1)
            return EventCandidate(
                kind: .closeSpacing,
                playerLabel: nil,
                confidence: confidence,
                title: "站位過近",
                detail: "兩位球員在 \(timeLabel(frame.time)) 左右站位太近，容易互相卡位。"
            )
        }

        events += collectIntervalEvents(from: pairedFrames) { frame, player1, player2 in
            let spacing = abs(player1.boundingBox.midX - player2.boundingBox.midX)
            guard spacing > ReviewConstants.wideSpacingThreshold else { return nil }

            let confidence = min(Double((spacing - ReviewConstants.wideSpacingThreshold) / 0.18), 1)
            return EventCandidate(
                kind: .wideSpacing,
                playerLabel: nil,
                confidence: confidence,
                title: "站位過開",
                detail: "兩位球員在 \(timeLabel(frame.time)) 左右拉得太開，中路容易出現空檔。"
            )
        }

        events += collectIntervalEvents(from: pairedFrames) { frame, player1, player2 in
            guard player1.boundingBox.midX > player2.boundingBox.midX else { return nil }

            let overlap = Double(player1.boundingBox.midX - player2.boundingBox.midX)
            return EventCandidate(
                kind: .crossover,
                playerLabel: nil,
                confidence: min(overlap / 0.12, 1),
                title: "左右交叉",
                detail: "在 \(timeLabel(frame.time)) 前後，Player1 與 Player2 的左右站位發生交叉。"
            )
        }

        events += collectIntervalEvents(from: pairedFrames) { frame, player1, _ in
            let retreatAmount = baselinePlayer1Y - player1.boundingBox.midY
            guard retreatAmount > ReviewConstants.retreatDropThreshold else { return nil }

            return EventCandidate(
                kind: .deepRetreat,
                playerLabel: "Player1",
                confidence: min(Double(retreatAmount / 0.22), 1),
                title: "Player1 退太深",
                detail: "Player1 在 \(timeLabel(frame.time)) 附近明顯往後退，可能影響下一板補位。"
            )
        }

        events += collectIntervalEvents(from: pairedFrames) { frame, _, player2 in
            let retreatAmount = baselinePlayer2Y - player2.boundingBox.midY
            guard retreatAmount > ReviewConstants.retreatDropThreshold else { return nil }

            return EventCandidate(
                kind: .deepRetreat,
                playerLabel: "Player2",
                confidence: min(Double(retreatAmount / 0.22), 1),
                title: "Player2 退太深",
                detail: "Player2 在 \(timeLabel(frame.time)) 附近明顯往後退，可能影響下一板補位。"
            )
        }

        return events.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.confidence > rhs.confidence
            }
            return lhs.startTime < rhs.startTime
        }
    }

    private static func normalizedDuration(from time: CMTime) -> Double {
        let seconds = time.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    private static func buildSuggestions(from events: [MovementEvent]) -> [ReviewSuggestion] {
        events.map { event in
            ReviewSuggestion(
                eventKind: event.kind,
                timeRange: event.startTime...event.endTime,
                playerLabel: event.playerLabel,
                confidence: event.confidence,
                title: suggestionTitle(for: event),
                text: suggestionText(for: event)
            )
        }
    }

    private static func suggestionTitle(for event: MovementEvent) -> String {
        switch event.kind {
        case .closeSpacing:
            return "拉開站位"
        case .wideSpacing:
            return "補回中路"
        case .crossover:
            return "重新分工左右區"
        case .deepRetreat:
            return "\(event.playerLabel ?? "球員") 先回到準備位"
        }
    }

    private static func suggestionText(for event: MovementEvent) -> String {
        switch event.kind {
        case .closeSpacing:
            return "AI 建議在 \(timeLabel(event.startTime)) 到 \(timeLabel(event.endTime)) 之間，兩位球員各自再拉開半步，避免同時擠進同一條線，讓下一板補位更順。"
        case .wideSpacing:
            return "AI 建議在 \(timeLabel(event.startTime)) 附近優先補回中路，不要讓左右距離持續過大，否則中間來球會需要額外跨步補救。"
        case .crossover:
            return "AI 建議在 \(timeLabel(event.startTime)) 前後盡快重新建立左右分工。交叉後若沒有立刻換位完成，下一板容易出現判斷遲疑。"
        case .deepRetreat:
            let player = event.playerLabel ?? "該球員"
            return "AI 建議 \(player) 在 \(timeLabel(event.startTime)) 到 \(timeLabel(event.endTime)) 之間不要退太深，擊球後要更快回到中性準備位，保留下一板往前補位的空間。"
        }
    }

    private static func matchingScore(previousPlayers: [TrackedPlayerBox], candidates: [TrackedPlayerBox]) -> CGFloat {
        zip(previousPlayers, candidates).reduce(0) { partialResult, pair in
            let centerDistance = hypot(
                pair.0.boundingBox.midX - pair.1.boundingBox.midX,
                pair.0.boundingBox.midY - pair.1.boundingBox.midY
            )
            return partialResult + (1 - min(centerDistance, 1))
        }
    }

    private struct EventCandidate {
        let kind: MovementEvent.Kind
        let playerLabel: String?
        let confidence: Double
        let title: String
        let detail: String
    }

    private static func collectIntervalEvents(
        from frames: [(PlayerTrackFrame, TrackedPlayerBox, TrackedPlayerBox)],
        detector: (PlayerTrackFrame, TrackedPlayerBox, TrackedPlayerBox) -> EventCandidate?
    ) -> [MovementEvent] {
        var events: [MovementEvent] = []
        var activeStart: Double?
        var activeEnd: Double?
        var activeCandidate: EventCandidate?
        var accumulatedConfidence = 0.0
        var confidenceSamples = 0

        func flushActiveEvent() {
            guard
                let startTime = activeStart,
                let endTime = activeEnd,
                let candidate = activeCandidate,
                endTime - startTime >= ReviewConstants.minimumEventDuration
            else {
                activeStart = nil
                activeEnd = nil
                activeCandidate = nil
                accumulatedConfidence = 0
                confidenceSamples = 0
                return
            }

            let averagedConfidence = confidenceSamples > 0 ? accumulatedConfidence / Double(confidenceSamples) : candidate.confidence
            events.append(
                MovementEvent(
                    kind: candidate.kind,
                    startTime: startTime,
                    endTime: endTime,
                    playerLabel: candidate.playerLabel,
                    confidence: averagedConfidence,
                    title: candidate.title,
                    detail: candidate.detail
                )
            )

            activeStart = nil
            activeEnd = nil
            activeCandidate = nil
            accumulatedConfidence = 0
            confidenceSamples = 0
        }

        for (frame, player1, player2) in frames {
            if let candidate = detector(frame, player1, player2) {
                if activeCandidate?.kind == candidate.kind, activeCandidate?.playerLabel == candidate.playerLabel {
                    activeEnd = frame.time
                    activeCandidate = candidate
                    accumulatedConfidence += candidate.confidence
                    confidenceSamples += 1
                } else {
                    flushActiveEvent()
                    activeStart = frame.time
                    activeEnd = frame.time
                    activeCandidate = candidate
                    accumulatedConfidence = candidate.confidence
                    confidenceSamples = 1
                }
            } else {
                flushActiveEvent()
            }
        }

        flushActiveEvent()
        return events
    }

    private static func median(of values: [CGFloat]) -> CGFloat {
        let sortedValues = values.sorted()
        guard !sortedValues.isEmpty else { return 0 }
        let middleIndex = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2
        } else {
            return sortedValues[middleIndex]
        }
    }

    private static func timeLabel(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

final class VideoLibraryManager: ObservableObject {
    @Published private(set) var videos: [SavedVideo] = []

    private static let directoryName = "SavedVideos"

    init() {
        refreshVideos()
    }

    func refreshVideos() {
        let fileManager = FileManager.default
        let directory = Self.storageDirectoryURL()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )

            videos = urls
                .filter { ["mov", "mp4"].contains($0.pathExtension.lowercased()) }
                .map { url in
                    let values = try? url.resourceValues(forKeys: [.creationDateKey])
                    return SavedVideo(url: url, createdAt: values?.creationDate ?? .distantPast)
                }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            print("Failed to load saved videos: \(error)")
            videos = []
        }
    }

    @discardableResult
    func saveVideo(from temporaryURL: URL) -> SavedVideo? {
        let fileManager = FileManager.default
        let directory = Self.storageDirectoryURL()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"

            let finalURL = directory
                .appendingPathComponent("TTCoach-\(formatter.string(from: Date()))")
                .appendingPathExtension("mov")

            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }

            try fileManager.moveItem(at: temporaryURL, to: finalURL)

            let savedVideo = SavedVideo(url: finalURL, createdAt: Date())
            refreshVideos()
            return savedVideo
        } catch {
            print("Failed to save video: \(error)")
            try? fileManager.removeItem(at: temporaryURL)
            return nil
        }
    }

    func deleteVideos(at offsets: IndexSet) {
        let fileManager = FileManager.default

        for index in offsets {
            let video = videos[index]
            try? fileManager.removeItem(at: video.url)
        }

        refreshVideos()
    }

    func deleteVideo(_ video: SavedVideo) {
        try? FileManager.default.removeItem(at: video.url)
        refreshVideos()
    }

    @discardableResult
    func renameVideo(_ video: SavedVideo, to newName: String) -> Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let destinationURL = video.url.deletingLastPathComponent()
            .appendingPathComponent(trimmedName)
            .appendingPathExtension(video.url.pathExtension)

        guard destinationURL != video.url else { return true }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return false }

        do {
            try FileManager.default.moveItem(at: video.url, to: destinationURL)
            refreshVideos()
            return true
        } catch {
            print("Failed to rename video: \(error)")
            return false
        }
    }

    private static func storageDirectoryURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }
}

struct SavedVideosView: View {
    @ObservedObject var videoLibrary: VideoLibraryManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVideo: SavedVideo?
    @State private var reviewingVideo: SavedVideo?
    @State private var renamingVideo: SavedVideo?
    @State private var draftVideoName = ""
    @State private var renameErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if videoLibrary.videos.isEmpty {
                    ContentUnavailableView(
                        "還沒有已儲存影片",
                        systemImage: "video.slash",
                        description: Text("先開始一次錄影，關閉時選擇儲存，就會出現在這裡。")
                    )
                } else {
                    List {
                        ForEach(videoLibrary.videos) { video in
                            Button {
                                selectedVideo = video
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "video.fill")
                                        .foregroundStyle(.blue)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(video.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        Text(video.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .contextMenu {
                                Button {
                                    reviewingVideo = video
                                } label: {
                                    Label("Review", systemImage: "text.magnifyingglass")
                                }

                                Button {
                                    renamingVideo = video
                                    draftVideoName = video.title
                                } label: {
                                    Label("重新命名", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    videoLibrary.deleteVideo(video)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: videoLibrary.deleteVideos)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("已儲存影片")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        videoLibrary.refreshVideos()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $selectedVideo) { video in
                VideoPlayerScreen(video: video)
            }
            .sheet(item: $reviewingVideo) { video in
                VideoReviewScreen(video: video)
            }
            .alert("重新命名影片", isPresented: Binding(
                get: { renamingVideo != nil },
                set: { isPresented in
                    if !isPresented {
                        renamingVideo = nil
                        draftVideoName = ""
                    }
                }
            )) {
                TextField("影片名稱", text: $draftVideoName)

                Button("取消", role: .cancel) { }

                Button("儲存") {
                    guard let renamingVideo else { return }

                    let didRename = videoLibrary.renameVideo(renamingVideo, to: draftVideoName)
                    if !didRename {
                        renameErrorMessage = "重新命名失敗。請確認名稱不是空白，且沒有和其他影片重複。"
                    }

                    self.renamingVideo = nil
                    draftVideoName = ""
                }
            } message: {
                Text("輸入新的影片名稱")
            }
            .alert("無法重新命名", isPresented: Binding(
                get: { renameErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        renameErrorMessage = nil
                    }
                }
            )) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(renameErrorMessage ?? "")
            }
        }
    }
}

struct VideoPlayerScreen: View {
    let video: SavedVideo
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var presentationInfo = VideoPresentationInfo()
    @State private var isPlaying = false
    @State private var controlsVisible = true
    @State private var playbackProgress: Double = 0
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var controlsHideWorkItem: DispatchWorkItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                InlineVideoPlayer(player: player, videoGravity: .resizeAspectFill)
                    .ignoresSafeArea()
                    .rotationEffect(.degrees(presentationInfo.rotationDegrees))

                if controlsVisible {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()

                    VStack {
                        HStack {
                            Spacer()

                            Button("完成") {
                                dismiss()
                            }
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.7))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        Spacer()

                        playbackActionButton

                        Spacer()

                        playbackControls
                    }
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleControlsVisibility()
            }
            .onAppear {
                presentationInfo = Self.loadVideoPresentationInfo(for: video.url)
                let item = AVPlayerItem(url: video.url)
                player.replaceCurrentItem(with: item)
                updateDuration()
                addTimeObserver()
                player.play()
                isPlaying = true
                scheduleControlsAutoHide()
            }
            .onDisappear {
                controlsHideWorkItem?.cancel()
                removeTimeObserver()
                player.pause()
                isPlaying = false
                player.replaceCurrentItem(with: nil)
            }
        }
    }

    private var playbackActionButton: some View {
        Button(action: togglePlayback) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 84, height: 84)
                .background(Color.black.opacity(0.72))
                .foregroundStyle(.white)
                .clipShape(Circle())
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { playbackProgress },
                    set: { newValue in
                        isSeeking = true
                        playbackProgress = newValue
                        currentTime = duration * newValue
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        isSeeking = true
                        controlsHideWorkItem?.cancel()
                    } else {
                        seekToProgress(playbackProgress)
                        isSeeking = false
                        if isPlaying {
                            scheduleControlsAutoHide()
                        }
                    }
                }
            )
            .tint(.white)

            HStack {
                Text(formatPlaybackTime(currentTime))
                Spacer()
                Text(formatPlaybackTime(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color.black.opacity(0.85))
    }

    static func loadVideoPresentationInfo(for url: URL) -> VideoPresentationInfo {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return VideoPresentationInfo() }

        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)

        guard width > 0, height > 0 else { return VideoPresentationInfo() }

        let aspectRatio = width / height
        if aspectRatio > 1 {
            return VideoPresentationInfo(rotationDegrees: 90, aspectRatio: aspectRatio)
        } else {
            return VideoPresentationInfo(rotationDegrees: 0, aspectRatio: aspectRatio)
        }
    }

    private func addTimeObserver() {
        removeTimeObserver()

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isSeeking else { return }

            let seconds = max(time.seconds, 0)
            currentTime = seconds

            if duration > 0 {
                playbackProgress = min(max(seconds / duration, 0), 1)
            } else {
                playbackProgress = 0
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func updateDuration() {
        let seconds = player.currentItem?.asset.duration.seconds ?? 0
        duration = seconds.isFinite && seconds > 0 ? seconds : 0
    }

    private func seekToProgress(_ progress: Double) {
        guard duration > 0 else { return }

        let targetTime = CMTime(seconds: duration * progress, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
            controlsVisible = true
            controlsHideWorkItem?.cancel()
        } else {
            if duration > 0, currentTime >= duration {
                let restartTime = CMTime(seconds: 0, preferredTimescale: 600)
                player.seek(to: restartTime, toleranceBefore: .zero, toleranceAfter: .zero)
                currentTime = 0
                playbackProgress = 0
            }

            player.play()
            isPlaying = true
            scheduleControlsAutoHide()
        }
    }

    private func toggleControlsVisibility() {
        if controlsVisible {
            controlsVisible = false
            controlsHideWorkItem?.cancel()
        } else {
            controlsVisible = true
            if isPlaying {
                scheduleControlsAutoHide()
            }
        }
    }

    private func scheduleControlsAutoHide() {
        controlsHideWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            if isPlaying && !isSeeking {
                controlsVisible = false
            }
        }

        controlsHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private func formatPlaybackTime(_ seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "00:00" }

        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct VideoReviewScreen: View {
    let video: SavedVideo
    @Environment(\.dismiss) private var dismiss

    @State private var player = AVPlayer()
    @State private var session: ReviewSession?
    @State private var presentationInfo = VideoPresentationInfo()
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isSeeking = false
    @State private var isPlaying = false
    @State private var timeObserver: Any?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Color.black

                        InlineVideoPlayer(player: player, videoGravity: .resizeAspect)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if session == nil {
                            ProgressView("分析影片中...")
                                .padding(20)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(presentationInfo.aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let currentFrame = currentReviewFrame {
                                ReviewFrameSummary(frame: currentFrame)
                            }

                            if let activeSuggestion {
                                ActiveReviewSuggestionCard(suggestion: activeSuggestion)
                            } else if let activeEvent {
                                ActiveMovementEventCard(event: activeEvent)
                            }
                        }
                        .padding(16)
                    }

                    reviewPlaybackControls

                    if let session {
                        reviewSummary(session: session)
                        reviewTimeline(session: session)
                        reviewSuggestionList(session: session)
                        reviewEventList(session: session)
                        reviewTrackPreview(session: session)
                    } else {
                        Text("正在建立 review 資料模型與事件點。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("影片 Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadReview()
            }
            .onDisappear {
                removeReviewTimeObserver()
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
        }
    }

    private var currentReviewFrame: PlayerTrackFrame? {
        guard let frames = session?.trackFrames, !frames.isEmpty else { return nil }
        return frames.min(by: { abs($0.time - currentTime) < abs($1.time - currentTime) })
    }

    private var activeEvent: MovementEvent? {
        session?.movementEvents.first(where: { currentTime >= $0.startTime && currentTime <= $0.endTime })
    }

    private var activeSuggestion: ReviewSuggestion? {
        session?.suggestions.first(where: { currentTime >= $0.timeRange.lowerBound && currentTime <= $0.timeRange.upperBound })
    }

    private var reviewPlaybackControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                Button(action: toggleReviewPlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Circle())
                }

                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: {
                                guard duration > 0 else { return 0 }
                                return currentTime / duration
                            },
                            set: { newValue in
                                isSeeking = true
                                currentTime = duration * newValue
                            }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if editing {
                                isSeeking = true
                            } else {
                                seekReview(to: currentTime)
                                isSeeking = false
                            }
                        }
                    )

                    HStack {
                        Text(reviewTimeString(currentTime))
                        Spacer()
                        Text(reviewTimeString(duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reviewSummary(session: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Session")
                .font(.headline)

            HStack {
                reviewStat(title: "影片長度", value: reviewTimeString(session.duration))
                reviewStat(title: "分析影格", value: "\(session.trackFrames.count)")
                reviewStat(title: "事件點", value: "\(session.movementEvents.count)")
                reviewStat(title: "AI 建議", value: "\(session.suggestions.count)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func reviewTimeline(session: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Timeline")
                .font(.headline)

            ReviewTimelineView(
                duration: max(session.duration, 0.1),
                currentTime: currentTime,
                events: session.movementEvents
            ) { event in
                seekToEvent(event)
            }
            .frame(height: 52)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(session.movementEvents) { event in
                        Button {
                            seekToEvent(event)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(reviewTimeString(event.time))
                                    .font(.caption.monospacedDigit())
                                Text(event.kindLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(event.tintColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func reviewEventList(session: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement Events")
                .font(.headline)

            ForEach(session.movementEvents) { event in
                Button {
                    seekToEvent(event)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(event.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("\(Int((event.confidence * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Text(event.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)

                        HStack {
                            Text(event.playerLabel ?? "雙人站位")
                            Spacer()
                            Text("\(reviewTimeString(event.startTime)) - \(reviewTimeString(event.endTime))")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(event.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func reviewSuggestionList(session: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Suggestions")
                .font(.headline)

            ForEach(session.suggestions) { suggestion in
                Button {
                    currentTime = suggestion.timeRange.lowerBound
                    seekReview(to: suggestion.timeRange.lowerBound)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("\(Int((suggestion.confidence * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Text(suggestion.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)

                        HStack {
                            Text(suggestion.playerLabel ?? "雙人站位")
                            Spacer()
                            Text("\(reviewTimeString(suggestion.timeRange.lowerBound)) - \(reviewTimeString(suggestion.timeRange.upperBound))")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(suggestion.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func reviewTrackPreview(session: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Track Frames")
                .font(.headline)

            ForEach(session.trackFrames.prefix(6)) { frame in
                VStack(alignment: .leading, spacing: 6) {
                    Text(reviewTimeString(frame.time))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    ForEach(frame.players) { player in
                        Text("\(player.label): x \(frameValueString(player.boundingBox.midX)) · y \(frameValueString(player.boundingBox.midY)) · w \(frameValueString(player.boundingBox.width)) · h \(frameValueString(player.boundingBox.height))")
                            .font(.footnote.monospaced())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func reviewStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func loadReview() async {
        presentationInfo = VideoPlayerScreen.loadVideoPresentationInfo(for: video.url)
        let item = AVPlayerItem(url: video.url)
        player.replaceCurrentItem(with: item)
        duration = item.asset.duration.seconds.isFinite ? max(item.asset.duration.seconds, 0) : 0
        addReviewTimeObserver()
        player.play()
        isPlaying = true

        let reviewSession = await VideoReviewAnalyzer.analyze(video: video)
        session = reviewSession
        duration = max(reviewSession.duration, duration)
    }

    private func addReviewTimeObserver() {
        removeReviewTimeObserver()

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isSeeking else { return }
            let seconds = time.seconds
            currentTime = seconds.isFinite ? max(seconds, 0) : 0
        }
    }

    private func removeReviewTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func seekReview(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func seekToEvent(_ event: MovementEvent) {
        currentTime = event.startTime
        seekReview(to: event.startTime)
    }

    private func toggleReviewPlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0, currentTime >= duration {
                seekReview(to: 0)
                currentTime = 0
            }

            player.play()
            isPlaying = true
        }
    }

    private func reviewTimeString(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func frameValueString(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }
}

struct ReviewFrameSummary: View {
    let frame: PlayerTrackFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("目前分析幀")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

            Text(timeString(frame.time))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)

            ForEach(frame.players) { player in
                Text("\(player.label)  \(compact(player.boundingBox.midX)), \(compact(player.boundingBox.midY))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))
    }

    private func timeString(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func compact(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}

struct ActiveMovementEventCard: View {
    let event: MovementEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("目前事件")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))

                Spacer()

                Text(event.kindLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(event.tintColor.opacity(0.26), in: Capsule())
                    .foregroundStyle(.white)
            }

            Text(event.title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(event.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.92))

            Text("\(timeRangeLabel)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(12)
        .background(Color.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
    }

    private var timeRangeLabel: String {
        "\(timeString(event.startTime)) - \(timeString(event.endTime))"
    }

    private func timeString(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct ActiveReviewSuggestionCard: View {
    let suggestion: ReviewSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI 建議")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))

                Spacer()

                Text(suggestionTitle)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(suggestion.tintColor.opacity(0.26), in: Capsule())
                    .foregroundStyle(.white)
            }

            Text(suggestion.title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(suggestion.text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.94))

            HStack {
                Text(suggestion.playerLabel ?? "雙人站位")
                Spacer()
                Text("\(timeString(suggestion.timeRange.lowerBound)) - \(timeString(suggestion.timeRange.upperBound))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.82))
        }
        .padding(12)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }

    private var suggestionTitle: String {
        suggestion.eventKindLabel
    }

    private func timeString(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct ReviewTimelineView: View {
    let duration: Double
    let currentTime: Double
    let events: [MovementEvent]
    let onSelectEvent: (MovementEvent) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)

                Capsule()
                    .fill(Color.blue.opacity(0.7))
                    .frame(
                        width: max(CGFloat(currentTime / duration) * geometry.size.width, 0),
                        height: 6
                    )

                ForEach(events) { event in
                    Button {
                        onSelectEvent(event)
                    } label: {
                        Circle()
                            .fill(event.tintColor)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: min(max(CGFloat(event.time / duration) * geometry.size.width, 8), geometry.size.width - 8),
                        y: geometry.size.height / 2
                    )
                }
            }
        }
    }
}

extension MovementEvent {
    var tintColor: Color {
        switch kind {
        case .closeSpacing:
            return .orange
        case .wideSpacing:
            return .blue
        case .crossover:
            return .pink
        case .deepRetreat:
            return .green
        }
    }

    var kindLabel: String {
        switch kind {
        case .closeSpacing:
            return "站位過近"
        case .wideSpacing:
            return "站位過開"
        case .crossover:
            return "左右交叉"
        case .deepRetreat:
            return "退太深"
        }
    }
}

extension ReviewSuggestion {
    var tintColor: Color {
        switch eventKind {
        case .closeSpacing:
            return .orange
        case .wideSpacing:
            return .blue
        case .crossover:
            return .pink
        case .deepRetreat:
            return .green
        }
    }

    var eventKindLabel: String {
        switch eventKind {
        case .closeSpacing:
            return "站位過近"
        case .wideSpacing:
            return "站位過開"
        case .crossover:
            return "左右交叉"
        case .deepRetreat:
            return "退太深"
        }
    }
}

struct VideoPresentationInfo {
    var rotationDegrees: Double = 0
    var aspectRatio: CGFloat = 16 / 9
}

struct InlineVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

final class CameraManager: NSObject, ObservableObject {
    enum RecordingDecision {
        case save
        case discard
    }

    private enum RallyDetectionConstants {
        static let minimumImpactLevel: Float = 0.035
        static let dynamicThresholdMultiplier: Float = 2.8
        static let impactCooldown: Double = 0.12
        static let rallyEndSilenceWindow: Double = 1.1
        static let levelSmoothingFactor: Float = 0.22
        static let floorAdaptationFactor: Float = 0.015
    }

    private enum TrackingConstants {
        static let playerLabels = ["Player1", "Player2"]
        static let detectionInterval = 1
        static let minimumHumanConfidence: VNConfidence = 0.45
        static let minimumHumanArea: CGFloat = 0.015
        static let fallbackHumanConfidence: VNConfidence = 0.2
        static let fallbackHumanArea: CGFloat = 0.006
        static let minimumBodyPosePointConfidence: VNConfidence = 0.18
        static let minimumBodyPosePointCount = 4
        static let bodyPosePaddingX: CGFloat = 0.18
        static let bodyPosePaddingY: CGFloat = 0.16
        static let smoothingFactor: CGFloat = 0.6
        static let minimumIoUForMatch: CGFloat = 0.08
        static let maximumNormalizedCenterDistance: CGFloat = 0.34
        static let fallbackFrameLimit = 6
    }

    private enum RallyFeedbackConstants {
        static let recoverCheckDelay: Double = 0.5
        static let recoverDistanceThreshold: CGFloat = 0.22
        static let moveOutAfterHittingDuration: Double = 1.0
    }

    let session = AVCaptureSession()
    @Published private(set) var trackedPlayers: [TrackedPlayerBox] = []
    @Published private(set) var trackingDebugInfo = TrackingDebugInfo()
    @Published private(set) var captureDevice: AVCaptureDevice?
    @Published private(set) var isRecordingActive = false
    @Published private(set) var rallyState: RallyState = .end
    @Published private(set) var playerAreaSpatialStatus = PlayerAreaSpatialStatus.uncalibrated

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "TTCoach.CameraSessionQueue", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "TTCoach.HumanDetectionQueue", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "TTCoach.AudioDetectionQueue", qos: .userInitiated)
    private let rallyAnalysisQueue = DispatchQueue(label: "TTCoach.RallyAnalysisQueue", qos: .userInitiated)
    private let ciContext = CIContext()
    private let rallyFeedbackSpeaker = RallyFeedbackSpeaker()

    private struct HumanDetectionResult {
        let source: String
        let rectangleCandidates: [CGRect]
        let bodyPoseCandidates: [CGRect]
        let selectedCandidates: [CGRect]
    }

    private struct ActiveHitterState {
        let hitterID: String
        let startedAt: Double
        let didTriggerMoveOutFeedback: Bool
        let isMoveOutFeedbackExempt: Bool
    }

    private struct PendingRecoverCheck {
        let hitterID: String
        let nonHitterID: String
        let dueTime: Double
    }

    private var isConfigured = false
    private var frameCounter = 0
    private var latestTrackedPlayers: [TrackedPlayerBox] = []
    private var trackingRequests: [VNTrackObjectRequest] = []
    private var missedDetectionFrames = 0
    private var recordingDecision: RecordingDecision = .discard
    private var stopCompletion: ((URL?) -> Void)?
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingURL: URL?
    private var recordingStartTime: CMTime?
    private var recordingCropRect: CGRect = .zero
    private var recordingRenderSize: CGSize = .zero
    private var recordingSourceCanvasSize: CGSize = .zero
    private var isRecording = false
    private var shouldStopRecording = false
    private var isFinishingRecording = false
    private var playerAreaCalibration: PlayerAreaCalibration?
    private var smoothedAudioLevel: Float = 0
    private var audioFloorLevel: Float = 0.01
    private var lastImpactTimestamp: Double = -.greatestFiniteMagnitude
    private var lastAudioTimestamp: Double = 0
    private var currentRallyState: RallyState = .end
    private var activeHitterState: ActiveHitterState?
    private var pendingRecoverChecks: [PendingRecoverCheck] = []
    private var queuedRallyFeedback = Set<RallyFeedback>()
    private var audioFeedbackMuteUntil: CFTimeInterval = 0

    func requestPermissionAndStart(completion: @escaping (Bool) -> Void) {
        requestCapturePermissions { granted in
            if granted {
                self.configureAndStartSession()
            }

            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func stopSession(saveRecording: Bool, completion: @escaping (URL?) -> Void) {
        recordingDecision = saveRecording ? .save : .discard
        stopCompletion = completion

        sessionQueue.async {
            if self.isRecording {
                self.shouldStopRecording = true
            } else {
                self.finishStoppingSession(with: nil)
            }
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async {
            if !self.isConfigured {
                self.configureSession()
                self.isConfigured = true
            }

            guard !self.session.isRunning else { return }

            self.session.startRunning()
        }
    }

    func startRecording() {
        sessionQueue.async {
            self.beginRecordingIfNeeded()
        }
    }

    func rallyEnded() {
        transitionRallyState(to: .end, playFeedback: false)
    }

    func updatePlayerAreaCalibration(_ calibration: PlayerAreaCalibration?) {
        visionQueue.async {
            self.playerAreaCalibration = calibration
        }

        DispatchQueue.main.async {
            self.playerAreaSpatialStatus = calibration == nil
                ? .uncalibrated
                : PlayerAreaSpatialStatus(isCalibrated: true, spacingSummary: "等待球員進入區域", holeSummary: "等待球員進入區域")
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        defer {
            session.commitConfiguration()
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back) else {
            print("No back camera found.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            DispatchQueue.main.async {
                self.captureDevice = camera
            }
        } catch {
            print("Failed to create camera input: \(error)")
        }

        if let microphone = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: microphone)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            } catch {
                print("Failed to create audio input: \(error)")
            }
        }

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: visionQueue)
        audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)

        guard session.canAddOutput(videoDataOutput) else {
            print("Failed to add video data output.")
            return
        }

        session.addOutput(videoDataOutput)

        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
        } else {
            print("Failed to add audio data output.")
        }

        if let connection = videoDataOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
    }

    private func beginRecordingIfNeeded() {
        guard !isRecording else { return }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        try? FileManager.default.removeItem(at: temporaryURL)
        recordingURL = temporaryURL
        recordingStartTime = nil
        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
        shouldStopRecording = false
        isFinishingRecording = false
        isRecording = true
        smoothedAudioLevel = 0
        audioFloorLevel = 0.01
        lastImpactTimestamp = -.greatestFiniteMagnitude
        lastAudioTimestamp = 0
        resetRallyAnalysisState()
        DispatchQueue.main.async {
            self.isRecordingActive = true
            self.rallyState = .end
        }
    }

    private func finishStoppingSession(with outputURL: URL?) {
        isRecording = false
        shouldStopRecording = false
        isFinishingRecording = false
        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
        recordingStartTime = nil
        recordingURL = nil
        recordingCropRect = .zero
        recordingRenderSize = .zero
        recordingSourceCanvasSize = .zero
        resetRallyAnalysisState()

        if session.isRunning {
            session.stopRunning()
        }

        latestTrackedPlayers = []
        trackingRequests = []
        frameCounter = 0
        missedDetectionFrames = 0

        DispatchQueue.main.async {
            self.trackedPlayers = []
            self.trackingDebugInfo = TrackingDebugInfo()
            self.isRecordingActive = false
            self.rallyState = .end
            self.playerAreaSpatialStatus = self.playerAreaCalibration == nil
                ? .uncalibrated
                : PlayerAreaSpatialStatus(isCalibrated: true, spacingSummary: "等待球員進入區域", holeSummary: "等待球員進入區域")
        }

        let completion = stopCompletion
        stopCompletion = nil

        DispatchQueue.main.async {
            completion?(outputURL)
        }
    }

    private func requestCapturePermissions(completion: @escaping (Bool) -> Void) {
        requestVideoPermission { videoGranted in
            guard videoGranted else {
                completion(false)
                return
            }

            self.requestAudioPermission(completion: completion)
        }
    }

    private func requestVideoPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        default:
            print("Camera permission denied or restricted.")
            completion(false)
        }
    }

    private func requestAudioPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        default:
            print("Microphone permission denied or restricted.")
            completion(false)
        }
    }

    private func updateRallyState(_ newState: RallyState) {
        DispatchQueue.main.async {
            self.rallyState = newState
        }
    }

    private func rallyStateSnapshot() -> RallyState {
        rallyAnalysisQueue.sync {
            currentRallyState
        }
    }

    private func resetRallyAnalysisState() {
        rallyAnalysisQueue.sync {
            resetRallyAnalysisStateLocked()
            currentRallyState = .end
            audioFeedbackMuteUntil = 0
        }
        rallyFeedbackSpeaker.stop()
    }

    private func transitionRallyState(to newState: RallyState, playFeedback: Bool) {
        let feedbackToPlay: [RallyFeedback] = rallyAnalysisQueue.sync {
            let previousState = currentRallyState
            currentRallyState = newState

            switch newState {
            case .start:
                if previousState != .start {
                    resetRallyAnalysisStateLocked()
                }
                return []

            case .end:
                let feedback = playFeedback && previousState == .start
                    ? orderedQueuedFeedbackLocked()
                    : []
                resetRallyAnalysisStateLocked()
                return feedback
            }
        }

        updateRallyState(newState)

        guard !feedbackToPlay.isEmpty else { return }

        let muteDuration = rallyFeedbackSpeaker.speak(feedbackToPlay)
        rallyAnalysisQueue.async {
            self.audioFeedbackMuteUntil = CACurrentMediaTime() + muteDuration
        }
    }

    private func resetRallyAnalysisStateLocked() {
        activeHitterState = nil
        pendingRecoverChecks = []
        queuedRallyFeedback = []
    }

    private func orderedQueuedFeedbackLocked() -> [RallyFeedback] {
        RallyFeedback.allCases.filter { queuedRallyFeedback.contains($0) }
    }

    private func updateRallyFeedbackTracking(with players: [TrackedPlayerBox], timestamp: Double) {
        guard timestamp.isFinite else { return }

        let playerLookup = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        let hitterID = players.first(where: \.isCurrentHitter)?.id

        rallyAnalysisQueue.async {
            guard self.currentRallyState == .start else { return }

            self.resolvePendingRecoverChecksLocked(
                using: playerLookup,
                currentHitterID: hitterID,
                timestamp: timestamp
            )

            guard
                let hitterID,
                playerLookup[hitterID]?.playerAreaPoint != nil,
                let nonHitterID = playerLookup.keys.first(where: { $0 != hitterID }),
                playerLookup[nonHitterID]?.playerAreaPoint != nil
            else {
                return
            }

            if let activeHitterState = self.activeHitterState {
                if activeHitterState.hitterID != hitterID {
                    self.pendingRecoverChecks.append(
                        PendingRecoverCheck(
                            hitterID: hitterID,
                            nonHitterID: nonHitterID,
                            dueTime: timestamp + RallyFeedbackConstants.recoverCheckDelay
                        )
                    )
                    self.activeHitterState = ActiveHitterState(
                        hitterID: hitterID,
                        startedAt: timestamp,
                        didTriggerMoveOutFeedback: false,
                        isMoveOutFeedbackExempt: false
                    )
                    return
                }

                if
                    !activeHitterState.isMoveOutFeedbackExempt,
                    !activeHitterState.didTriggerMoveOutFeedback,
                    (timestamp - activeHitterState.startedAt) >= RallyFeedbackConstants.moveOutAfterHittingDuration
                {
                    self.queueMoveOutFeedbackLocked(for: hitterID)
                    self.activeHitterState = ActiveHitterState(
                        hitterID: hitterID,
                        startedAt: activeHitterState.startedAt,
                        didTriggerMoveOutFeedback: true,
                        isMoveOutFeedbackExempt: false
                    )
                }
                return
            }

            self.pendingRecoverChecks.append(
                PendingRecoverCheck(
                    hitterID: hitterID,
                    nonHitterID: nonHitterID,
                    dueTime: timestamp + RallyFeedbackConstants.recoverCheckDelay
                )
            )
            self.activeHitterState = ActiveHitterState(
                hitterID: hitterID,
                startedAt: timestamp,
                didTriggerMoveOutFeedback: false,
                isMoveOutFeedbackExempt: true
            )
        }
    }

    private func resolvePendingRecoverChecksLocked(
        using playerLookup: [String: TrackedPlayerBox],
        currentHitterID: String?,
        timestamp: Double
    ) {
        guard !pendingRecoverChecks.isEmpty else { return }

        var remainingChecks: [PendingRecoverCheck] = []

        for check in pendingRecoverChecks {
            guard timestamp >= check.dueTime else {
                remainingChecks.append(check)
                continue
            }

            guard
                currentHitterID == check.hitterID,
                let hitterPoint = playerLookup[check.hitterID]?.playerAreaPoint,
                let nonHitterPoint = playerLookup[check.nonHitterID]?.playerAreaPoint
            else {
                continue
            }

            let distance = hypot(hitterPoint.x - nonHitterPoint.x, hitterPoint.y - nonHitterPoint.y)
            if distance <= RallyFeedbackConstants.recoverDistanceThreshold {
                queueRecoverEarlierFeedbackLocked(for: check.nonHitterID)
            }
        }

        pendingRecoverChecks = remainingChecks
    }

    private func queueRecoverEarlierFeedbackLocked(for playerID: String) {
        switch playerID {
        case "Player1":
            queuedRallyFeedback.insert(.p1RecoverEarlier)
        case "Player2":
            queuedRallyFeedback.insert(.p2RecoverEarlier)
        default:
            break
        }
    }

    private func queueMoveOutFeedbackLocked(for playerID: String) {
        switch playerID {
        case "Player1":
            queuedRallyFeedback.insert(.p1MoveOutAfterHitting)
        case "Player2":
            queuedRallyFeedback.insert(.p2MoveOutAfterHitting)
        default:
            break
        }
    }

    private func isAudioFeedbackMuted() -> Bool {
        let now = CACurrentMediaTime()
        return rallyAnalysisQueue.sync {
            now < audioFeedbackMuteUntil
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audioDataOutput {
            processAudioSampleBuffer(sampleBuffer)
            return
        }

        guard output === videoDataOutput else { return }
        appendFrameToRecording(sampleBuffer)

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        frameCounter += 1

        guard frameCounter.isMultiple(of: TrackingConstants.detectionInterval) else { return }
        detectLivePlayers(in: pixelBuffer, timestamp: timestamp)
    }

    private func detectLivePlayers(in pixelBuffer: CVPixelBuffer, timestamp: Double) {
        do {
            let detectionResult = try detectHumanBoundingBoxes(in: pixelBuffer)
            let boundingBoxes = detectionResult.selectedCandidates

            guard boundingBoxes.count >= TrackingConstants.playerLabels.count else {
                missedDetectionFrames += 1
                if missedDetectionFrames > TrackingConstants.fallbackFrameLimit {
                    latestTrackedPlayers = []
                    trackingRequests = []
                    DispatchQueue.main.async {
                        self.trackedPlayers = []
                    }
                    updateTrackingDebugInfo(
                        source: detectionResult.source,
                        rectangleCandidates: detectionResult.rectangleCandidates.count,
                        bodyPoseCandidates: detectionResult.bodyPoseCandidates.count,
                        selectedCandidates: boundingBoxes.count,
                        players: []
                    )
                } else if !latestTrackedPlayers.isEmpty {
                    updateTrackedPlayers(latestTrackedPlayers)
                    updateTrackingDebugInfo(
                        source: detectionResult.source,
                        rectangleCandidates: detectionResult.rectangleCandidates.count,
                        bodyPoseCandidates: detectionResult.bodyPoseCandidates.count,
                        selectedCandidates: boundingBoxes.count,
                        players: latestTrackedPlayers
                    )
                } else {
                    updateTrackingDebugInfo(
                        source: detectionResult.source,
                        rectangleCandidates: detectionResult.rectangleCandidates.count,
                        bodyPoseCandidates: detectionResult.bodyPoseCandidates.count,
                        selectedCandidates: boundingBoxes.count,
                        players: []
                    )
                }
                return
            }

            missedDetectionFrames = 0
            let players = associatedPlayers(from: boundingBoxes, previousPlayers: latestTrackedPlayers)
            let smoothedPlayers = smoothedPlayers(from: players)
            let annotatedPlayers = annotatePlayers(smoothedPlayers)
            updateRallyFeedbackTracking(with: annotatedPlayers, timestamp: timestamp)
            updateTrackingRequests(from: annotatedPlayers)
            updateTrackedPlayers(annotatedPlayers)
            updateTrackingDebugInfo(
                source: detectionResult.source,
                rectangleCandidates: detectionResult.rectangleCandidates.count,
                bodyPoseCandidates: detectionResult.bodyPoseCandidates.count,
                selectedCandidates: boundingBoxes.count,
                players: annotatedPlayers
            )
        } catch {
            print("Failed to detect live players: \(error)")
            updateTrackingDebugInfo(
                source: "error",
                rectangleCandidates: 0,
                bodyPoseCandidates: 0,
                selectedCandidates: 0,
                players: latestTrackedPlayers
            )
        }
    }

    private func detectHumanBoundingBoxes(in pixelBuffer: CVPixelBuffer) throws -> HumanDetectionResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let humanRectanglesRequest = VNDetectHumanRectanglesRequest()
        humanRectanglesRequest.upperBodyOnly = false
        try handler.perform([humanRectanglesRequest])

        let observations = (humanRectanglesRequest.results ?? [])
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return (lhs.boundingBox.width * lhs.boundingBox.height) > (rhs.boundingBox.width * rhs.boundingBox.height)
                }
                return lhs.confidence > rhs.confidence
            }

        let strictMatches = observations
            .filter { observation in
                observation.confidence >= TrackingConstants.minimumHumanConfidence &&
                (observation.boundingBox.width * observation.boundingBox.height) >= TrackingConstants.minimumHumanArea
            }
            .sorted { $0.boundingBox.midX < $1.boundingBox.midX }

        if strictMatches.count >= TrackingConstants.playerLabels.count {
            return HumanDetectionResult(
                source: "rectangles-strict",
                rectangleCandidates: observations.map(\.boundingBox),
                bodyPoseCandidates: [],
                selectedCandidates: strictMatches.map(\.boundingBox)
            )
        }

        let relaxedRectangleMatches = observations
            .filter { observation in
                observation.confidence >= TrackingConstants.fallbackHumanConfidence &&
                (observation.boundingBox.width * observation.boundingBox.height) >= TrackingConstants.fallbackHumanArea
            }
            .sorted { $0.boundingBox.midX < $1.boundingBox.midX }
            .map(\.boundingBox)

        if relaxedRectangleMatches.count >= TrackingConstants.playerLabels.count {
            return HumanDetectionResult(
                source: "rectangles-relaxed",
                rectangleCandidates: observations.map(\.boundingBox),
                bodyPoseCandidates: [],
                selectedCandidates: relaxedRectangleMatches
            )
        }

        let bodyPoseBoxes = try detectBodyPoseBoundingBoxes(in: pixelBuffer)
        if bodyPoseBoxes.count >= relaxedRectangleMatches.count {
            return HumanDetectionResult(
                source: "body-pose",
                rectangleCandidates: observations.map(\.boundingBox),
                bodyPoseCandidates: bodyPoseBoxes,
                selectedCandidates: bodyPoseBoxes
            )
        }

        return HumanDetectionResult(
            source: "rectangles-fallback",
            rectangleCandidates: observations.map(\.boundingBox),
            bodyPoseCandidates: bodyPoseBoxes,
            selectedCandidates: relaxedRectangleMatches
        )
    }

    private func detectBodyPoseBoundingBoxes(in pixelBuffer: CVPixelBuffer) throws -> [CGRect] {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .compactMap { observation in
                guard let points = try? observation.recognizedPoints(.all).values else { return nil }

                let validPoints = points.filter { $0.confidence >= TrackingConstants.minimumBodyPosePointConfidence }
                guard validPoints.count >= TrackingConstants.minimumBodyPosePointCount else { return nil }

                let xs = validPoints.map { $0.location.x }
                let ys = validPoints.map { $0.location.y }

                guard
                    let minX = xs.min(),
                    let maxX = xs.max(),
                    let minY = ys.min(),
                    let maxY = ys.max()
                else {
                    return nil
                }

                var rect = CGRect(
                    x: minX,
                    y: minY,
                    width: maxX - minX,
                    height: maxY - minY
                )

                guard rect.width > 0, rect.height > 0 else { return nil }

                rect = rect.insetBy(
                    dx: -(rect.width * TrackingConstants.bodyPosePaddingX),
                    dy: -(rect.height * TrackingConstants.bodyPosePaddingY)
                )

                let clampedRect = CGRect(
                    x: max(0, rect.origin.x),
                    y: max(0, rect.origin.y),
                    width: min(1, rect.maxX) - max(0, rect.origin.x),
                    height: min(1, rect.maxY) - max(0, rect.origin.y)
                )

                guard
                    clampedRect.width * clampedRect.height >= TrackingConstants.fallbackHumanArea
                else {
                    return nil
                }

                return clampedRect
            }
            .sorted { $0.midX < $1.midX }
    }

    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else {
            if rallyStateSnapshot() != .end {
                transitionRallyState(to: .end, playFeedback: false)
            }
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp.isFinite, let level = audioPeakLevel(from: sampleBuffer) else { return }

        if isAudioFeedbackMuted() {
            smoothedAudioLevel = 0
            audioFloorLevel = 0.01
            lastImpactTimestamp = timestamp
            lastAudioTimestamp = timestamp
            return
        }

        let smoothing = RallyDetectionConstants.levelSmoothingFactor
        smoothedAudioLevel = (smoothedAudioLevel * (1 - smoothing)) + (level * smoothing)
        audioFloorLevel = max(
            0.003,
            (audioFloorLevel * (1 - RallyDetectionConstants.floorAdaptationFactor)) + (smoothedAudioLevel * RallyDetectionConstants.floorAdaptationFactor)
        )
        lastAudioTimestamp = timestamp

        let dynamicThreshold = max(
            RallyDetectionConstants.minimumImpactLevel,
            audioFloorLevel * RallyDetectionConstants.dynamicThresholdMultiplier
        )
        let isImpact = smoothedAudioLevel > dynamicThreshold &&
            (timestamp - lastImpactTimestamp) >= RallyDetectionConstants.impactCooldown

        if isImpact {
            lastImpactTimestamp = timestamp
            if rallyStateSnapshot() != .start {
                transitionRallyState(to: .start, playFeedback: false)
            }
            return
        }

        if rallyStateSnapshot() == .start,
           (timestamp - lastImpactTimestamp) >= RallyDetectionConstants.rallyEndSilenceWindow {
            transitionRallyState(to: .end, playFeedback: true)
        }
    }

    private func audioPeakLevel(from sampleBuffer: CMSampleBuffer) -> Float? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        let streamDescription = streamDescriptionPointer.pointee
        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (streamDescription.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)

        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        var peak: Float = 0

        for audioBuffer in buffers {
            guard let rawPointer = audioBuffer.mData else { continue }

            switch (isFloat, isSignedInteger, bitsPerChannel) {
            case (true, _, 32):
                let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = rawPointer.bindMemory(to: Float.self, capacity: sampleCount)
                for index in 0..<sampleCount {
                    peak = max(peak, abs(samples[index]))
                }
            case (true, _, 64):
                let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Double>.size
                let samples = rawPointer.bindMemory(to: Double.self, capacity: sampleCount)
                for index in 0..<sampleCount {
                    peak = max(peak, Float(abs(samples[index])))
                }
            case (_, true, 16):
                let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.size
                let samples = rawPointer.bindMemory(to: Int16.self, capacity: sampleCount)
                for index in 0..<sampleCount {
                    peak = max(peak, Float(abs(Int(samples[index]))) / Float(Int16.max))
                }
            case (_, true, 32):
                let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int32>.size
                let samples = rawPointer.bindMemory(to: Int32.self, capacity: sampleCount)
                for index in 0..<sampleCount {
                    peak = max(peak, Float(abs(Double(samples[index]))) / Float(Int32.max))
                }
            default:
                return nil
            }
        }

        return peak
    }

    private func associatedPlayers(
        from boundingBoxes: [CGRect],
        previousPlayers: [TrackedPlayerBox]
    ) -> [TrackedPlayerBox] {
        guard previousPlayers.count == TrackingConstants.playerLabels.count else {
            return zip(boundingBoxes.prefix(TrackingConstants.playerLabels.count), TrackingConstants.playerLabels).map { boundingBox, label in
                TrackedPlayerBox(id: label, label: label, boundingBox: boundingBox)
            }
        }

        let candidateBoxes = boundingBoxes
        var usedIndices = Set<Int>()
        var associatedPlayers: [TrackedPlayerBox] = []

        for previousPlayer in previousPlayers {
            let bestMatch = candidateBoxes.enumerated()
                .filter { !usedIndices.contains($0.offset) }
                .map { index, box in
                    (index, trackingMatchScore(previous: previousPlayer.boundingBox, candidate: box))
                }
                .max { $0.1 < $1.1 }

            if
                let bestMatch,
                bestMatch.1 > 0
            {
                usedIndices.insert(bestMatch.0)
                associatedPlayers.append(
                    TrackedPlayerBox(
                        id: previousPlayer.id,
                        label: previousPlayer.label,
                        boundingBox: candidateBoxes[bestMatch.0]
                    )
                )
            }
        }

        let unmatchedBoxes = candidateBoxes.enumerated()
            .filter { !usedIndices.contains($0.offset) }
            .map(\.element)
            .sorted { $0.midX < $1.midX }

        let missingLabels = TrackingConstants.playerLabels.filter { label in
            !associatedPlayers.contains(where: { $0.label == label })
        }

        for (box, label) in zip(unmatchedBoxes, missingLabels) {
            associatedPlayers.append(
                TrackedPlayerBox(id: label, label: label, boundingBox: box)
            )
        }

        return associatedPlayers.sorted { lhs, rhs in
            TrackingConstants.playerLabels.firstIndex(of: lhs.label)! < TrackingConstants.playerLabels.firstIndex(of: rhs.label)!
        }
    }

    private func trackingMatchScore(previous: CGRect, candidate: CGRect) -> CGFloat {
        let intersection = previous.intersection(candidate)
        let intersectionArea = max(intersection.width, 0) * max(intersection.height, 0)
        let unionArea = (previous.width * previous.height) + (candidate.width * candidate.height) - intersectionArea
        let iou = unionArea > 0 ? intersectionArea / unionArea : 0

        let centerDistance = hypot(previous.midX - candidate.midX, previous.midY - candidate.midY)
        guard
            iou >= TrackingConstants.minimumIoUForMatch ||
            centerDistance <= TrackingConstants.maximumNormalizedCenterDistance
        else {
            return -1
        }

        let normalizedDistanceScore = max(0, 1 - (centerDistance / TrackingConstants.maximumNormalizedCenterDistance))
        return (iou * 0.7) + (normalizedDistanceScore * 0.3)
    }

    private func smoothedPlayers(from players: [TrackedPlayerBox]) -> [TrackedPlayerBox] {
        guard latestTrackedPlayers.count == players.count else { return players }

        return players.map { player in
            guard let previousPlayer = latestTrackedPlayers.first(where: { $0.id == player.id }) else {
                return player
            }

            let factor = TrackingConstants.smoothingFactor
            let smoothedBox = CGRect(
                x: previousPlayer.boundingBox.origin.x + ((player.boundingBox.origin.x - previousPlayer.boundingBox.origin.x) * factor),
                y: previousPlayer.boundingBox.origin.y + ((player.boundingBox.origin.y - previousPlayer.boundingBox.origin.y) * factor),
                width: previousPlayer.boundingBox.width + ((player.boundingBox.width - previousPlayer.boundingBox.width) * factor),
                height: previousPlayer.boundingBox.height + ((player.boundingBox.height - previousPlayer.boundingBox.height) * factor)
            )

            return TrackedPlayerBox(id: player.id, label: player.label, boundingBox: smoothedBox)
        }
    }

    private func annotatePlayers(_ players: [TrackedPlayerBox]) -> [TrackedPlayerBox] {
        let baseAnnotatedPlayers = players.map { player -> TrackedPlayerBox in
            let footPoint = playerFootPoint(for: player.boundingBox)
            let mappedPoint = playerAreaCalibration?.normalizedPoint(forCapturePoint: footPoint)
            return TrackedPlayerBox(
                id: player.id,
                label: player.label,
                boundingBox: player.boundingBox,
                footPoint: footPoint,
                playerAreaPoint: mappedPoint,
                lateralPosition: mappedPoint.map(lateralPositionLabel(for:)),
                depthPosition: mappedPoint.map(depthPositionLabel(for:))
            )
        }

        let hitterID = currentHitterID(from: baseAnnotatedPlayers)
        let annotatedPlayers = baseAnnotatedPlayers.map { player in
            TrackedPlayerBox(
                id: player.id,
                label: player.label,
                boundingBox: player.boundingBox,
                footPoint: player.footPoint,
                playerAreaPoint: player.playerAreaPoint,
                lateralPosition: player.lateralPosition,
                depthPosition: player.depthPosition,
                isCurrentHitter: player.id == hitterID
            )
        }

        updateSpatialStatus(with: annotatedPlayers)
        return annotatedPlayers
    }

    private func currentHitterID(from players: [TrackedPlayerBox]) -> String? {
        let mappedPlayers = players.compactMap { player -> (String, CGPoint)? in
            guard let playerAreaPoint = player.playerAreaPoint else { return nil }
            return (player.id, playerAreaPoint)
        }

        guard mappedPlayers.count == 2 else { return nil }
        return mappedPlayers.min(by: { lhs, rhs in
            lhs.1.y < rhs.1.y
        })?.0
    }

    private func playerFootPoint(for boundingBox: CGRect) -> CGPoint {
        CGPoint(
            x: boundingBox.midX,
            y: 1 - boundingBox.minY
        )
    }

    private func lateralPositionLabel(for point: CGPoint) -> String {
        switch point.x {
        case ..<0.33:
            return "left"
        case 0.67...:
            return "right"
        default:
            return "center"
        }
    }

    private func depthPositionLabel(for point: CGPoint) -> String {
        switch point.y {
        case ..<0.33:
            return "front"
        case 0.67...:
            return "back"
        default:
            return "mid"
        }
    }

    private func updateSpatialStatus(with players: [TrackedPlayerBox]) {
        guard playerAreaCalibration != nil else {
            DispatchQueue.main.async {
                self.playerAreaSpatialStatus = .uncalibrated
            }
            return
        }

        let mappedPlayers = players.compactMap(\.playerAreaPoint)
        guard mappedPlayers.count == 2 else {
            DispatchQueue.main.async {
                self.playerAreaSpatialStatus = PlayerAreaSpatialStatus(
                    isCalibrated: true,
                    spacingSummary: "等待兩位球員都進入標定區",
                    holeSummary: "等待兩位球員都進入標定區"
                )
            }
            return
        }

        let horizontalGap = abs(mappedPlayers[0].x - mappedPlayers[1].x)
        let spacingSummary: String
        switch horizontalGap {
        case ..<0.18:
            spacingSummary = "間距過近"
        case 0.42...:
            spacingSummary = "間距過大"
        default:
            spacingSummary = "間距正常"
        }

        let holeSummary: String
        if mappedPlayers.allSatisfy({ $0.x < 0.45 }) {
            holeSummary = "右側站位漏洞"
        } else if mappedPlayers.allSatisfy({ $0.x > 0.55 }) {
            holeSummary = "左側站位漏洞"
        } else if mappedPlayers.allSatisfy({ $0.y < 0.45 }) {
            holeSummary = "後場站位漏洞"
        } else if mappedPlayers.allSatisfy({ $0.y > 0.55 }) {
            holeSummary = "前場站位漏洞"
        } else {
            holeSummary = "未偵測到明顯漏洞"
        }

        DispatchQueue.main.async {
            self.playerAreaSpatialStatus = PlayerAreaSpatialStatus(
                isCalibrated: true,
                spacingSummary: spacingSummary,
                holeSummary: holeSummary
            )
        }
    }

    private func updateTrackingRequests(from players: [TrackedPlayerBox]) {
        trackingRequests = players.map { player in
            let request = VNTrackObjectRequest(
                detectedObjectObservation: VNDetectedObjectObservation(boundingBox: player.boundingBox)
            )
            request.trackingLevel = .accurate
            return request
        }
    }

    private func updateTrackingDebugInfo(
        source: String,
        rectangleCandidates: Int,
        bodyPoseCandidates: Int,
        selectedCandidates: Int,
        players: [TrackedPlayerBox]
    ) {
        let summaries = players.map { player in
            let playerAreaSummary: String
            if let point = player.playerAreaPoint {
                let lateral = player.lateralPosition ?? "n/a"
                let depth = player.depthPosition ?? "n/a"
                playerAreaSummary = " area:\(formatDebugValue(point.x)),\(formatDebugValue(point.y)) \(lateral)/\(depth)"
            } else {
                playerAreaSummary = ""
            }

            let hitterSummary = player.isCurrentHitter ? " hitter" : ""
            return "\(player.label) x:\(formatDebugValue(player.boundingBox.midX)) y:\(formatDebugValue(player.boundingBox.midY))\(playerAreaSummary)\(hitterSummary)"
        }

        DispatchQueue.main.async {
            self.trackingDebugInfo = TrackingDebugInfo(
                source: source,
                rectangleCandidates: rectangleCandidates,
                bodyPoseCandidates: bodyPoseCandidates,
                selectedCandidates: selectedCandidates,
                trackedPlayers: players.count,
                missedFrames: self.missedDetectionFrames,
                trackedSummaries: summaries
            )
        }
    }

    private func formatDebugValue(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    private func updateTrackedPlayers(_ players: [TrackedPlayerBox]) {
        latestTrackedPlayers = players
        DispatchQueue.main.async {
            self.trackedPlayers = players
        }
    }

    private func appendFrameToRecording(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if assetWriter == nil {
            do {
                try prepareAssetWriter(using: pixelBuffer, startTime: presentationTime)
            } catch {
                print("Failed to prepare video writer: \(error)")
                isRecording = false
                finishStoppingSession(with: nil)
                return
            }
        }

        guard
            let assetWriterInput,
            let pixelBufferAdaptor,
            let recordingStartTime,
            assetWriterInput.isReadyForMoreMediaData
        else { return }

        guard let renderedPixelBuffer = makeRenderedPixelBuffer(from: pixelBuffer) else { return }

        let relativePresentationTime = CMTimeSubtract(presentationTime, recordingStartTime)
        guard relativePresentationTime >= .zero else { return }

        let didAppend = pixelBufferAdaptor.append(renderedPixelBuffer, withPresentationTime: relativePresentationTime)
        if !didAppend {
            print("Failed to append video frame: \(assetWriter?.error?.localizedDescription ?? "unknown error")")
        }

        if shouldStopRecording {
            finishRecording()
        }
    }

    private func prepareAssetWriter(using pixelBuffer: CVPixelBuffer, startTime: CMTime) throws {
        guard let recordingURL else {
            throw NSError(domain: "TTCoach.CameraManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing recording URL."])
        }

        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let sourceCanvasSize = CGSize(width: sourceWidth, height: sourceHeight)
        let recordingGeometry = makeRecordingGeometry(canvasSize: sourceCanvasSize)
        let width = Int(recordingGeometry.renderSize.width)
        let height = Int(recordingGeometry.renderSize.height)

        let writer = try AVAssetWriter(outputURL: recordingURL, fileType: .mov)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        writerInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "TTCoach.CameraManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to add writer input."])
        }

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        assetWriter = writer
        assetWriterInput = writerInput
        pixelBufferAdaptor = adaptor
        recordingStartTime = startTime
        recordingCropRect = recordingGeometry.cropRect
        recordingRenderSize = recordingGeometry.renderSize
        recordingSourceCanvasSize = sourceCanvasSize
    }

    private func makeRenderedPixelBuffer(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard
            let pixelBufferPool = pixelBufferAdaptor?.pixelBufferPool
        else { return nil }

        var renderedPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &renderedPixelBuffer)
        guard status == kCVReturnSuccess, let renderedPixelBuffer else { return nil }

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let croppedImage = sourceImage
            .cropped(to: recordingCropRect)
            .transformed(by: CGAffineTransform(translationX: -recordingCropRect.origin.x, y: -recordingCropRect.origin.y))
        ciContext.render(croppedImage, to: renderedPixelBuffer)
        drawTrackedPlayers(
            on: renderedPixelBuffer,
            players: latestTrackedPlayers,
            cropRect: recordingCropRect,
            renderSize: recordingRenderSize,
            sourceCanvasSize: recordingSourceCanvasSize
        )
        return renderedPixelBuffer
    }

    private func drawTrackedPlayers(
        on pixelBuffer: CVPixelBuffer,
        players: [TrackedPlayerBox],
        cropRect: CGRect,
        renderSize: CGSize,
        sourceCanvasSize: CGSize
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return }

        context.setLineWidth(6)
        context.setFillColor(UIColor.systemGreen.cgColor)

        for player in players {
            let box = transformedBoundingBoxForRecordedFrame(from: player.boundingBox)
            let sourceRect = CGRect(
                x: box.origin.x * sourceCanvasSize.width,
                y: (1 - box.origin.y - box.height) * sourceCanvasSize.height,
                width: box.width * sourceCanvasSize.width,
                height: box.height * sourceCanvasSize.height
            )
            let rect = CGRect(
                x: sourceRect.origin.x - cropRect.origin.x,
                y: sourceRect.origin.y - cropRect.origin.y,
                width: sourceRect.width,
                height: sourceRect.height
            )
            context.setStrokeColor((player.isCurrentHitter ? UIColor.systemRed : UIColor.systemGreen).cgColor)
            context.stroke(rect.insetBy(dx: 1, dy: 1))

            let labelRect = CGRect(x: rect.minX, y: max(rect.minY - 34, 8), width: 120, height: 28)
            context.setFillColor(UIColor.systemGreen.cgColor)
            context.fill(labelRect)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.black
            ]
            drawVideoText(
                player.label,
                in: labelRect.insetBy(dx: 8, dy: 4),
                attributes: attributes,
                context: context,
                canvasHeight: height
            )
        }
    }

    private func transformedBoundingBoxForRecordedFrame(from orientedBoundingBox: CGRect) -> CGRect {
        orientedBoundingBox
    }

    private func makeRecordingGeometry(canvasSize: CGSize) -> (cropRect: CGRect, renderSize: CGSize) {
        let screenSize = UIScreen.main.bounds.size
        let targetAspect = max(screenSize.width, screenSize.height) / min(screenSize.width, screenSize.height)

        var cropWidth = canvasSize.width
        var cropHeight = canvasSize.height

        if cropWidth / cropHeight > targetAspect {
            cropWidth = floor((cropHeight * targetAspect) / 2) * 2
        } else {
            cropHeight = floor((cropWidth / targetAspect) / 2) * 2
        }

        let cropX = floor((canvasSize.width - cropWidth) / 2)
        let cropY = floor((canvasSize.height - cropHeight) / 2)
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        return (cropRect, CGSize(width: cropWidth, height: cropHeight))
    }

    private func drawVideoText(
        _ text: String,
        in rect: CGRect,
        attributes: [NSAttributedString.Key: Any],
        context: CGContext,
        canvasHeight: Int
    ) {
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(canvasHeight))
        context.scaleBy(x: 1, y: -1)

        let flippedRect = CGRect(
            x: rect.origin.x,
            y: CGFloat(canvasHeight) - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        UIGraphicsPushContext(context)
        NSString(string: text).draw(in: flippedRect, withAttributes: attributes)
        UIGraphicsPopContext()
        context.restoreGState()
    }

    private func finishRecording() {
        guard !isFinishingRecording else { return }
        isFinishingRecording = true

        guard let assetWriter else {
            finishStoppingSession(with: nil)
            return
        }

        assetWriterInput?.markAsFinished()
        let recordingURL = recordingURL
        let shouldSave = recordingDecision == .save

        assetWriter.finishWriting {
            self.sessionQueue.async {
                let status = assetWriter.status
                if status == .completed, shouldSave, let recordingURL {
                    self.finishStoppingSession(with: recordingURL)
                } else {
                    if let error = assetWriter.error {
                        print("Failed to finish writing video: \(error)")
                    }

                    if let recordingURL {
                        try? FileManager.default.removeItem(at: recordingURL)
                    }
                    self.finishStoppingSession(with: nil)
                }
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let trackedPlayers: [TrackedPlayerBox]
    let captureDevice: AVCaptureDevice?
    let calibrationPoints: [CGPoint]
    let completedCalibration: PlayerAreaCalibration?
    let isCalibrationEnabled: Bool
    let onCalibrationTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.setCaptureDevice(captureDevice)
        view.setCalibration(
            points: calibrationPoints,
            completedCalibration: completedCalibration,
            isEnabled: isCalibrationEnabled,
            onTap: onCalibrationTap
        )
        view.applyCurrentPreviewRotation()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.videoPreviewLayer.videoGravity = .resizeAspectFill
        uiView.setCaptureDevice(captureDevice)
        uiView.setCalibration(
            points: calibrationPoints,
            completedCalibration: completedCalibration,
            isEnabled: isCalibrationEnabled,
            onTap: onCalibrationTap
        )
        uiView.applyCurrentPreviewRotation()
        uiView.updateTrackedPlayers(trackedPlayers)
    }
}

final class PreviewView: UIView {
    private let overlayLayer = CALayer()
    private let tapGestureRecognizer = UITapGestureRecognizer()
    private var previewDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObserver: NSKeyValueObservation?
    private var calibrationPoints: [CGPoint] = []
    private var completedCalibration: PlayerAreaCalibration?
    private var calibrationTapHandler: ((CGPoint) -> Void)?
    private var isCalibrationEnabled = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        overlayLayer.masksToBounds = true
        layer.addSublayer(overlayLayer)
        tapGestureRecognizer.addTarget(self, action: #selector(handleCalibrationTap(_:)))
        addGestureRecognizer(tapGestureRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        rotationObserver?.invalidate()
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayLayer.frame = bounds
        applyCurrentPreviewRotation()
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func setCaptureDevice(_ device: AVCaptureDevice?) {
        guard previewDevice?.uniqueID != device?.uniqueID else { return }

        previewDevice = device
        rotationObserver?.invalidate()
        rotationObserver = nil
        rotationCoordinator = nil

        guard let device else { return }

        if #available(iOS 17.0, *) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
            rotationCoordinator = coordinator
            rotationObserver = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                self?.applyPreviewRotationAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
            }
        }
    }

    func setCalibration(
        points: [CGPoint],
        completedCalibration: PlayerAreaCalibration?,
        isEnabled: Bool,
        onTap: @escaping (CGPoint) -> Void
    ) {
        calibrationPoints = points
        self.completedCalibration = completedCalibration
        isCalibrationEnabled = isEnabled
        calibrationTapHandler = onTap
    }

    func applyCurrentPreviewRotation() {
        if #available(iOS 17.0, *), let rotationCoordinator {
            applyPreviewRotationAngle(rotationCoordinator.videoRotationAngleForHorizonLevelPreview)
        } else {
            applyPreviewRotationAngle(fallbackPreviewRotationAngle)
        }
    }

    private func applyPreviewRotationAngle(_ angle: CGFloat) {
        guard
            let connection = videoPreviewLayer.connection,
            connection.isVideoRotationAngleSupported(angle)
        else {
            return
        }

        connection.videoRotationAngle = angle
    }

    private var fallbackPreviewRotationAngle: CGFloat {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else {
            return 0
        }

        switch windowScene.interfaceOrientation {
        case .landscapeLeft:
            return 180
        case .landscapeRight:
            return 0
        case .portraitUpsideDown:
            return 270
        case .portrait, .unknown:
            return 90
        @unknown default:
            return 90
        }
    }

    func updateTrackedPlayers(_ players: [TrackedPlayerBox]) {
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        drawCalibrationOverlay()

        let positionedPlayers = players.compactMap { player -> (player: TrackedPlayerBox, rect: CGRect)? in
            let box = player.boundingBox
            let metadataRect = CGRect(
                x: box.origin.x,
                y: 1 - box.origin.y - box.size.height,
                width: box.size.width,
                height: box.size.height
            )
            let convertedRect = videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
            guard convertedRect.width > 0, convertedRect.height > 0 else { return nil }
            return (player, convertedRect)
        }
        .sorted { $0.rect.minX < $1.rect.minX }

        for (index, item) in positionedPlayers.enumerated() {
            let player = item.player
            let convertedRect = item.rect
            let displayLabel = index == 0 ? "Player1" : "Player2"
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = UIBezierPath(rect: convertedRect).cgPath
            shapeLayer.strokeColor = (player.isCurrentHitter ? UIColor.systemRed : UIColor.systemGreen).cgColor
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.lineWidth = 3
            shapeLayer.cornerRadius = 12
            overlayLayer.addSublayer(shapeLayer)

            let labelFrame = CGRect(
                x: convertedRect.minX,
                y: max(convertedRect.minY - 28, 8),
                width: 92,
                height: 22
            )
            let textLayer = CATextLayer()
            textLayer.string = displayLabel
            textLayer.font = UIFont.boldSystemFont(ofSize: 16)
            textLayer.fontSize = 16
            textLayer.alignmentMode = .left
            textLayer.foregroundColor = UIColor.black.cgColor
            textLayer.backgroundColor = UIColor.systemGreen.cgColor
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.cornerRadius = 6
            textLayer.frame = labelFrame
            overlayLayer.addSublayer(textLayer)
        }
    }

    @objc private func handleCalibrationTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, isCalibrationEnabled else { return }

        let tapLocation = recognizer.location(in: self)
        guard bounds.contains(tapLocation) else { return }
        let capturePoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: tapLocation)
        calibrationTapHandler?(capturePoint)
    }

    private func drawCalibrationOverlay() {
        let pointsToDraw = completedCalibration?.orderedPoints ?? calibrationPoints
        let layerPoints = pointsToDraw.map { videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: $0) }
        guard !layerPoints.isEmpty else { return }

        let path = UIBezierPath()
        if let firstPoint = layerPoints.first {
            path.move(to: firstPoint)
            for point in layerPoints.dropFirst() {
                path.addLine(to: point)
            }
            if completedCalibration != nil, layerPoints.count == 4 {
                path.close()
            }
        }

        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = UIColor.systemYellow.cgColor
        shapeLayer.fillColor = UIColor.systemYellow.withAlphaComponent(completedCalibration == nil ? 0.04 : 0.08).cgColor
        shapeLayer.lineWidth = 3
        shapeLayer.lineDashPattern = completedCalibration == nil ? [8, 6] : nil
        overlayLayer.addSublayer(shapeLayer)

        for (index, point) in layerPoints.enumerated() {
            let markerSize: CGFloat = 22
            let markerFrame = CGRect(
                x: point.x - (markerSize / 2),
                y: point.y - (markerSize / 2),
                width: markerSize,
                height: markerSize
            )

            let markerLayer = CAShapeLayer()
            markerLayer.path = UIBezierPath(ovalIn: markerFrame).cgPath
            markerLayer.fillColor = UIColor.systemYellow.cgColor
            overlayLayer.addSublayer(markerLayer)

            let textLayer = CATextLayer()
            textLayer.string = "\(index + 1)"
            textLayer.font = UIFont.boldSystemFont(ofSize: 13)
            textLayer.fontSize = 13
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = UIColor.black.cgColor
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.frame = markerFrame.offsetBy(dx: 0, dy: 3)
            overlayLayer.addSublayer(textLayer)
        }
    }
}

#Preview {
    ContentView()
}
