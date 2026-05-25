import SwiftUI
import AVFoundation
import AVKit
import Photos
import PhotosUI
import UIKit
import Vision
import CoreTransferable
import UniformTypeIdentifiers

private enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    var displayName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

private let appLanguageStorageKey = "appLanguage"

private func localized(_ language: AppLanguage, zh: String, en: String) -> String {
    switch language {
    case .chinese:
        return zh
    case .english:
        return en
    }
}

enum PlayerHandednessMode: String, Codable, CaseIterable {
    case rightRight
    case leftRight

    fileprivate func title(in language: AppLanguage) -> String {
        switch self {
        case .rightRight:
            return "Right/Right"
        case .leftRight:
            return "Left/Right"
        }
    }
}

enum LiveFeedbackMode: String, CaseIterable {
    case duringRally
    case afterRally

    fileprivate func title(in language: AppLanguage) -> String {
        switch self {
        case .duringRally:
            return localized(language, zh: "During rally", en: "During rally")
        case .afterRally:
            return localized(language, zh: "After rally", en: "After rally")
        }
    }
}

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var videoLibrary = VideoLibraryManager()
    @AppStorage(appLanguageStorageKey) private var appLanguageRawValue = AppLanguage.chinese.rawValue

    @State private var isCoachingMode = false
    @State private var permissionMessage: String?
    @State private var isVideoLibraryPresented = false
    @State private var isClosingSession = false
    @State private var showSaveRecordingDialog = false
    @State private var isWaitingForLandscapeRecording = false
    @State private var calibrationPoints: [CGPoint] = []
    @State private var showLanguagePicker = false
    @State private var showHandednessPicker = false
    @State private var showFeedbackModePicker = false
    @State private var pendingHandednessMode: PlayerHandednessMode?

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .chinese
    }

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

                ProgressView(localized(appLanguage, zh: "處理錄影中...", en: "Processing recording..."))
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .foregroundStyle(.white)
            }
        }
        .environment(\.locale, Locale(identifier: appLanguage.rawValue))
        .alert(localized(appLanguage, zh: "無法開啟相機", en: "Unable to Open Camera"), isPresented: Binding(
            get: { permissionMessage != nil },
            set: { isPresented in
                if !isPresented {
                    permissionMessage = nil
                }
            }
        )) {
            Button(localized(appLanguage, zh: "確定", en: "OK"), role: .cancel) { }
        } message: {
            Text(permissionMessage ?? "")
        }
        .confirmationDialog(localized(appLanguage, zh: "是否儲存本次錄影？", en: "Save this recording?"), isPresented: $showSaveRecordingDialog, titleVisibility: .visible) {
            Button(localized(appLanguage, zh: "儲存", en: "Save")) {
                closeCoachingMode(saveRecording: true)
            }

            Button(localized(appLanguage, zh: "不儲存", en: "Don't Save"), role: .destructive) {
                closeCoachingMode(saveRecording: false)
            }

            Button(localized(appLanguage, zh: "取消", en: "Cancel"), role: .cancel) { }
        } message: {
            Text(localized(appLanguage, zh: "關閉教練模式前，選擇是否保留剛剛錄下的影片。", en: "Choose whether to keep the video you just recorded before leaving coaching mode."))
        }
        .confirmationDialog(localized(appLanguage, zh: "選擇語言", en: "Choose Language"), isPresented: $showLanguagePicker, titleVisibility: .visible) {
            ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                Button(language.displayName) {
                    appLanguageRawValue = language.rawValue
                }
            }

            Button(localized(appLanguage, zh: "取消", en: "Cancel"), role: .cancel) { }
        }
        .confirmationDialog(localized(appLanguage, zh: "請選擇球員慣用手", en: "Choose Players' Dominant Hands"), isPresented: $showHandednessPicker, titleVisibility: .visible) {
            ForEach(PlayerHandednessMode.allCases, id: \.rawValue) { mode in
                Button(mode.title(in: appLanguage)) {
                    pendingHandednessMode = mode
                    showFeedbackModePicker = true
                }
            }

            Button(localized(appLanguage, zh: "取消", en: "Cancel"), role: .cancel) { }
        }
        .confirmationDialog(localized(appLanguage, zh: "請選擇 feedback 時機", en: "Choose Feedback Timing"), isPresented: $showFeedbackModePicker, titleVisibility: .visible) {
            ForEach(LiveFeedbackMode.allCases, id: \.rawValue) { mode in
                Button(mode.title(in: appLanguage)) {
                    guard let pendingHandednessMode else { return }
                    startCoachingMode(with: pendingHandednessMode, feedbackMode: mode)
                }
            }

            Button(localized(appLanguage, zh: "取消", en: "Cancel"), role: .cancel) {
                pendingHandednessMode = nil
            }
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
                HStack {
                    Spacer()

                    Button {
                        showLanguagePicker = true
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.14))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                Text("TT-Coach")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)

                Text(localized(appLanguage, zh: "桌球雙打語音教練", en: "Table Tennis Doubles Audio Coach"))
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.85))

                Spacer()

                Button {
                    showHandednessPicker = true
                } label: {
                    Text(localized(appLanguage, zh: "開始", en: "Start"))
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
                    Label(localized(appLanguage, zh: "已儲存影片", en: "Saved Videos"), systemImage: "film.stack")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 32)

                Text(localized(appLanguage, zh: "按下開始後會開啟相機、進入 AI 教練模式；若手機直放，會提示先橫放再開始錄影", en: "Tap Start to open the camera and enter AI coaching mode. If the phone is vertical, the app will ask you to rotate to landscape before recording starts."))
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
                            if cameraManager.isRecordingActive {
                                TrackingDebugPanel(
                                    debugInfo: cameraManager.trackingDebugInfo,
                                    rallyState: cameraManager.rallyState,
                                    spatialStatus: cameraManager.playerAreaSpatialStatus,
                                    calibrationStatus: isCalibrationComplete
                                        ? localized(appLanguage, zh: "已完成", en: "ready")
                                        : localized(appLanguage, zh: "未完成", en: "pending")
                                )
                            }
                            if cameraManager.selectedLiveFeedbackMode == .afterRally {
                                AfterRallyDebugPanel(items: cameraManager.afterRallyDebugItems)
                            }
                        }

                        Spacer()

                        HStack(spacing: 12) {
                            if !cameraManager.isRecordingActive {
                                Button {
                                    resetCalibration()
                                } label: {
                                    Label(localized(appLanguage, zh: "重設標定", en: "Reset Calibration"), systemImage: "arrow.counterclockwise")
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

                    Spacer(minLength: 0)
                }

                if isWaitingForLandscapeRecording {
                    VStack {
                        Spacer()

                        VStack(spacing: 10) {
                            Text(localized(appLanguage, zh: "請把手機水平放置", en: "Rotate Phone to Landscape"))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)

                            Text(localized(appLanguage, zh: "偵測到目前是直式，轉成橫式後會自動開始錄影。", en: "Portrait orientation detected. Recording will start automatically after you rotate to landscape."))
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
                    .allowsHitTesting(false)
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
        isCalibrationComplete
            ? localized(appLanguage, zh: "已標定", en: "Calibrated")
            : localized(appLanguage, zh: "第 \(calibrationPoints.count)/3 點", en: "Point \(calibrationPoints.count)/3")
    }

    private var recordingBadgeLabel: String {
        if cameraManager.isRecordingActive {
            return "REC"
        }
        if isWaitingForLandscapeRecording {
            return localized(appLanguage, zh: "等待橫放", en: "Waiting for Landscape")
        }
        if !isCalibrationComplete {
            return localized(appLanguage, zh: "等待標定", en: "Waiting for Calibration")
        }
        return localized(appLanguage, zh: "待命", en: "Standby")
    }

    private var recordingBadgeColor: Color {
        if cameraManager.isRecordingActive {
            return .red
        }
        return .orange
    }

    private var calibrationHeadline: String {
        if let nextCorner = CalibrationCorner(rawValue: calibrationPoints.count) {
            return localized(appLanguage, zh: "請點選球桌前緣的\(nextCorner.title(in: appLanguage))", en: "Tap the \(nextCorner.title(in: appLanguage)) point on the table front edge")
        }
        return localized(appLanguage, zh: "球桌前緣標定完成", en: "Table Front Edge Calibration Complete")
    }

    private var calibrationDetail: String {
        if isCalibrationComplete {
            return localized(appLanguage, zh: "已建立以球桌前緣為基準的座標，可開始錄影。", en: "The table-front coordinate system is ready. Recording can start.")
        }
        return localized(appLanguage, zh: "依序點選球桌前緣最左點、中間點、最右點。中間點會是座標 0,0；左點是 -1,0；右點是 1,0，左右點也會作為擊球區邊界。", en: "Tap the left point, center point, and right point along the table front edge. The center becomes coordinate 0,0; the left point is -1,0; and the right point is 1,0. The left and right points also define the hitting-zone boundaries.")
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
        guard calibrationPoints.count < 3 else { return }

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

    private func startCoachingMode(with handednessMode: PlayerHandednessMode, feedbackMode: LiveFeedbackMode) {
        resetCalibration()
        pendingHandednessMode = nil
        cameraManager.requestPermissionAndStart(handednessMode: handednessMode, feedbackMode: feedbackMode) { started in
            if started {
                isCoachingMode = true
            } else {
                permissionMessage = localized(appLanguage, zh: "請先允許相機與麥克風權限，才能進入 AI 教練模式。", en: "Please allow camera and microphone access before entering AI coaching mode.")
            }
        }
    }

    private func closeCoachingMode(saveRecording: Bool) {
        isClosingSession = true
        isWaitingForLandscapeRecording = false

        cameraManager.stopSession(saveRecording: saveRecording) { output in
            if let output, let savedVideo = videoLibrary.saveRecordedVideo(from: output) {
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
            Text("source: \(debugInfo.source)")
            Text("rectangles: \(debugInfo.rectangleCandidates)  bodyPose: \(debugInfo.bodyPoseCandidates)")
            Text("selected: \(debugInfo.selectedCandidates)  tracked: \(debugInfo.trackedPlayers)")
            Text("missed: \(debugInfo.missedFrames)")

            Divider()
                .background(Color.white.opacity(0.35))

            if debugInfo.trackedSummaries.isEmpty {
                Text("Player1: no point")
                Text("Player2: no point")
            } else {
                ForEach(debugInfo.trackedSummaries, id: \.self) { summary in
                    Text(summary)
                }
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

private func cameraProximityScore(for boundingBox: CGRect) -> CGFloat {
    let footPoint = normalizedPlayerFootPoint(for: boundingBox)
    let areaScore = boundingBox.width * boundingBox.height
    let heightScore = boundingBox.height
    let footlineScore = footPoint.y
    return (footlineScore * 1.8) + (heightScore * 0.9) + (areaScore * 0.4)
}

private func isForegroundPlayerBox(_ boundingBox: CGRect, nearestFootline: CGFloat, largestHeight: CGFloat, largestArea: CGFloat) -> Bool {
    let footline = normalizedPlayerFootPoint(for: boundingBox).y
    let area = boundingBox.width * boundingBox.height
    return footline >= nearestFootline - 0.12 &&
        boundingBox.height >= largestHeight * 0.55 &&
        area >= largestArea * 0.38
}

private func isFallbackForegroundPlayerBox(_ boundingBox: CGRect, nearestFootline: CGFloat, largestHeight: CGFloat, largestArea: CGFloat) -> Bool {
    let footline = normalizedPlayerFootPoint(for: boundingBox).y
    let area = boundingBox.width * boundingBox.height
    return footline >= nearestFootline - 0.16 &&
        boundingBox.height >= largestHeight * 0.45 &&
        area >= largestArea * 0.28
}

private func normalizedPlayerFootPoint(for boundingBox: CGRect) -> CGPoint {
    CGPoint(
        x: min(max(boundingBox.midX, 0), 1),
        y: min(max(1 - boundingBox.minY, 0), 1)
    )
}

private func fallbackCourtMapPoint(for boundingBox: CGRect) -> CGPoint {
    let footPoint = normalizedPlayerFootPoint(for: boundingBox)

    // Review-mode videos do not have a calibrated player-area homography, so
    // apply a simple perspective compensation to place players closer to the
    // table when they appear higher in the camera frame.
    let adjustedDepth = pow(footPoint.y, 2.1) * 1.6
    return CGPoint(
        x: (footPoint.x - 0.5) * 2.4,
        y: max(adjustedDepth, 0)
    )
}

private func selectNearestTwoPlayerBoxes(from boundingBoxes: [CGRect]) -> [CGRect] {
    let sortedByProximity = boundingBoxes.sorted { lhs, rhs in
        let lhsScore = cameraProximityScore(for: lhs)
        let rhsScore = cameraProximityScore(for: rhs)
        if lhsScore == rhsScore {
            return lhs.midX < rhs.midX
        }
        return lhsScore > rhsScore
    }

    guard
        let nearestFootline = sortedByProximity.first.map({ normalizedPlayerFootPoint(for: $0).y }),
        let largestHeight = sortedByProximity.map(\.height).max(),
        let largestArea = sortedByProximity.map({ $0.width * $0.height }).max()
    else {
        return []
    }

    let foregroundCandidates = sortedByProximity.filter {
        isForegroundPlayerBox($0, nearestFootline: nearestFootline, largestHeight: largestHeight, largestArea: largestArea)
    }

    let selectedBoxes: [CGRect]
    if foregroundCandidates.count >= 2 {
        selectedBoxes = Array(foregroundCandidates.prefix(2))
    } else if foregroundCandidates.count == 1 {
        let primaryBox = foregroundCandidates[0]
        let fallbackSecondBox = sortedByProximity.first { candidate in
            candidate != primaryBox &&
                isFallbackForegroundPlayerBox(
                    candidate,
                    nearestFootline: nearestFootline,
                    largestHeight: largestHeight,
                    largestArea: largestArea
                )
        }
        selectedBoxes = [primaryBox] + Array([fallbackSecondBox].compactMap { $0 }.prefix(1))
    } else {
        selectedBoxes = Array(sortedByProximity.prefix(2))
    }

    return selectedBoxes.sorted { $0.midX < $1.midX }
}

private struct StableAssignmentCandidate {
    let players: [TrackedPlayerBox]
    let score: CGFloat
}

private func stablePlayerInitialization(from boundingBoxes: [CGRect]) -> [TrackedPlayerBox] {
    zip(
        boundingBoxes.sorted { $0.midX < $1.midX }.prefix(2),
        ["Player1", "Player2"]
    ).map { boundingBox, label in
        TrackedPlayerBox(id: label, label: label, boundingBox: boundingBox)
    }
}

private func trackingCenterDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
}

private func trackingIoU(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    let intersectionArea = max(intersection.width, 0) * max(intersection.height, 0)
    let unionArea = (lhs.width * lhs.height) + (rhs.width * rhs.height) - intersectionArea
    return unionArea > 0 ? intersectionArea / unionArea : 0
}

private func playerTrackingContinuityScore(previous: CGRect, candidate: CGRect) -> CGFloat {
    let centerDistance = trackingCenterDistance(previous, candidate)
    let distanceScore = max(0, 1 - (centerDistance / 0.28))
    let iouScore = trackingIoU(previous, candidate)
    let areaDelta = abs((previous.width * previous.height) - (candidate.width * candidate.height))
    let areaScore = max(0, 1 - (areaDelta / 0.08))
    return (distanceScore * 0.55) + (iouScore * 0.3) + (areaScore * 0.15)
}

private func shouldLockPlayerIdentities(previousPlayers: [TrackedPlayerBox], candidateBoxes: [CGRect]) -> Bool {
    guard previousPlayers.count == 2, candidateBoxes.count == 2 else { return false }

    let previousSpacing = abs(previousPlayers[0].boundingBox.midX - previousPlayers[1].boundingBox.midX)
    let candidateSpacing = abs(candidateBoxes[0].midX - candidateBoxes[1].midX)
    let overlapAmount = max(
        min(candidateBoxes[0].maxX, candidateBoxes[1].maxX) - max(candidateBoxes[0].minX, candidateBoxes[1].minX),
        0
    )
    let closeInteraction = candidateSpacing < 0.16 || previousSpacing < 0.16 || overlapAmount > 0.025

    let keepOrderScore = playerTrackingContinuityScore(previous: previousPlayers[0].boundingBox, candidate: candidateBoxes[0]) +
        playerTrackingContinuityScore(previous: previousPlayers[1].boundingBox, candidate: candidateBoxes[1])
    let swapOrderScore = playerTrackingContinuityScore(previous: previousPlayers[0].boundingBox, candidate: candidateBoxes[1]) +
        playerTrackingContinuityScore(previous: previousPlayers[1].boundingBox, candidate: candidateBoxes[0])

    return closeInteraction && abs(keepOrderScore - swapOrderScore) < 0.18
}

private func stableTrackedPlayers(
    previousPlayers: [TrackedPlayerBox],
    candidateBoxes: [CGRect]
) -> [TrackedPlayerBox] {
    let sortedCandidates = Array(candidateBoxes.sorted { $0.midX < $1.midX }.prefix(2))

    guard previousPlayers.count == 2 else {
        return stablePlayerInitialization(from: sortedCandidates)
    }

    guard !sortedCandidates.isEmpty else {
        return previousPlayers
    }

    if sortedCandidates.count == 1 {
        let onlyCandidate = sortedCandidates[0]
        let matchedPlayer = previousPlayers.max {
            playerTrackingContinuityScore(previous: $0.boundingBox, candidate: onlyCandidate) <
                playerTrackingContinuityScore(previous: $1.boundingBox, candidate: onlyCandidate)
        }

        return previousPlayers.map { previousPlayer in
            guard previousPlayer.id == matchedPlayer?.id else { return previousPlayer }
            let continuityScore = playerTrackingContinuityScore(previous: previousPlayer.boundingBox, candidate: onlyCandidate)
            if continuityScore < 0.2 {
                return previousPlayer
            }
            return TrackedPlayerBox(id: previousPlayer.id, label: previousPlayer.label, boundingBox: onlyCandidate)
        }
    }

    if shouldLockPlayerIdentities(previousPlayers: previousPlayers, candidateBoxes: sortedCandidates) {
        return previousPlayers
    }

    let assignmentOrders = [
        [sortedCandidates[0], sortedCandidates[1]],
        [sortedCandidates[1], sortedCandidates[0]]
    ]

    let rankedAssignments = assignmentOrders.map { orderedBoxes -> StableAssignmentCandidate in
        let assignedPlayers = zip(previousPlayers, orderedBoxes).map { previousPlayer, candidateBox in
            TrackedPlayerBox(id: previousPlayer.id, label: previousPlayer.label, boundingBox: candidateBox)
        }
        let score = zip(previousPlayers, orderedBoxes).reduce(CGFloat.zero) { partial, pair in
            partial + playerTrackingContinuityScore(previous: pair.0.boundingBox, candidate: pair.1)
        }
        return StableAssignmentCandidate(players: assignedPlayers, score: score)
    }

    let bestAssignment = rankedAssignments.max { $0.score < $1.score } ?? rankedAssignments[0]

    return zip(previousPlayers, bestAssignment.players).map { previousPlayer, assignedPlayer in
        let continuityScore = playerTrackingContinuityScore(previous: previousPlayer.boundingBox, candidate: assignedPlayer.boundingBox)
        let jumpDistance = trackingCenterDistance(previousPlayer.boundingBox, assignedPlayer.boundingBox)
        let candidateIoU = trackingIoU(previousPlayer.boundingBox, assignedPlayer.boundingBox)

        if continuityScore < 0.16 || (jumpDistance > 0.32 && candidateIoU < 0.03) {
            return previousPlayer
        }

        return assignedPlayer
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

struct AfterRallyDebugItem: Identifiable, Hashable {
    let code: Int
    let label: String

    var id: Int { code }
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
    case moveLeft = "Move left."
    case moveRight = "Move right."
    case rallyStart = "Rally start."
    case rallyEnd = "Rally end."
}

private final class RallyFeedbackSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    static func estimatedDuration(for feedback: [String]) -> CFTimeInterval {
        guard !feedback.isEmpty else { return 0 }

        let wordCount = feedback.reduce(0) { total, item in
            total + item.split { $0.isWhitespace || $0.isNewline }.count
        }
        let countBasedDuration = (Double(feedback.count) * 2.1) + 0.4
        let wordBasedDuration = (Double(wordCount) * 0.42) + 0.8
        return max(countBasedDuration, wordBasedDuration)
    }

    @discardableResult
    func speak(_ feedback: [String]) -> CFTimeInterval {
        guard !feedback.isEmpty else { return 0 }

        let estimatedDuration = Self.estimatedDuration(for: feedback)

        DispatchQueue.main.async {
            self.activateAudioSessionIfPossible()
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            for item in feedback {
                let utterance = AVSpeechUtterance(string: item)
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
    case leftEdge
    case center
    case rightEdge

    fileprivate func title(in language: AppLanguage) -> String {
        switch self {
        case .leftEdge:
            return localized(language, zh: "最左點", en: "left point")
        case .center:
            return localized(language, zh: "中間點", en: "center point")
        case .rightEdge:
            return localized(language, zh: "最右點", en: "right point")
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
    let leftPoint: CGPoint
    let centerPoint: CGPoint
    let rightPoint: CGPoint
    private let axisX: CGPoint
    private let axisY: CGPoint
    private let halfWidth: CGFloat

    init?(points: [CGPoint]) {
        guard points.count == 3 else { return nil }
        self.init(leftPoint: points[0], centerPoint: points[1], rightPoint: points[2])
    }

    init?(leftPoint: CGPoint, centerPoint: CGPoint, rightPoint: CGPoint) {
        let spanVector = CGPoint(x: rightPoint.x - leftPoint.x, y: rightPoint.y - leftPoint.y)
        let spanLength = hypot(spanVector.x, spanVector.y)
        guard spanLength > 0.0001 else { return nil }

        let normalizedAxisX = CGPoint(x: spanVector.x / spanLength, y: spanVector.y / spanLength)
        let candidateNormalA = CGPoint(x: -normalizedAxisX.y, y: normalizedAxisX.x)
        let candidateNormalB = CGPoint(x: normalizedAxisX.y, y: -normalizedAxisX.x)
        let chosenAxisY = candidateNormalA.y >= candidateNormalB.y ? candidateNormalA : candidateNormalB

        self.leftPoint = leftPoint
        self.centerPoint = centerPoint
        self.rightPoint = rightPoint
        self.axisX = normalizedAxisX
        self.axisY = chosenAxisY
        self.halfWidth = spanLength / 2
    }

    var orderedPoints: [CGPoint] {
        [leftPoint, centerPoint, rightPoint]
    }

    func normalizedPoint(forCapturePoint point: CGPoint) -> CGPoint? {
        guard halfWidth > 0.0001 else { return nil }

        let delta = CGPoint(x: point.x - centerPoint.x, y: point.y - centerPoint.y)
        let mappedX = ((delta.x * axisX.x) + (delta.y * axisX.y)) / halfWidth
        let mappedY = max(((delta.x * axisY.x) + (delta.y * axisY.y)) / halfWidth, 0)

        guard mappedX.isFinite, mappedY.isFinite else { return nil }
        return CGPoint(x: mappedX, y: mappedY)
    }
}

struct SavedVideo: Identifiable, Hashable {
    let url: URL
    let createdAt: Date

    var id: URL { url }

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }

    var trackingDataURL: URL {
        Self.trackingDataURL(forVideoURL: url)
    }

    static func trackingDataURL(forVideoURL videoURL: URL) -> URL {
        videoURL.deletingPathExtension().appendingPathExtension("tracking.json")
    }
}

private struct RecordedSessionOutput {
    let videoURL: URL
    let trackingDataURL: URL?
}

struct RallyInterval: Identifiable, Codable, Hashable {
    let startTime: Double
    let endTime: Double

    var id: String {
        "\(startTime)-\(endTime)"
    }
}

private struct TrackingSidecarFile: Codable {
    let frames: [TrackingSidecarFrame]
    let rallyIntervals: [RallyInterval]
    let feedbackEvents: [TrackingSidecarFeedbackEvent]
    let handednessMode: PlayerHandednessMode

    init(
        frames: [TrackingSidecarFrame],
        rallyIntervals: [RallyInterval],
        feedbackEvents: [TrackingSidecarFeedbackEvent],
        handednessMode: PlayerHandednessMode
    ) {
        self.frames = frames
        self.rallyIntervals = rallyIntervals
        self.feedbackEvents = feedbackEvents
        self.handednessMode = handednessMode
    }

    private enum CodingKeys: String, CodingKey {
        case frames
        case rallyIntervals
        case feedbackEvents
        case handednessMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frames = try container.decode([TrackingSidecarFrame].self, forKey: .frames)
        rallyIntervals = try container.decodeIfPresent([RallyInterval].self, forKey: .rallyIntervals) ?? []
        feedbackEvents = try container.decodeIfPresent([TrackingSidecarFeedbackEvent].self, forKey: .feedbackEvents) ?? []
        handednessMode = try container.decodeIfPresent(PlayerHandednessMode.self, forKey: .handednessMode) ?? .rightRight
    }
}

private struct TrackingSidecarFeedbackEvent: Codable, Hashable {
    let kind: String
    let playerLabel: String
    let startTime: Double
    let endTime: Double
}

private struct TrackingSidecarFrame: Codable {
    let time: Double
    let players: [TrackingSidecarPlayer]

    init(frame: PlayerTrackFrame) {
        self.time = frame.time
        self.players = frame.players.map(TrackingSidecarPlayer.init)
    }

    func playerTrackFrame() -> PlayerTrackFrame {
        PlayerTrackFrame(
            time: time,
            players: players.map { $0.trackedPlayerBox() }
        )
    }
}

private struct TrackingSidecarPlayer: Codable {
    let id: String
    let label: String
    let boundingBoxX: Double
    let boundingBoxY: Double
    let boundingBoxWidth: Double
    let boundingBoxHeight: Double
    let footPointX: Double?
    let footPointY: Double?
    let playerAreaPointX: Double?
    let playerAreaPointY: Double?
    let lateralPosition: String?
    let depthPosition: String?
    let isCurrentHitter: Bool

    init(player: TrackedPlayerBox) {
        self.id = player.id
        self.label = player.label
        self.boundingBoxX = player.boundingBox.origin.x
        self.boundingBoxY = player.boundingBox.origin.y
        self.boundingBoxWidth = player.boundingBox.size.width
        self.boundingBoxHeight = player.boundingBox.size.height
        self.footPointX = player.footPoint.map { Double($0.x) }
        self.footPointY = player.footPoint.map { Double($0.y) }
        self.playerAreaPointX = player.playerAreaPoint.map { Double($0.x) }
        self.playerAreaPointY = player.playerAreaPoint.map { Double($0.y) }
        self.lateralPosition = player.lateralPosition
        self.depthPosition = player.depthPosition
        self.isCurrentHitter = player.isCurrentHitter
    }

    func trackedPlayerBox() -> TrackedPlayerBox {
        TrackedPlayerBox(
            id: id,
            label: label,
            boundingBox: CGRect(
                x: boundingBoxX,
                y: boundingBoxY,
                width: boundingBoxWidth,
                height: boundingBoxHeight
            ),
            footPoint: point(x: footPointX, y: footPointY),
            playerAreaPoint: point(x: playerAreaPointX, y: playerAreaPointY),
            lateralPosition: lateralPosition,
            depthPosition: depthPosition,
            isCurrentHitter: isCurrentHitter
        )
    }

    private func point(x: Double?, y: Double?) -> CGPoint? {
        guard let x, let y else { return nil }
        return CGPoint(x: x, y: y)
    }
}

private struct ImportedReviewVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)

            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }

            try FileManager.default.copyItem(at: received.file, to: temporaryURL)
            return ImportedReviewVideo(url: temporaryURL)
        }
    }
}

struct ReviewSession {
    let video: SavedVideo
    let duration: Double
    let trackFrames: [PlayerTrackFrame]
    let rallyIntervals: [RallyInterval]
    let handednessMode: PlayerHandednessMode
    let movementEvents: [MovementEvent]
    let suggestions: [ReviewSuggestion]
}

struct PlayerTrackFrame: Identifiable, Hashable {
    let id = UUID()
    let time: Double
    let players: [TrackedPlayerBox]
}

private func normalizedTrackFrameTimes(_ frames: [PlayerTrackFrame]) -> [PlayerTrackFrame] {
    guard let firstTime = frames.first(where: { $0.time.isFinite })?.time else {
        return frames
    }

    return frames.map { frame in
        PlayerTrackFrame(
            time: max(frame.time - firstTime, 0),
            players: frame.players
        )
    }
}

private struct CourtMapJumpFilterState {
    var acceptedPoint: CGPoint
    var pendingPoint: CGPoint?
    var pendingCount = 0
}

private func limitedStepPoint(from current: CGPoint, toward target: CGPoint, maxStep: CGFloat) -> CGPoint {
    let deltaX = target.x - current.x
    let deltaY = target.y - current.y
    let distance = hypot(deltaX, deltaY)
    guard distance > 0.0001 else { return target }
    guard distance > maxStep else { return target }

    let scale = maxStep / distance
    return CGPoint(
        x: current.x + (deltaX * scale),
        y: current.y + (deltaY * scale)
    )
}

private func filteredCourtMapFrames(from frames: [PlayerTrackFrame]) -> [PlayerTrackFrame] {
    var filterStates: [String: CourtMapJumpFilterState] = [:]
    let jumpFilteredFrames = frames.map { frame in
        let filteredPlayers = frame.players.map { player in
            guard let point = player.playerAreaPoint else { return player }

            let filteredPoint: CGPoint
            if var state = filterStates[player.id] {
                let jumpDistance = hypot(point.x - state.acceptedPoint.x, point.y - state.acceptedPoint.y)
                if jumpDistance <= 0.24 {
                    state.acceptedPoint = point
                    state.pendingPoint = nil
                    state.pendingCount = 0
                    filteredPoint = point
                } else if jumpDistance <= 0.5 {
                    // Preserve continuous movement while still damping abrupt drift.
                    state.acceptedPoint = limitedStepPoint(from: state.acceptedPoint, toward: point, maxStep: 0.18)
                    state.pendingPoint = nil
                    state.pendingCount = 0
                    filteredPoint = state.acceptedPoint
                } else {
                    let blendedPendingPoint: CGPoint
                    if let pendingPoint = state.pendingPoint {
                        blendedPendingPoint = CGPoint(
                            x: (pendingPoint.x + point.x) / 2,
                            y: (pendingPoint.y + point.y) / 2
                        )
                        state.pendingCount += 1
                    } else {
                        blendedPendingPoint = point
                        state.pendingCount = 1
                    }

                    state.pendingPoint = blendedPendingPoint
                    if state.pendingCount >= 2 {
                        state.acceptedPoint = limitedStepPoint(
                            from: state.acceptedPoint,
                            toward: blendedPendingPoint,
                            maxStep: 0.22
                        )
                        state.pendingPoint = nil
                        state.pendingCount = 0
                        filteredPoint = state.acceptedPoint
                    } else {
                        filteredPoint = state.acceptedPoint
                    }
                }
                filterStates[player.id] = state
            } else {
                filterStates[player.id] = CourtMapJumpFilterState(acceptedPoint: point)
                filteredPoint = point
            }

            return TrackedPlayerBox(
                id: player.id,
                label: player.label,
                boundingBox: player.boundingBox,
                footPoint: player.footPoint,
                playerAreaPoint: filteredPoint,
                lateralPosition: player.lateralPosition,
                depthPosition: player.depthPosition,
                isCurrentHitter: player.isCurrentHitter
            )
        }

        return PlayerTrackFrame(time: frame.time, players: filteredPlayers)
    }

    return interpolateCourtMapFramesRemovingFrontInvalidPoints(from: jumpFilteredFrames)
}

private func interpolateCourtMapFramesRemovingFrontInvalidPoints(from frames: [PlayerTrackFrame]) -> [PlayerTrackFrame] {
    guard let frontLimitY = courtMapFrontLimitY(from: frames) else {
        return frames
    }

    let playerIDs = Array(
        Set(frames.flatMap { $0.players.map(\.id) })
    ).sorted()

    var overriddenPointsByFrameIndex: [Int: [String: CGPoint]] = [:]

    for playerID in playerIDs {
        let indexedPoints = frames.enumerated().compactMap { index, frame -> (Int, CGPoint)? in
            guard
                let player = frame.players.first(where: { $0.id == playerID }),
                let point = player.playerAreaPoint
            else {
                return nil
            }
            return (index, point)
        }

        guard !indexedPoints.isEmpty else { continue }

        var validIndicesAndPoints: [(Int, CGPoint)] = []
        let invalidIndices = indexedPoints.compactMap { index, point in
            point.y < frontLimitY ? index : nil
        }

        for (index, point) in indexedPoints where point.y >= frontLimitY {
            validIndicesAndPoints.append((index, point))
        }

        for invalidIndex in invalidIndices {
            guard
                let previousValid = validIndicesAndPoints.last(where: { $0.0 < invalidIndex }),
                let nextValid = validIndicesAndPoints.first(where: { $0.0 > invalidIndex })
            else {
                continue
            }

            let frameSpan = nextValid.0 - previousValid.0
            guard frameSpan > 0 else { continue }

            let progress = CGFloat(invalidIndex - previousValid.0) / CGFloat(frameSpan)
            let interpolatedPoint = CGPoint(
                x: previousValid.1.x + ((nextValid.1.x - previousValid.1.x) * progress),
                y: previousValid.1.y + ((nextValid.1.y - previousValid.1.y) * progress)
            )
            overriddenPointsByFrameIndex[invalidIndex, default: [:]][playerID] = interpolatedPoint
        }
    }

    return frames.enumerated().map { index, frame in
        guard let overriddenPoints = overriddenPointsByFrameIndex[index] else {
            return frame
        }

        let players = frame.players.map { player in
            guard let point = overriddenPoints[player.id] else { return player }
            return player.updatingPlayerAreaPoint(point)
        }
        return PlayerTrackFrame(time: frame.time, players: players)
    }
}

private func courtMapFrontLimitY(from frames: [PlayerTrackFrame]) -> CGFloat? {
    for frame in frames {
        if let hitter = frame.players.first(where: { $0.isCurrentHitter }),
           let point = hitter.playerAreaPoint {
            return point.y
        }
    }

    for frame in frames {
        let points = frame.players.compactMap(\.playerAreaPoint)
        if let fallbackFrontPlayer = points.min(by: { $0.y < $1.y }) {
            return fallbackFrontPlayer.y
        }
    }

    return nil
}

private extension TrackedPlayerBox {
    func updatingPlayerAreaPoint(_ point: CGPoint) -> TrackedPlayerBox {
        TrackedPlayerBox(
            id: id,
            label: label,
            boundingBox: boundingBox,
            footPoint: footPoint,
            playerAreaPoint: point,
            lateralPosition: lateralPosition,
            depthPosition: depthPosition,
            isCurrentHitter: isCurrentHitter
        )
    }
}

struct MovementEvent: Identifiable, Hashable {
    enum Kind: String, Hashable, CaseIterable {
        case wrongExitDirection
        case directRetreatToWaiting
        case missingWaitingRecovery
        case failedToClearHittingZone
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
        static let minimumEventDuration: Double = 0.2
        static let samplingStride = 2
        static let hittingZoneMaxY: CGFloat = 1.5
        static let exitZoneMaxY: CGFloat = 0.56
        static let waitingZoneMinY: CGFloat = 1.5
        static let hittingZoneOverstayDuration: Double = 0.5
        static let wrongExitDecisionDelay: Double = 0.3
        static let exitZoneOverstayDuration: Double = 0.35
    }

    private enum HittingSide {
        case left
        case right

        var exitDirectionLabel: String {
            switch self {
            case .left:
                return "左邊"
            case .right:
                return "右邊"
            }
        }

        var exitSuggestionTitle: String {
            switch self {
            case .left:
                return "往左退出"
            case .right:
                return "往右退出"
            }
        }
    }

    private enum CourtRoleZone {
        case hitting
        case exit
        case wrongExit
        case waiting
        case other
    }

    private struct PlayerReviewPhase {
        let side: HittingSide
        let hittingZoneEnteredAt: Double
        var leftHittingZoneAt: Double?
        var enteredExitZoneAt: Double?
        var skippedExitZoneAt: Double?
        var partnerBecameHitterAt: Double?
    }

    private struct EventKey: Hashable {
        let kind: MovementEvent.Kind
        let playerLabel: String
    }

    private struct ActiveReviewEventInterval {
        let key: EventKey
        let startedAt: Double
        var lastSeenAt: Double
        var latestCandidate: EventCandidate
        var confidenceSamples: [Double]
    }

    private struct ReviewEventDedupKey: Hashable {
        let rallyIndex: Int
        let kind: MovementEvent.Kind
        let playerLabel: String?
    }

    private struct SidecarReviewContext {
        let frames: [PlayerTrackFrame]
        let rallyIntervals: [RallyInterval]
        let feedbackEvents: [TrackingSidecarFeedbackEvent]
        let handednessMode: PlayerHandednessMode
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

        if let sidecar = loadReviewContextFromSidecar(for: video) {
            let shouldRebuildFeedbackEvents = shouldRebuildFeedbackEventsFromFrames(
                sidecar.feedbackEvents,
                rallyIntervals: sidecar.rallyIntervals,
                frames: sidecar.frames
            )
            let movementEvents = sidecar.feedbackEvents.isEmpty || shouldRebuildFeedbackEvents
                ? buildMovementEvents(
                    from: sidecar.frames,
                    rallyIntervals: sidecar.rallyIntervals,
                    handednessMode: sidecar.handednessMode
                )
                : buildMovementEvents(
                    fromSidecarFeedbackEvents: sidecar.feedbackEvents,
                    rallyIntervals: sidecar.rallyIntervals
                )
            let suggestions = buildSuggestions(from: movementEvents)
            return ReviewSession(
                video: video,
                duration: duration,
                trackFrames: sidecar.frames,
                rallyIntervals: sidecar.rallyIntervals,
                handednessMode: sidecar.handednessMode,
                movementEvents: movementEvents,
                suggestions: suggestions
            )
        }

        guard
            let track = asset.tracks(withMediaType: .video).first,
            let reader = try? AVAssetReader(asset: asset)
        else {
            return ReviewSession(video: video, duration: duration, trackFrames: [], rallyIntervals: [], handednessMode: .rightRight, movementEvents: [], suggestions: [])
        }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            return ReviewSession(video: video, duration: duration, trackFrames: [], rallyIntervals: [], handednessMode: .rightRight, movementEvents: [], suggestions: [])
        }

        reader.add(output)
        guard reader.startReading() else {
            return ReviewSession(video: video, duration: duration, trackFrames: [], rallyIntervals: [], handednessMode: .rightRight, movementEvents: [], suggestions: [])
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

        let normalizedTrackFrames = normalizedTrackFrameTimes(trackFrames)
        let movementEvents = buildMovementEvents(from: normalizedTrackFrames, rallyIntervals: [], handednessMode: .rightRight)
        let suggestions = buildSuggestions(from: movementEvents)
        return ReviewSession(
            video: video,
            duration: duration,
            trackFrames: normalizedTrackFrames,
            rallyIntervals: [],
            handednessMode: .rightRight,
            movementEvents: movementEvents,
            suggestions: suggestions
        )
    }

    private static func shouldRebuildFeedbackEventsFromFrames(
        _ feedbackEvents: [TrackingSidecarFeedbackEvent],
        rallyIntervals: [RallyInterval],
        frames: [PlayerTrackFrame]
    ) -> Bool {
        guard !feedbackEvents.isEmpty, !rallyIntervals.isEmpty, !frames.isEmpty else { return false }

        return feedbackEvents.allSatisfy { feedbackEvent in
            rallyIntervals.contains { interval in
                abs(feedbackEvent.startTime - interval.startTime) < 0.05
                    && abs(feedbackEvent.endTime - interval.endTime) < 0.05
            }
        }
    }

    private static func loadReviewContextFromSidecar(for video: SavedVideo) -> SidecarReviewContext? {
        let sidecarURL = video.trackingDataURL
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: sidecarURL)
            let sidecar = try JSONDecoder().decode(TrackingSidecarFile.self, from: data)
            return SidecarReviewContext(
                frames: normalizedTrackFrameTimes(sidecar.frames.map { $0.playerTrackFrame() }),
                rallyIntervals: sidecar.rallyIntervals,
                feedbackEvents: sidecar.feedbackEvents,
                handednessMode: sidecar.handednessMode
            )
        } catch {
            print("Failed to load tracking sidecar: \(error)")
            return nil
        }
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

            let selectedBoxes = selectNearestTwoPlayerBoxes(
                from: (request.results ?? []).map(\.boundingBox)
            )

            let trackedPlayers = stableTrackedPlayers(previousPlayers: previousPlayers, candidateBoxes: selectedBoxes)
            return trackedPlayers.map { trackedPlayer in
                let footPoint = normalizedPlayerFootPoint(for: trackedPlayer.boundingBox)
                let courtMapPoint = fallbackCourtMapPoint(for: trackedPlayer.boundingBox)
                return TrackedPlayerBox(
                    id: trackedPlayer.id,
                    label: trackedPlayer.label,
                    boundingBox: trackedPlayer.boundingBox,
                    footPoint: footPoint,
                    playerAreaPoint: courtMapPoint
                )
            }
        } catch {
            print("Failed to analyze review frame: \(error)")
            return []
        }
    }

    private static func buildMovementEvents(
        from frames: [PlayerTrackFrame],
        rallyIntervals: [RallyInterval],
        handednessMode: PlayerHandednessMode
    ) -> [MovementEvent] {
        guard handednessMode == .rightRight else { return [] }

        let intervalFrames = frames.filter { frame in
            rallyIntervals.isEmpty || rallyIntervals.contains(where: { frame.time >= $0.startTime && frame.time <= $0.endTime })
        }
        let analysisFrames = intervalFrames.isEmpty && !rallyIntervals.isEmpty ? frames : intervalFrames
        guard !analysisFrames.isEmpty else { return [] }

        var events: [MovementEvent] = []
        var activeIntervals: [EventKey: ActiveReviewEventInterval] = [:]
        var reviewPhases: [String: PlayerReviewPhase] = [:]

        func appendEvent(
            key: EventKey,
            startTime: Double,
            endTime: Double,
            candidate: EventCandidate,
            confidenceSamples: [Double]
        ) {
            guard endTime - startTime >= ReviewConstants.minimumEventDuration else { return }
            let averagedConfidence = confidenceSamples.isEmpty
                ? candidate.confidence
                : confidenceSamples.reduce(0, +) / Double(confidenceSamples.count)
            events.append(
                MovementEvent(
                    kind: key.kind,
                    startTime: startTime,
                    endTime: endTime,
                    playerLabel: candidate.playerLabel,
                    confidence: averagedConfidence,
                    title: candidate.title,
                    detail: candidate.detail
                )
            )
        }

        func deactivateEvent(_ key: EventKey, at time: Double) {
            guard let activeInterval = activeIntervals.removeValue(forKey: key) else { return }
            appendEvent(
                key: key,
                startTime: activeInterval.startedAt,
                endTime: activeInterval.lastSeenAt,
                candidate: activeInterval.latestCandidate,
                confidenceSamples: activeInterval.confidenceSamples
            )
        }

        func setEventActive(_ candidate: EventCandidate, playerLabel: String, isActive: Bool, time: Double) {
            let key = EventKey(kind: candidate.kind, playerLabel: playerLabel)

            if isActive {
                if var activeInterval = activeIntervals[key] {
                    activeInterval.lastSeenAt = time
                    activeInterval.latestCandidate = candidate
                    activeInterval.confidenceSamples.append(candidate.confidence)
                    activeIntervals[key] = activeInterval
                } else {
                    activeIntervals[key] = ActiveReviewEventInterval(
                        key: key,
                        startedAt: time,
                        lastSeenAt: time,
                        latestCandidate: candidate,
                        confidenceSamples: [candidate.confidence]
                    )
                }
            } else {
                deactivateEvent(key, at: time)
            }
        }

        func deactivateAllEvents(for playerLabel: String, at time: Double) {
            for kind in MovementEvent.Kind.allCases {
                deactivateEvent(EventKey(kind: kind, playerLabel: playerLabel), at: time)
            }
        }

        for frame in analysisFrames {
            let playerLookup = Dictionary(uniqueKeysWithValues: frame.players.map { ($0.id, $0) })
            let hitterID = reviewHitterID(in: frame)

            for playerLabel in ["Player1", "Player2"] {
                guard
                    let player = playerLookup[playerLabel],
                    let point = player.playerAreaPoint
                else {
                    deactivateAllEvents(for: playerLabel, at: frame.time)
                    reviewPhases.removeValue(forKey: playerLabel)
                    continue
                }

                let playerSide = hittingSide(for: point)
                if hitterID == playerLabel, reviewZone(for: point, side: playerSide, handednessMode: handednessMode) == .hitting {
                    if let currentPhase = reviewPhases[playerLabel],
                       currentPhase.side == playerSide,
                       currentPhase.leftHittingZoneAt == nil {
                        // Continue the same hitting sequence.
                    } else {
                        reviewPhases[playerLabel] = PlayerReviewPhase(
                            side: playerSide,
                            hittingZoneEnteredAt: frame.time,
                            leftHittingZoneAt: nil,
                            enteredExitZoneAt: nil,
                            skippedExitZoneAt: nil,
                            partnerBecameHitterAt: nil
                        )
                    }
                }

                guard var phase = reviewPhases[playerLabel] else {
                    deactivateAllEvents(for: playerLabel, at: frame.time)
                    continue
                }

                let zone = reviewZone(for: point, side: phase.side, handednessMode: handednessMode)
                var wrongExitCandidate: EventCandidate?
                var waitingCandidate: EventCandidate?
                var noClearCandidate: EventCandidate?

                if hitterID != playerLabel, phase.enteredExitZoneAt != nil, phase.partnerBecameHitterAt == nil {
                    phase.partnerBecameHitterAt = frame.time
                }

                if zone == .hitting {
                    let dwellDuration = frame.time - phase.hittingZoneEnteredAt
                    if dwellDuration >= ReviewConstants.hittingZoneOverstayDuration {
                        let confidence = min(
                            max(
                                (dwellDuration - ReviewConstants.hittingZoneOverstayDuration) / 1.0,
                                0.45
                            ),
                            1
                        )
                        noClearCandidate = EventCandidate(
                            kind: .failedToClearHittingZone,
                            playerLabel: playerLabel,
                            confidence: confidence,
                            title: "\(playerLabel) 擊球完沒有讓開",
                            detail: "\(playerLabel) 在 \(timeLabel(phase.hittingZoneEnteredAt)) 到 \(timeLabel(frame.time)) 之間持續停在擊球區，擊球後沒有及時讓開前場。"
                        )
                    }
                } else {
                    if phase.leftHittingZoneAt == nil {
                        phase.leftHittingZoneAt = frame.time
                    }

                    switch zone {
                    case .waiting:
                        if phase.enteredExitZoneAt == nil, let leftTime = phase.leftHittingZoneAt {
                            let directRetreatDuration = frame.time - leftTime
                            let eventEndTime = max(frame.time, leftTime + ReviewConstants.minimumEventDuration)
                            appendEvent(
                                key: EventKey(kind: .directRetreatToWaiting, playerLabel: playerLabel),
                                startTime: leftTime,
                                endTime: eventEndTime,
                                candidate: directRetreatToWaitingCandidate(
                                    for: playerLabel,
                                    side: phase.side,
                                    startTime: leftTime,
                                    endTime: eventEndTime,
                                    confidence: min(max(directRetreatDuration / 0.7, 0.75), 1)
                                ),
                                confidenceSamples: [0.9]
                            )
                        }
                        deactivateAllEvents(for: playerLabel, at: frame.time)
                        reviewPhases.removeValue(forKey: playerLabel)
                        continue
                    case .exit:
                        if phase.enteredExitZoneAt == nil {
                            phase.enteredExitZoneAt = frame.time
                        }
                        if let partnerBecameHitterAt = phase.partnerBecameHitterAt,
                           frame.time - partnerBecameHitterAt >= ReviewConstants.exitZoneOverstayDuration {
                            let exitDuration = frame.time - partnerBecameHitterAt
                            waitingCandidate = waitingRecoveryCandidate(
                                for: playerLabel,
                                startTime: partnerBecameHitterAt,
                                endTime: frame.time,
                                confidence: min(
                                    max(
                                        (exitDuration - ReviewConstants.exitZoneOverstayDuration) / 0.8,
                                        0.65
                                    ),
                                    1
                                ),
                                handednessMode: handednessMode
                            )
                        }
                    case .wrongExit:
                        if let leftTime = phase.leftHittingZoneAt {
                            let wrongDuration = frame.time - leftTime
                            if wrongDuration >= ReviewConstants.wrongExitDecisionDelay {
                                wrongExitCandidate = wrongExitDirectionCandidate(
                                    for: playerLabel,
                                    side: phase.side,
                                    startTime: leftTime,
                                    endTime: frame.time,
                                    confidence: min(max((wrongDuration - ReviewConstants.wrongExitDecisionDelay) / 0.7, 0.65), 1)
                                )
                            }
                        }
                    case .other:
                        break
                    case .hitting:
                        break
                    }
                }

                reviewPhases[playerLabel] = phase

                if let wrongExitCandidate {
                    setEventActive(wrongExitCandidate, playerLabel: playerLabel, isActive: true, time: frame.time)
                } else {
                    deactivateEvent(EventKey(kind: .wrongExitDirection, playerLabel: playerLabel), at: frame.time)
                }

                deactivateEvent(EventKey(kind: .directRetreatToWaiting, playerLabel: playerLabel), at: frame.time)

                if let waitingCandidate {
                    setEventActive(waitingCandidate, playerLabel: playerLabel, isActive: true, time: frame.time)
                } else {
                    setEventActive(
                        waitingRecoveryCandidate(
                            for: playerLabel,
                            startTime: phase.leftHittingZoneAt ?? frame.time,
                            endTime: frame.time,
                            confidence: 0.45,
                            handednessMode: handednessMode
                        ),
                        playerLabel: playerLabel,
                        isActive: false,
                        time: frame.time
                    )
                }

                if let noClearCandidate {
                    setEventActive(noClearCandidate, playerLabel: playerLabel, isActive: true, time: frame.time)
                } else {
                    setEventActive(
                        EventCandidate(
                            kind: .failedToClearHittingZone,
                            playerLabel: playerLabel,
                            confidence: 0.45,
                            title: "\(playerLabel) 擊球完沒有讓開",
                            detail: "\(playerLabel) 擊球後在前場停留過久。"
                        ),
                        playerLabel: playerLabel,
                        isActive: false,
                        time: frame.time
                    )
                }
            }
        }

        for activeInterval in activeIntervals.values {
            appendEvent(
                key: activeInterval.key,
                startTime: activeInterval.startedAt,
                endTime: activeInterval.lastSeenAt,
                candidate: activeInterval.latestCandidate,
                confidenceSamples: activeInterval.confidenceSamples
            )
        }

        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.confidence > rhs.confidence
            }
            return lhs.startTime < rhs.startTime
        }

        return deduplicatedMovementEvents(sortedEvents, rallyIntervals: rallyIntervals)
    }

    private static func buildMovementEvents(
        fromSidecarFeedbackEvents feedbackEvents: [TrackingSidecarFeedbackEvent],
        rallyIntervals: [RallyInterval]
    ) -> [MovementEvent] {
        let sortedEvents: [MovementEvent] = feedbackEvents.compactMap { feedbackEvent -> MovementEvent? in
            guard let kind = MovementEvent.Kind(rawValue: feedbackEvent.kind) else { return nil }
            let startTime = min(feedbackEvent.startTime, feedbackEvent.endTime)
            let endTime = max(feedbackEvent.startTime, feedbackEvent.endTime)
            return MovementEvent(
                kind: kind,
                startTime: startTime,
                endTime: max(endTime, startTime + ReviewConstants.minimumEventDuration),
                playerLabel: feedbackEvent.playerLabel,
                confidence: 0.95,
                title: sidecarFeedbackTitle(for: kind, playerLabel: feedbackEvent.playerLabel),
                detail: sidecarFeedbackDetail(for: kind, playerLabel: feedbackEvent.playerLabel, startTime: startTime, endTime: endTime)
            )
        }
        .sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.confidence > rhs.confidence
            }
            return lhs.startTime < rhs.startTime
        }

        return deduplicatedMovementEvents(sortedEvents, rallyIntervals: rallyIntervals)
    }

    private static func deduplicatedMovementEvents(_ events: [MovementEvent], rallyIntervals: [RallyInterval]) -> [MovementEvent] {
        guard !rallyIntervals.isEmpty else { return events }

        var seenKeys = Set<ReviewEventDedupKey>()
        var deduplicatedEvents: [MovementEvent] = []

        for event in events {
            guard let rallyIndex = rallyIntervals.firstIndex(where: { interval in
                event.startTime >= interval.startTime && event.startTime <= interval.endTime
            }) else {
                deduplicatedEvents.append(event)
                continue
            }

            let key = ReviewEventDedupKey(
                rallyIndex: rallyIndex,
                kind: event.kind,
                playerLabel: event.playerLabel
            )
            guard !seenKeys.contains(key) else { continue }

            seenKeys.insert(key)
            deduplicatedEvents.append(event)
        }

        return deduplicatedEvents
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
        case .wrongExitDirection:
            return exitDirectionSuggestionTitle(for: event)
        case .directRetreatToWaiting:
            return "\(event.playerLabel ?? "球員") 不要直接後退"
        case .missingWaitingRecovery:
            return "\(event.playerLabel ?? "球員") 先回等待補位區"
        case .failedToClearHittingZone:
            return "\(event.playerLabel ?? "球員") 擊球後先讓開"
        }
    }

    private static func sidecarFeedbackTitle(for kind: MovementEvent.Kind, playerLabel: String) -> String {
        switch kind {
        case .wrongExitDirection:
            return "\(playerLabel) 退錯邊"
        case .directRetreatToWaiting:
            return "\(playerLabel) 擊球後直接後退"
        case .missingWaitingRecovery:
            return "\(playerLabel) 沒有等待補位"
        case .failedToClearHittingZone:
            return "\(playerLabel) 擊球完沒有讓開"
        }
    }

    private static func sidecarFeedbackDetail(
        for kind: MovementEvent.Kind,
        playerLabel: String,
        startTime: Double,
        endTime: Double
    ) -> String {
        switch kind {
        case .wrongExitDirection:
            return "\(playerLabel) 在 \(timeLabel(startTime)) 到 \(timeLabel(endTime)) 之間，錄影時已判定擊球後退到錯誤側。原因是錯邊退出會佔到隊友準備進入擊球區的路線，讓下一板銜接變慢。"
        case .directRetreatToWaiting:
            return "\(playerLabel) 在 \(timeLabel(startTime)) 到 \(timeLabel(endTime)) 之間，錄影時已判定擊球後沒有先經過外側退出區，而是直接退到等待區。原因是直接後退會穿過隊友補位路線，容易造成兩人互相卡位。"
        case .missingWaitingRecovery:
            return "\(playerLabel) 在 \(timeLabel(startTime)) 到 \(timeLabel(endTime)) 之間，錄影時已判定隊友成為擊球員後仍停在退出區太久。退出區應該只是短暫過渡位置，停太久會降低下一次輪轉速度。"
        case .failedToClearHittingZone:
            return "\(playerLabel) 在 \(timeLabel(startTime)) 到 \(timeLabel(endTime)) 之間，錄影時已判定擊球後停在擊球區太久。擊球區是下一位隊友要進入的位置，停留過久會擋住隊友上前擊球。"
        }
    }

    private static func suggestionText(for event: MovementEvent) -> String {
        switch event.kind {
        case .wrongExitDirection:
            let player = event.playerLabel ?? "該球員"
            return "AI 建議 \(player) 在 \(timeLabel(event.startTime)) 到 \(timeLabel(event.endTime)) 之間，擊球後先往該半區外側退出。原因是錯邊退出會佔到隊友準備進入擊球區的路線，讓下一板銜接變慢。"
        case .directRetreatToWaiting:
            let player = event.playerLabel ?? "該球員"
            return "AI 建議 \(player) 在 \(timeLabel(event.startTime)) 到 \(timeLabel(event.endTime)) 之間，不要擊球後直接往後退到等待區。原因是直接後退會穿過隊友的補位路線，雙打輪轉時容易和隊友互相卡位；應先往擊球側外側退出，再回到後方等待區。"
        case .missingWaitingRecovery:
            let player = event.playerLabel ?? "該球員"
            return "AI 建議 \(player) 在 \(timeLabel(event.startTime)) 到 \(timeLabel(event.endTime)) 之間，隊友已經成為擊球員後要更快離開退出區並回到等待區。原因是退出區只是一個短暫過渡位置，停太久會讓場上形成側邊壅塞，也會降低下一次補位速度。"
        case .failedToClearHittingZone:
            let player = event.playerLabel ?? "該球員"
            return "AI 建議 \(player) 在 \(timeLabel(event.startTime)) 到 \(timeLabel(event.endTime)) 之間擊球後更快離開前場擊球區。原因是擊球區是下一位隊友要進入的位置，停留過久會擋住隊友上前擊球，也會讓輪轉節奏變慢。"
        }
    }

    private static func reviewHitterID(in frame: PlayerTrackFrame) -> String? {
        if let hitter = frame.players.first(where: \.isCurrentHitter) {
            return hitter.id
        }

        return frame.players
            .filter { $0.playerAreaPoint != nil }
            .min { lhs, rhs in
                guard
                    let lhsPoint = lhs.playerAreaPoint,
                    let rhsPoint = rhs.playerAreaPoint
                else {
                    return false
                }
                return lhsPoint.y < rhsPoint.y
            }?
            .id
    }

    private static func hittingSide(for point: CGPoint) -> HittingSide {
        point.x < 0 ? .left : .right
    }

    private static func reviewZone(for point: CGPoint, side: HittingSide, handednessMode: PlayerHandednessMode) -> CourtRoleZone {
        switch handednessMode {
        case .rightRight:
            if hittingZoneRect(for: side).contains(point) {
                return .hitting
            }
            if exitZoneRect(for: side).contains(point) {
                return .exit
            }
            if exitZoneRect(for: oppositeSide(of: side)).contains(point) {
                return .wrongExit
            }
            if waitingZoneRect(for: side).contains(point) {
                return .waiting
            }
            return .other
        case .leftRight:
            if leftRightHittingZoneRect().contains(point) {
                return .hitting
            }
            if leftRightWaitingZoneContains(point) {
                return .waiting
            }
            return .other
        }
    }

    private static func hittingZoneRect(for side: HittingSide) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: -1.0, y: 0.0, width: 1.0, height: ReviewConstants.hittingZoneMaxY)
        case .right:
            return CGRect(x: 0.0, y: 0.0, width: 1.0, height: ReviewConstants.hittingZoneMaxY)
        }
    }

    private static func exitZoneRect(for side: HittingSide) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: -8.0, y: 0.0, width: 7.0, height: 8.0)
        case .right:
            return CGRect(x: 1.0, y: 0.0, width: 7.0, height: 8.0)
        }
    }

    private static func oppositeSide(of side: HittingSide) -> HittingSide {
        switch side {
        case .left:
            return .right
        case .right:
            return .left
        }
    }

    private static func waitingZoneRect(for side: HittingSide) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: -1.2, y: ReviewConstants.waitingZoneMinY, width: 1.3, height: 80.0)
        case .right:
            return CGRect(x: -0.1, y: ReviewConstants.waitingZoneMinY, width: 1.3, height: 80.0)
        }
    }

    private static func leftRightHittingZoneRect() -> CGRect {
        CGRect(x: -1.0, y: 0.0, width: 2.0, height: ReviewConstants.hittingZoneMaxY)
    }

    private static func leftRightWaitingZoneContains(_ point: CGPoint) -> Bool {
        let rearRect = CGRect(x: -1.6, y: ReviewConstants.waitingZoneMinY, width: 3.2, height: 1.8)
        let leftSideRect = CGRect(x: -1.6, y: 0.0, width: 0.6, height: ReviewConstants.waitingZoneMinY)
        let rightSideRect = CGRect(x: 1.0, y: 0.0, width: 0.6, height: ReviewConstants.waitingZoneMinY)
        return rearRect.contains(point) || leftSideRect.contains(point) || rightSideRect.contains(point)
    }

    private static func waitingRecoveryCandidate(
        for playerLabel: String,
        startTime: Double,
        endTime: Double,
        confidence: Double,
        handednessMode: PlayerHandednessMode
    ) -> EventCandidate {
        let detail: String
        switch handednessMode {
        case .rightRight:
            detail = "\(playerLabel) 在 \(timeLabel(startTime)) 到 \(timeLabel(endTime)) 之間，隊友已經接手成為擊球員後仍停在擊球後退出區，沒有快速回到後方等待補位區。退出區應該只是短暫過渡位置，停太久會讓側邊路線被佔住，也會降低下一次輪轉速度。"
        case .leftRight:
            detail = "\(playerLabel) 在 \(timeLabel(startTime)) 到 \(timeLabel(endTime)) 之間離開擊球區後，沒有盡快移到後方或兩側的等待區。"
        }

        return EventCandidate(
            kind: .missingWaitingRecovery,
            playerLabel: playerLabel,
            confidence: confidence,
            title: "\(playerLabel) 沒有等待補位",
            detail: detail
        )
    }

    private static func directRetreatToWaitingCandidate(
        for playerLabel: String,
        side: HittingSide,
        startTime: Double,
        endTime: Double,
        confidence: Double
    ) -> EventCandidate {
        EventCandidate(
            kind: .directRetreatToWaiting,
            playerLabel: playerLabel,
            confidence: confidence,
            title: "\(playerLabel) 擊球後直接後退",
            detail: "\(playerLabel) 在 \(timeLabel(startTime)) 到 \(timeLabel(endTime)) 之間，從\(side.exitDirectionLabel)半邊擊球後沒有先經過外側退出區，而是直接退到等待區。這會穿過隊友補位路線，容易造成兩人互相卡位。"
        )
    }

    private static func wrongExitDirectionCandidate(
        for playerLabel: String,
        side: HittingSide,
        startTime: Double,
        endTime: Double,
        confidence: Double = 0.8
    ) -> EventCandidate {
        EventCandidate(
            kind: .wrongExitDirection,
            playerLabel: playerLabel,
            confidence: confidence,
            title: "\(playerLabel) 退錯邊",
            detail: "\(playerLabel) 在 \(timeLabel(startTime)) 到 \(timeLabel(endTime)) 之間離開擊球區後，沒有先往\(side.exitDirectionLabel)的外側退出區移動。擊球後應該退出到自己擊球半邊的外側，讓隊友有空間從中間或後方進入擊球區。"
        )
    }

    private static func exitDirectionSuggestionTitle(for event: MovementEvent) -> String {
        guard let detailRange = event.detail.range(of: "往左") ?? event.detail.range(of: "左邊") else {
            if event.detail.contains("右") {
                return "往右退出"
            }
            return "先退到正確方向"
        }
        return event.detail[detailRange].contains("左") ? "往左退出" : "往右退出"
    }

    private struct EventCandidate {
        let kind: MovementEvent.Kind
        let playerLabel: String?
        let confidence: Double
        let title: String
        let detail: String
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
        persistVideo(from: temporaryURL, preferredExtension: temporaryURL.pathExtension, copyItem: false, trackingDataURL: nil)
    }

    @discardableResult
    fileprivate func saveRecordedVideo(from output: RecordedSessionOutput) -> SavedVideo? {
        persistVideo(
            from: output.videoURL,
            preferredExtension: output.videoURL.pathExtension,
            copyItem: false,
            trackingDataURL: output.trackingDataURL
        )
    }

    @discardableResult
    func importVideo(from sourceURL: URL) -> SavedVideo? {
        persistVideo(from: sourceURL, preferredExtension: sourceURL.pathExtension, copyItem: true, trackingDataURL: nil)
    }

    @discardableResult
    private func persistVideo(from sourceURL: URL, preferredExtension: String, copyItem: Bool, trackingDataURL: URL?) -> SavedVideo? {
        let fileManager = FileManager.default
        let directory = Self.storageDirectoryURL()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"

            let finalURL = directory
                .appendingPathComponent("TTCoach-\(formatter.string(from: Date()))")
                .appendingPathExtension(normalizedVideoExtension(from: preferredExtension))
            let finalTrackingURL = SavedVideo.trackingDataURL(forVideoURL: finalURL)

            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            if fileManager.fileExists(atPath: finalTrackingURL.path) {
                try fileManager.removeItem(at: finalTrackingURL)
            }

            if copyItem {
                try fileManager.copyItem(at: sourceURL, to: finalURL)
            } else {
                try fileManager.moveItem(at: sourceURL, to: finalURL)
            }

            if let trackingDataURL, fileManager.fileExists(atPath: trackingDataURL.path) {
                if copyItem {
                    try fileManager.copyItem(at: trackingDataURL, to: finalTrackingURL)
                } else {
                    try fileManager.moveItem(at: trackingDataURL, to: finalTrackingURL)
                }
            }

            let savedVideo = SavedVideo(url: finalURL, createdAt: Date())
            refreshVideos()
            return savedVideo
        } catch {
            print("Failed to save video: \(error)")
            if !copyItem {
                try? fileManager.removeItem(at: sourceURL)
            }
            return nil
        }
    }

    func deleteVideos(at offsets: IndexSet) {
        for index in offsets {
            let video = videos[index]
            deleteVideo(video)
        }
    }

    func deleteVideo(_ video: SavedVideo) {
        try? FileManager.default.removeItem(at: video.url)
        try? FileManager.default.removeItem(at: video.trackingDataURL)
        refreshVideos()
    }

    @discardableResult
    func renameVideo(_ video: SavedVideo, to newName: String) -> Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let destinationURL = video.url.deletingLastPathComponent()
            .appendingPathComponent(trimmedName)
            .appendingPathExtension(video.url.pathExtension)
        let sourceTrackingURL = video.trackingDataURL
        let destinationTrackingURL = SavedVideo.trackingDataURL(forVideoURL: destinationURL)

        guard destinationURL != video.url else { return true }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return false }
        guard !FileManager.default.fileExists(atPath: destinationTrackingURL.path) else { return false }

        do {
            try FileManager.default.moveItem(at: video.url, to: destinationURL)
            if FileManager.default.fileExists(atPath: sourceTrackingURL.path) {
                try FileManager.default.moveItem(at: sourceTrackingURL, to: destinationTrackingURL)
            }
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

    private func normalizedVideoExtension(from pathExtension: String) -> String {
        let normalizedExtension = pathExtension.lowercased()
        return ["mov", "mp4"].contains(normalizedExtension) ? normalizedExtension : "mov"
    }
}

struct SavedVideosView: View {
    @ObservedObject var videoLibrary: VideoLibraryManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage(appLanguageStorageKey) private var appLanguageRawValue = AppLanguage.chinese.rawValue
    @State private var selectedVideo: SavedVideo?
    @State private var reviewingVideo: SavedVideo?
    @State private var importedVideoItem: PhotosPickerItem?
    @State private var renamingVideo: SavedVideo?
    @State private var draftVideoName = ""
    @State private var isImportingVideo = false
    @State private var importErrorMessage: String?
    @State private var renameErrorMessage: String?

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .chinese
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if videoLibrary.videos.isEmpty {
                        ContentUnavailableView(
                            localized(appLanguage, zh: "還沒有已儲存影片", en: "No Saved Videos Yet"),
                            systemImage: "video.slash",
                            description: Text(localized(appLanguage, zh: "先開始一次錄影，關閉時選擇儲存，或從右上角上傳手機裡的影片做 review。", en: "Record a session and save it when closing, or import a video from your phone using the top-right button for review."))
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
                                        Label(localized(appLanguage, zh: "分析", en: "Review"), systemImage: "text.magnifyingglass")
                                    }

                                    Button {
                                        renamingVideo = video
                                        draftVideoName = video.title
                                    } label: {
                                        Label(localized(appLanguage, zh: "重新命名", en: "Rename"), systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        videoLibrary.deleteVideo(video)
                                    } label: {
                                        Label(localized(appLanguage, zh: "刪除", en: "Delete"), systemImage: "trash")
                                    }
                                }
                            }
                            .onDelete(perform: videoLibrary.deleteVideos)
                        }
                        .listStyle(.plain)
                    }
                }

                if isImportingVideo {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()

                    ProgressView(localized(appLanguage, zh: "匯入影片中...", en: "Importing Video..."))
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .navigationTitle(localized(appLanguage, zh: "已儲存影片", en: "Saved Videos"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localized(appLanguage, zh: "關閉", en: "Close")) {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    PhotosPicker(selection: $importedVideoItem, matching: .videos) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(isImportingVideo)

                    Button {
                        videoLibrary.refreshVideos()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isImportingVideo)
                }
            }
            .sheet(item: $selectedVideo) { video in
                VideoPlayerScreen(video: video)
            }
            .sheet(item: $reviewingVideo) { video in
                VideoReviewScreen(video: video)
            }
            .alert(localized(appLanguage, zh: "重新命名影片", en: "Rename Video"), isPresented: Binding(
                get: { renamingVideo != nil },
                set: { isPresented in
                    if !isPresented {
                        renamingVideo = nil
                        draftVideoName = ""
                    }
                }
            )) {
                TextField(localized(appLanguage, zh: "影片名稱", en: "Video Name"), text: $draftVideoName)

                Button(localized(appLanguage, zh: "取消", en: "Cancel"), role: .cancel) { }

                Button(localized(appLanguage, zh: "儲存", en: "Save")) {
                    guard let renamingVideo else { return }

                    let didRename = videoLibrary.renameVideo(renamingVideo, to: draftVideoName)
                    if !didRename {
                        renameErrorMessage = localized(appLanguage, zh: "重新命名失敗。請確認名稱不是空白，且沒有和其他影片重複。", en: "Rename failed. Make sure the name is not empty and does not duplicate another video.")
                    }

                    self.renamingVideo = nil
                    draftVideoName = ""
                }
            } message: {
                Text(localized(appLanguage, zh: "輸入新的影片名稱", en: "Enter a new video name"))
            }
            .task(id: importedVideoItem) {
                guard let importedVideoItem else { return }
                await importSelectedVideo(from: importedVideoItem)
            }
            .alert(localized(appLanguage, zh: "無法匯入影片", en: "Unable to Import Video"), isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        importErrorMessage = nil
                    }
                }
            )) {
                Button(localized(appLanguage, zh: "確定", en: "OK"), role: .cancel) { }
            } message: {
                Text(importErrorMessage ?? "")
            }
            .alert(localized(appLanguage, zh: "無法重新命名", en: "Unable to Rename"), isPresented: Binding(
                get: { renameErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        renameErrorMessage = nil
                    }
                }
            )) {
                Button(localized(appLanguage, zh: "確定", en: "OK"), role: .cancel) { }
            } message: {
                Text(renameErrorMessage ?? "")
            }
        }
    }

    @MainActor
    private func finishVideoImport(with savedVideo: SavedVideo?) {
        isImportingVideo = false
        importedVideoItem = nil

        guard let savedVideo else {
            importErrorMessage = localized(appLanguage, zh: "影片已選取，但匯入到 app 失敗。", en: "A video was selected, but importing it into the app failed.")
            return
        }

        reviewingVideo = savedVideo
    }

    private func importSelectedVideo(from item: PhotosPickerItem) async {
        await MainActor.run {
            guard !isImportingVideo else { return }
            isImportingVideo = true
            importErrorMessage = nil
        }

        do {
            guard let importedVideo = try await item.loadTransferable(type: ImportedReviewVideo.self) else {
                await MainActor.run {
                    isImportingVideo = false
                    importedVideoItem = nil
                    importErrorMessage = localized(appLanguage, zh: "選取的影片無法讀取。", en: "The selected video could not be read.")
                }
                return
            }

            let savedVideo = await MainActor.run {
                videoLibrary.importVideo(from: importedVideo.url)
            }
            try? FileManager.default.removeItem(at: importedVideo.url)

            await MainActor.run {
                finishVideoImport(with: savedVideo)
            }
        } catch {
            await MainActor.run {
                isImportingVideo = false
                importedVideoItem = nil
                importErrorMessage = "影片匯入失敗：\(error.localizedDescription)"
            }
        }
    }
}

struct VideoPlayerScreen: View {
    let video: SavedVideo
    @Environment(\.dismiss) private var dismiss
    @AppStorage(appLanguageStorageKey) private var appLanguageRawValue = AppLanguage.chinese.rawValue
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
    @State private var isSavingToPhotoLibrary = false
    @State private var photoLibrarySaveMessage: String?

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .chinese
    }

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

                            HStack(spacing: 12) {
                                Button {
                                    Task {
                                        await saveVideoToPhotoLibrary()
                                    }
                                } label: {
                                    Group {
                                        if isSavingToPhotoLibrary {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "arrow.down.to.line")
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.7))
                                    .foregroundStyle(.white)
                                    .clipShape(Circle())
                                }
                                .disabled(isSavingToPhotoLibrary)

                                Button(localized(appLanguage, zh: "完成", en: "Done")) {
                                    dismiss()
                                }
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.black.opacity(0.7))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
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
            .alert(
                localized(appLanguage, zh: "下載到相簿", en: "Save to Photos"),
                isPresented: Binding(
                    get: { photoLibrarySaveMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            photoLibrarySaveMessage = nil
                        }
                    }
                )
            ) {
                Button(localized(appLanguage, zh: "確定", en: "OK"), role: .cancel) { }
            } message: {
                Text(photoLibrarySaveMessage ?? "")
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

    @MainActor
    private func saveVideoToPhotoLibrary() async {
        guard !isSavingToPhotoLibrary else { return }
        isSavingToPhotoLibrary = true
        defer { isSavingToPhotoLibrary = false }

        let authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            photoLibrarySaveMessage = localized(
                appLanguage,
                zh: "沒有相簿存取權限，無法將影片下載到手機相簿。",
                en: "Photo Library access was not granted, so the video could not be saved."
            )
            return
        }

        do {
            try await saveVideoFileToPhotoLibrary(video.url)
            photoLibrarySaveMessage = localized(
                appLanguage,
                zh: "影片已下載到手機相簿。",
                en: "The video was saved to your Photos library."
            )
        } catch {
            photoLibrarySaveMessage = localized(
                appLanguage,
                zh: "下載到相簿失敗：\(error.localizedDescription)",
                en: "Failed to save to Photos: \(error.localizedDescription)"
            )
        }
    }

    private func saveVideoFileToPhotoLibrary(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .video, fileURL: url, options: nil)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "TTCoach.PhotoLibrary",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString(
                                "Unknown photo library save error.",
                                comment: "Fallback error when saving a video to Photos fails without an underlying system error."
                            )
                        ]
                    ))
                }
            }
        }
    }
}

struct VideoReviewScreen: View {
    let video: SavedVideo
    @Environment(\.dismiss) private var dismiss
    @AppStorage(appLanguageStorageKey) private var appLanguageRawValue = AppLanguage.chinese.rawValue

    @State private var player = AVPlayer()
    @State private var session: ReviewSession?
    @State private var presentationInfo = VideoPresentationInfo()
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isSeeking = false
    @State private var isPlaying = false
    @State private var isCourtMapPresented = false
    @State private var selectedReviewEvent: MovementEvent?
    @State private var timeObserver: Any?

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .chinese
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Color.black

                        InlineVideoPlayer(player: player, videoGravity: .resizeAspect)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if session == nil {
                            ProgressView(localized(appLanguage, zh: "分析影片中...", en: "Analyzing Video..."))
                                .padding(20)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(presentationInfo.aspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                    reviewPlaybackControls

                    if let session {
                        activeReviewInsight()
                        reviewTimeline(session: session)
                        reviewSummary(session: session)
                        reviewSuggestionList(session: session)
                        reviewEventList(session: session)
                        coordinationScoreCard(session: session)
                    } else {
                        Text(localized(appLanguage, zh: "正在建立 review 資料模型與事件點。", en: "Building the review model and event markers."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle(localized(appLanguage, zh: "影片分析", en: "Video Review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isCourtMapPresented = true
                    } label: {
                        Image(systemName: "map")
                    }
                    .disabled(session == nil)

                    Button(localized(appLanguage, zh: "完成", en: "Done")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isCourtMapPresented) {
                if let session {
                    ReviewCourtMapScreen(
                        session: session,
                        currentTime: $currentTime,
                        duration: duration,
                        isPlaying: $isPlaying,
                        onTogglePlayback: toggleReviewPlayback,
                        onSeek: seekReview,
                        selectedEvent: selectedMapEvent
                    )
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

    private var displayedSuggestion: ReviewSuggestion? {
        session?.suggestions
            .filter { $0.timeRange.lowerBound <= currentTime }
            .max(by: { $0.timeRange.lowerBound < $1.timeRange.lowerBound })
    }

    private var selectedMapEvent: MovementEvent? {
        if let selectedReviewEvent {
            return selectedReviewEvent
        }
        return activeEvent
    }

    private func activeReviewInsight() -> some View {
        Group {
            if let displayedSuggestion {
                ActiveReviewSuggestionCard(suggestion: displayedSuggestion)
            } else {
                ReviewSuggestionPlaceholderCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(localized(appLanguage, zh: "分析摘要", en: "Review Session"))
                .font(.headline)

            HStack {
                reviewStat(title: localized(appLanguage, zh: "影片長度", en: "Duration"), value: reviewTimeString(session.duration))
                reviewStat(title: localized(appLanguage, zh: "分析影格", en: "Frames"), value: "\(session.trackFrames.count)")
                reviewStat(title: localized(appLanguage, zh: "事件點", en: "Events"), value: "\(session.movementEvents.count)")
                reviewStat(title: localized(appLanguage, zh: "AI 建議", en: "AI Tips"), value: "\(session.suggestions.count)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func reviewTimeline(session: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(appLanguage, zh: "分析時間軸", en: "Review Timeline"))
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
            Text(localized(appLanguage, zh: "移動事件", en: "Movement Events"))
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
                            Text(event.playerLabel ?? localized(appLanguage, zh: "雙人站位", en: "Team Positioning"))
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

    private func coordinationScoreCard(session: ReviewSession) -> some View {
        let summary = coordinationScoreSummary(for: session)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(localized(appLanguage, zh: "配合度分數", en: "Coordination Score"))
                    .font(.headline)
                Spacer()
                Text("\(summary.score) / 100")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(coordinationScoreColor(summary.score))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(localized(appLanguage, zh: "主要問題", en: "Main Issue"))
                    .font(.subheadline.weight(.semibold))
                Text(summary.mainIssueText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localized(appLanguage, zh: "錯誤細項", en: "Breakdown"))
                    .font(.subheadline.weight(.semibold))

                ForEach(MovementEvent.Kind.allCases, id: \.self) { kind in
                    HStack {
                        Text(coordinationBreakdownLabel(for: kind))
                        Spacer()
                        Text("\(summary.counts[kind, default: 0])")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(localized(appLanguage, zh: "建議", en: "Suggestion"))
                    .font(.subheadline.weight(.semibold))
                Text(summary.suggestion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Text(localized(
                appLanguage,
                zh: "計算方式：總扣分 \(scoreNumberString(summary.totalPenalty))，平均每段 rally 扣分 \(scoreNumberString(summary.averagePenaltyPerRally))，rally 數 \(summary.rallyCount)。",
                en: "Formula: total penalty \(scoreNumberString(summary.totalPenalty)), average penalty per rally \(scoreNumberString(summary.averagePenaltyPerRally)), rally count \(summary.rallyCount)."
            ))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private struct CoordinationScoreSummary {
        let score: Int
        let rallyCount: Int
        let totalPenalty: Double
        let averagePenaltyPerRally: Double
        let counts: [MovementEvent.Kind: Int]
        let mainIssueText: String
        let suggestion: String
    }

    private func coordinationScoreSummary(for session: ReviewSession) -> CoordinationScoreSummary {
        let rallyCount = max(session.rallyIntervals.count, 1)
        var counts: [MovementEvent.Kind: Int] = [:]
        var weightedCounts: [MovementEvent.Kind: Double] = [:]
        var totalPenalty = 0.0

        for event in session.movementEvents {
            let severity = min(max(event.confidence, 0), 1)
            let weight = coordinationFeedbackWeight(for: event.kind)
            counts[event.kind, default: 0] += 1
            weightedCounts[event.kind, default: 0] += weight * severity
            totalPenalty += weight * severity
        }

        let averagePenaltyPerRally = totalPenalty / Double(rallyCount)
        let score = Int(min(max(100 - averagePenaltyPerRally * 10, 0), 100).rounded())
        let mainIssueKind = MovementEvent.Kind.allCases.max { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount == rhsCount {
                return weightedCounts[lhs, default: 0] < weightedCounts[rhs, default: 0]
            }
            return lhsCount < rhsCount
        }

        return CoordinationScoreSummary(
            score: score,
            rallyCount: rallyCount,
            totalPenalty: totalPenalty,
            averagePenaltyPerRally: averagePenaltyPerRally,
            counts: counts,
            mainIssueText: coordinationMainIssueText(kind: mainIssueKind, count: mainIssueKind.map { counts[$0, default: 0] } ?? 0),
            suggestion: coordinationSuggestion(for: mainIssueKind, score: score)
        )
    }

    private func coordinationFeedbackWeight(for kind: MovementEvent.Kind) -> Double {
        switch kind {
        case .failedToClearHittingZone:
            return 1.2
        case .wrongExitDirection:
            return 1.5
        case .directRetreatToWaiting:
            return 1.3
        case .missingWaitingRecovery:
            return 1.0
        }
    }

    private func coordinationMainIssueText(kind: MovementEvent.Kind?, count: Int) -> String {
        guard let kind, count > 0 else {
            return localized(
                appLanguage,
                zh: "這段影片沒有偵測到明顯的輪轉或站位錯誤。",
                en: "No major rotation or positioning issue was detected in this review."
            )
        }

        return localized(
            appLanguage,
            zh: "\(coordinationBreakdownLabel(for: kind)) 出現 \(count) 次。",
            en: "\(coordinationBreakdownLabel(for: kind)) happened \(count) \(count == 1 ? "time" : "times")."
        )
    }

    private func coordinationSuggestion(for kind: MovementEvent.Kind?, score: Int) -> String {
        guard let kind else {
            return localized(
                appLanguage,
                zh: "維持現在的輪轉節奏，擊球後繼續快速讓出前場並回到等待補位區。",
                en: "Keep the current rhythm: clear the hitting zone quickly and reset behind your partner after each shot."
            )
        }

        switch kind {
        case .failedToClearHittingZone:
            return localized(
                appLanguage,
                zh: "優先練習擊球後立刻離開前場，讓隊友可以順利進入下一拍的擊球區。",
                en: "Focus on clearing the front hitting zone immediately after contact so your partner has room to step in for the next shot."
            )
        case .wrongExitDirection:
            return localized(
                appLanguage,
                zh: "擊球後優先往擊球側外側退出，避免切進隊友的補位路線，讓輪轉更順。",
                en: "Focus on exiting outward after each shot to keep the rotation smooth and avoid cutting across your partner's recovery path."
            )
        case .directRetreatToWaiting:
            return localized(
                appLanguage,
                zh: "不要擊球後直接往後退；先往側外側退出，再回到後方等待補位區，避免和隊友路線重疊。",
                en: "Avoid moving straight back after hitting. Exit to the outside first, then reset behind your partner to prevent path conflicts."
            )
        case .missingWaitingRecovery:
            return localized(
                appLanguage,
                zh: "退出到側邊後不要停留太久，隊友成為擊球員時應更快回到後方等待補位區。",
                en: "Do not stay on the side after rotating out. Once your partner becomes the hitter, recover earlier into the waiting zone."
            )
        }
    }

    private func coordinationBreakdownLabel(for kind: MovementEvent.Kind) -> String {
        switch kind {
        case .failedToClearHittingZone:
            return localized(appLanguage, zh: "擊球區停留太久", en: "Stayed in hitting zone too long")
        case .wrongExitDirection:
            return localized(appLanguage, zh: "退出方向錯誤", en: "Moved to the wrong side")
        case .directRetreatToWaiting:
            return localized(appLanguage, zh: "擊球後直接後退", en: "Moved straight back after hitting")
        case .missingWaitingRecovery:
            return localized(appLanguage, zh: "退出後停在側邊太久", en: "Stopped on the side after rotating out")
        }
    }

    private func coordinationScoreColor(_ score: Int) -> Color {
        if score >= 80 {
            return .green
        } else if score >= 60 {
            return .orange
        } else {
            return .red
        }
    }

    private func scoreNumberString(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func reviewSuggestionList(session: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(appLanguage, zh: "AI 建議", en: "AI Suggestions"))
                .font(.headline)

            ForEach(session.suggestions) { suggestion in
                Button {
                    selectedReviewEvent = matchedEvent(for: suggestion)
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
                            Text(suggestion.playerLabel ?? localized(appLanguage, zh: "雙人站位", en: "Team Positioning"))
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
            Text(localized(appLanguage, zh: "追蹤影格", en: "Track Frames"))
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
        selectedReviewEvent = event
        currentTime = event.startTime
        seekReview(to: event.startTime)
    }

    private func matchedEvent(for suggestion: ReviewSuggestion) -> MovementEvent? {
        session?.movementEvents.first(where: { event in
            event.kind == suggestion.eventKind &&
            event.startTime <= suggestion.timeRange.upperBound &&
            event.endTime >= suggestion.timeRange.lowerBound
        })
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

struct AfterRallyDebugPanel: View {
    let items: [AfterRallyDebugItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("After Rally Debug")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)

            if items.isEmpty {
                Text("IDs: none")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.88))
            } else {
                Text("IDs: " + items.map { String($0.code) }.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.94))

                ForEach(items) { item in
                    Text(item.label)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ReviewFrameSummary: View {
    let frame: PlayerTrackFrame
    @AppStorage(appLanguageStorageKey) private var appLanguageRawValue = AppLanguage.chinese.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .chinese
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized(appLanguage, zh: "目前分析幀", en: "Current Frame"))
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
    @AppStorage(appLanguageStorageKey) private var appLanguageRawValue = AppLanguage.chinese.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .chinese
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(localized(appLanguage, zh: "目前事件", en: "Current Event"))
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
    @AppStorage(appLanguageStorageKey) private var appLanguageRawValue = AppLanguage.chinese.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .chinese
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localized(appLanguage, zh: "AI 建議", en: "AI Suggestion"))
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
                Text(suggestion.playerLabel ?? localized(appLanguage, zh: "雙人站位", en: "Team Positioning"))
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

struct ReviewSuggestionPlaceholderCard: View {
    @AppStorage(appLanguageStorageKey) private var appLanguageRawValue = AppLanguage.chinese.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .chinese
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localized(appLanguage, zh: "AI 建議", en: "AI Suggestion"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))

                Spacer()

                Text(localized(appLanguage, zh: "等待中", en: "Waiting"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .foregroundStyle(.white)
            }

            Text(localized(appLanguage, zh: "尚未出現 feedback", en: "No Feedback Yet"))
                .font(.headline)
                .foregroundStyle(.white)

            Text(localized(appLanguage, zh: "這個區塊會固定顯示。當影片跑到第一個 feedback 時，內容會更新；之後會維持目前建議，直到下一個 feedback 出現。", en: "This panel stays visible. It will update when the first feedback appears, then keep the current suggestion until the next feedback shows up."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.94))
        }
        .padding(12)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
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

struct ReviewCourtMapScreen: View {
    let session: ReviewSession
    @Binding var currentTime: Double
    let duration: Double
    @Binding var isPlaying: Bool
    let onTogglePlayback: () -> Void
    let onSeek: (Double) -> Void
    let selectedEvent: MovementEvent?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(appLanguageStorageKey) private var appLanguageRawValue = AppLanguage.chinese.rawValue
    @State private var isSeeking = false

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .chinese
    }

    private enum MapConstants {
        static let recentTrailDuration: Double = 1.5
    }

    private var courtMapFrames: [PlayerTrackFrame] {
        filteredCourtMapFrames(from: session.trackFrames)
    }

    private var courtMapFramesWithPlayers: [PlayerTrackFrame] {
        courtMapFrames.filter { frame in
            frame.players.contains { $0.playerAreaPoint != nil }
        }
    }

    private var currentFrame: PlayerTrackFrame? {
        guard !courtMapFramesWithPlayers.isEmpty else { return nil }
        return courtMapFramesWithPlayers.min(by: { abs($0.time - currentTime) < abs($1.time - currentTime) })
    }

    private var displayedTrailFrames: [PlayerTrackFrame] {
        if let selectedEvent {
            let selectedFrames = courtMapFramesWithPlayers.filter { frame in
                frame.time >= selectedEvent.startTime && frame.time <= selectedEvent.endTime
            }
            return selectedFrames.isEmpty ? (currentFrame.map { [$0] } ?? []) : selectedFrames
        }

        let trailStart = max(currentTime - MapConstants.recentTrailDuration, 0)
        let trailFrames = courtMapFramesWithPlayers.filter { frame in
            frame.time >= trailStart && frame.time <= currentTime
        }
        return trailFrames.isEmpty ? (currentFrame.map { [$0] } ?? []) : trailFrames
    }

    private var modeTitle: String {
        selectedEvent == nil
            ? localized(appLanguage, zh: "即時位置與最近軌跡", en: "Live Position + Recent Trails")
            : localized(appLanguage, zh: "所選回合軌跡", en: "Selected Rally Trajectory")
    }

    private var modeDetail: String {
        if let selectedEvent {
            return "\(selectedEvent.title) · \(timeString(selectedEvent.startTime)) - \(timeString(selectedEvent.endTime))"
        }
        return localized(appLanguage, zh: "顯示最接近 \(timeString(currentTime)) 的分析影格，以及前 1.5 秒的移動軌跡。", en: "Showing the analyzed frame closest to \(timeString(currentTime)) with the last 1.5 seconds of movement.")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ReviewCourtMapView(
                        currentFrame: currentFrame,
                        trailFrames: displayedTrailFrames,
                        selectedEvent: selectedEvent
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.9, contentMode: .fit)

                    courtMapPlaybackControls

                    VStack(alignment: .leading, spacing: 8) {
                        Text(modeTitle)
                            .font(.headline)

                        Text(modeDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                    HStack(spacing: 12) {
                        CourtMapLegendChip(label: "Player1", color: .blue)
                        CourtMapLegendChip(label: "Player2", color: .orange)
                        Spacer()
                    }

                    Text(localized(appLanguage, zh: "上方代表更靠近球桌。位置來自每位球員 bounding box 的腳底點，並映射到標準化的跑動區域座標。", en: "The top edge is closer to the table. Positions come from each player's bounding-box foot point mapped into normalized player-area coordinates."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle(localized(appLanguage, zh: "2D 球場地圖", en: "2D Court Map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized(appLanguage, zh: "完成", en: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private var courtMapPlaybackControls: some View {
        HStack(spacing: 16) {
            Button(action: onTogglePlayback) {
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
                            onSeek(currentTime)
                            isSeeking = false
                        }
                    }
                )

                HStack {
                    Text(timeString(currentTime))
                    Spacer()
                    Text(timeString(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ReviewCourtMapView: View {
    let currentFrame: PlayerTrackFrame?
    let trailFrames: [PlayerTrackFrame]
    let selectedEvent: MovementEvent?

    private let playerColors: [String: Color] = [
        "Player1": .blue,
        "Player2": .orange
    ]

    var body: some View {
        GeometryReader { geometry in
            let viewBounds = CGRect(origin: .zero, size: geometry.size)
            let outerRect = viewBounds.insetBy(dx: 18, dy: 18)
            let tableRect = CGRect(
                x: outerRect.minX + (outerRect.width * 0.19),
                y: viewBounds.minY,
                width: outerRect.width * 0.62,
                height: outerRect.height * 0.24
            )
            let playerZoneRect = CGRect(
                x: outerRect.minX + (outerRect.width * 0.015),
                y: tableRect.maxY,
                width: outerRect.width * 0.97,
                height: outerRect.maxY - tableRect.maxY - 18
            )

            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.17, green: 0.38, blue: 0.28),
                                Color(red: 0.09, green: 0.21, blue: 0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.black.opacity(0.18), lineWidth: 2)

                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.23, green: 0.48, blue: 0.82))
                    .frame(width: tableRect.width, height: tableRect.height)
                    .position(x: tableRect.midX, y: tableRect.midY)

                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: tableRect.width, height: tableRect.height)
                    .position(x: tableRect.midX, y: tableRect.midY)

                Path { path in
                    path.move(to: CGPoint(x: tableRect.midX, y: tableRect.minY))
                    path.addLine(to: CGPoint(x: tableRect.midX, y: tableRect.maxY))
                }
                .stroke(Color.white.opacity(0.95), lineWidth: 2)

                Path { path in
                    let insetX = tableRect.width * 0.04
                    let netY = tableRect.minY + 1.5
                    path.move(to: CGPoint(x: tableRect.minX + insetX, y: netY))
                    path.addLine(to: CGPoint(x: tableRect.maxX - insetX, y: netY))
                }
                .stroke(Color.white.opacity(0.98), lineWidth: 3)

                Path { path in
                    let insetX = tableRect.width * 0.04
                    let startX = tableRect.minX + insetX
                    let endX = tableRect.maxX - insetX
                    let netY = tableRect.minY + 1.5
                    let netDepth: CGFloat = 7
                    let segmentWidth: CGFloat = 10
                    var x = startX

                    while x < endX {
                        let nextX = min(x + segmentWidth, endX)
                        path.move(to: CGPoint(x: x, y: netY))
                        path.addLine(to: CGPoint(x: nextX, y: netY + netDepth))
                        x += segmentWidth * 0.9
                    }
                }
                .stroke(Color.white.opacity(0.55), lineWidth: 1.2)

                Text("Table")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .position(x: tableRect.midX, y: tableRect.maxY - 10)

                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: playerZoneRect.width, height: playerZoneRect.height)
                    .position(x: playerZoneRect.midX, y: playerZoneRect.midY)

                Path { path in
                    path.move(to: CGPoint(x: playerZoneRect.midX, y: playerZoneRect.minY))
                    path.addLine(to: CGPoint(x: playerZoneRect.midX, y: playerZoneRect.maxY))

                    path.move(to: CGPoint(x: playerZoneRect.minX, y: playerZoneRect.minY + (playerZoneRect.height * 0.33)))
                    path.addLine(to: CGPoint(x: playerZoneRect.maxX, y: playerZoneRect.minY + (playerZoneRect.height * 0.33)))

                    path.move(to: CGPoint(x: playerZoneRect.minX, y: playerZoneRect.minY + (playerZoneRect.height * 0.66)))
                    path.addLine(to: CGPoint(x: playerZoneRect.maxX, y: playerZoneRect.minY + (playerZoneRect.height * 0.66)))
                }
                .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.25, dash: [6, 6]))

                Text("Player Movement Zone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .position(x: playerZoneRect.midX, y: playerZoneRect.maxY + 16)

                ForEach(currentPlayers, id: \.id) { player in
                    if let point = player.playerAreaPoint {
                        let position = mappedPosition(for: point, in: playerZoneRect)
                        let isCurrentHitter = player.id == currentHitterID

                        Circle()
                            .fill(playerColor(for: player))
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .stroke(isCurrentHitter ? .red : .white, lineWidth: 3)
                            }
                            .position(position)

                        Text(player.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(playerColor(for: player), in: Capsule())
                            .position(
                                x: position.x,
                                y: max(playerZoneRect.minY + 16, position.y - 24)
                            )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 28))
            .animation(.linear(duration: 0.12), value: currentPlayers)
        }
    }

    private var currentPlayers: [TrackedPlayerBox] {
        currentFrame?.players.filter { $0.playerAreaPoint != nil } ?? []
    }

    private var currentHitterID: String? {
        if let markedHitter = currentPlayers.first(where: \.isCurrentHitter)?.id {
            return markedHitter
        }

        return currentPlayers.min { lhs, rhs in
            guard
                let lhsPoint = lhs.playerAreaPoint,
                let rhsPoint = rhs.playerAreaPoint
            else {
                return false
            }
            return lhsPoint.y < rhsPoint.y
        }?.id
    }

    private func playerColor(for player: TrackedPlayerBox) -> Color {
        playerColors[player.id, default: .gray]
    }

    private func mappedPosition(for point: CGPoint, in rect: CGRect) -> CGPoint {
        let horizontalRange: CGFloat = 1.6
        let verticalRange: CGFloat = 2.2
        let normalizedX = min(max((point.x + horizontalRange) / (horizontalRange * 2), 0), 1)
        let normalizedY = min(max(point.y / verticalRange, 0), 1)

        return CGPoint(
            x: rect.minX + (normalizedX * rect.width),
            y: rect.minY + (normalizedY * rect.height)
        )
    }
}

struct CourtMapLegendChip: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: Capsule())
    }
}

extension MovementEvent {
    var tintColor: Color {
        switch kind {
        case .wrongExitDirection:
            return .red
        case .directRetreatToWaiting:
            return .purple
        case .missingWaitingRecovery:
            return .blue
        case .failedToClearHittingZone:
            return .orange
        }
    }

    var kindLabel: String {
        switch kind {
        case .wrongExitDirection:
            return "退錯邊"
        case .directRetreatToWaiting:
            return "擊球後直接後退"
        case .missingWaitingRecovery:
            return "沒有等待補位"
        case .failedToClearHittingZone:
            return "擊球完沒有讓開"
        }
    }
}

extension ReviewSuggestion {
    var tintColor: Color {
        switch eventKind {
        case .wrongExitDirection:
            return .red
        case .directRetreatToWaiting:
            return .purple
        case .missingWaitingRecovery:
            return .blue
        case .failedToClearHittingZone:
            return .orange
        }
    }

    var eventKindLabel: String {
        switch eventKind {
        case .wrongExitDirection:
            return "退錯邊"
        case .directRetreatToWaiting:
            return "擊球後直接後退"
        case .missingWaitingRecovery:
            return "沒有等待補位"
        case .failedToClearHittingZone:
            return "擊球完沒有讓開"
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
        static let stillnessDuration: Double = 2.0
        static let maximumStillCenterShift: CGFloat = 0.2
        static let maximumStillSizeShift: CGFloat = 0.08
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
        static let directionalCueDelay: Double = 0.5
        static let hittingZoneMaxY: CGFloat = 1.5
        static let exitZoneMaxY: CGFloat = 0.56
        static let hittingZoneOverstayDuration: Double = 0.5
        static let waitingZoneMinY: CGFloat = 1.5
        static let exitToWaitingTransitionDuration: Double = 0.35
    }

    let session = AVCaptureSession()
    @Published private(set) var trackedPlayers: [TrackedPlayerBox] = []
    @Published private(set) var trackingDebugInfo = TrackingDebugInfo()
    @Published private(set) var captureDevice: AVCaptureDevice?
    @Published private(set) var isRecordingActive = false
    @Published private(set) var rallyState: RallyState = .end
    @Published private(set) var playerAreaSpatialStatus = PlayerAreaSpatialStatus.uncalibrated
    @Published private(set) var selectedLiveFeedbackMode: LiveFeedbackMode = .duringRally
    @Published private(set) var afterRallyDebugItems: [AfterRallyDebugItem] = []

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
    }

    private enum LiveHittingSide {
        case left
        case right
    }

    private enum LiveCourtRoleZone {
        case hitting
        case correctExit
        case wrongExit
        case waiting
        case other
    }

    private struct LivePlayerFeedbackPhase {
        let side: LiveHittingSide
        let hittingZoneEnteredAt: Double
        var leftHittingZoneAt: Double?
        var enteredExitZoneAt: Double?
        var skippedExitZoneAt: Double?
        var partnerBecameHitterAt: Double?
    }

    private struct AfterRallyFeedbackEvent: Hashable {
        enum Kind: Hashable {
            case hittingZoneOverstay
            case wrongExitSide
            case directRetreatToWaiting
            case exitZoneOverstay
        }

        let playerID: String
        let kind: Kind
        let triggeredAt: Double

        func hash(into hasher: inout Hasher) {
            hasher.combine(playerID)
            hasher.combine(kind)
        }

        static func == (lhs: AfterRallyFeedbackEvent, rhs: AfterRallyFeedbackEvent) -> Bool {
            lhs.playerID == rhs.playerID && lhs.kind == rhs.kind
        }
    }

    private struct PendingDirectionalCue {
        let hitterID: String
        let dueTime: Double
    }

    private struct RallyMotionState {
        var stillnessAnchorPlayers: [TrackedPlayerBox] = []
        var stillnessStartedAt: Double?
        var detectedLargeMovementSinceStart = false
    }

    private var isConfigured = false
    private var frameCounter = 0
    private var latestTrackedPlayers: [TrackedPlayerBox] = []
    private var trackingRequests: [VNTrackObjectRequest] = []
    private var missedDetectionFrames = 0
    private var recordingDecision: RecordingDecision = .discard
    private var stopCompletion: ((RecordedSessionOutput?) -> Void)?
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingURL: URL?
    private var recordingTrackingDataURL: URL?
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
    private var rallyMotionState = RallyMotionState()
    private var activeHitterState: ActiveHitterState?
    private var pendingDirectionalCue: PendingDirectionalCue?
    private var liveFeedbackMode: LiveFeedbackMode = .duringRally
    private var livePlayerFeedbackPhases: [String: LivePlayerFeedbackPhase] = [:]
    private var afterRallyFeedbackEvents = Set<AfterRallyFeedbackEvent>()
    private var audioFeedbackMuteUntil: CFTimeInterval = 0
    private var recordedTrackFrames: [PlayerTrackFrame] = []
    private var recordedRallyIntervals: [RallyInterval] = []
    private var recordedFeedbackEvents: [TrackingSidecarFeedbackEvent] = []
    private var currentRecordedRallyStartTime: Double?
    private var lastRecordedFrameTime: Double = 0
    private var recordingHandednessMode: PlayerHandednessMode = .rightRight

    func requestPermissionAndStart(handednessMode: PlayerHandednessMode, feedbackMode: LiveFeedbackMode, completion: @escaping (Bool) -> Void) {
        recordingHandednessMode = handednessMode
        liveFeedbackMode = feedbackMode
        DispatchQueue.main.async {
            self.selectedLiveFeedbackMode = feedbackMode
            self.afterRallyDebugItems = []
        }
        requestCapturePermissions { granted in
            if granted {
                self.configureAndStartSession()
            }

            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    fileprivate func stopSession(saveRecording: Bool, completion: @escaping (RecordedSessionOutput?) -> Void) {
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
        transitionRallyState(to: .end, playFeedback: false, timestamp: lastRecordedFrameTime)
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
        let temporaryTrackingDataURL = SavedVideo.trackingDataURL(forVideoURL: temporaryURL)

        try? FileManager.default.removeItem(at: temporaryURL)
        try? FileManager.default.removeItem(at: temporaryTrackingDataURL)
        recordingURL = temporaryURL
        recordingTrackingDataURL = temporaryTrackingDataURL
        recordingStartTime = nil
        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
        shouldStopRecording = false
        isFinishingRecording = false
        recordedTrackFrames = []
        recordedRallyIntervals = []
        recordedFeedbackEvents = []
        currentRecordedRallyStartTime = nil
        lastRecordedFrameTime = 0
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

    private func finishStoppingSession(with output: RecordedSessionOutput?) {
        isRecording = false
        shouldStopRecording = false
        isFinishingRecording = false
        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
        recordingStartTime = nil
        recordingURL = nil
        recordingTrackingDataURL = nil
        recordingCropRect = .zero
        recordingRenderSize = .zero
        recordingSourceCanvasSize = .zero
        recordedTrackFrames = []
        recordedRallyIntervals = []
        recordedFeedbackEvents = []
        currentRecordedRallyStartTime = nil
        lastRecordedFrameTime = 0
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
            completion?(output)
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
        transitionRallyState(to: newState, playFeedback: playFeedback, timestamp: lastRecordedFrameTime)
    }

    private func transitionRallyState(to newState: RallyState, playFeedback: Bool, timestamp: Double?) {
        let transitionResult: (state: RallyState?, feedback: [String]) = rallyAnalysisQueue.sync {
            let previousState = currentRallyState
            if previousState == .end, newState == .start, CACurrentMediaTime() < audioFeedbackMuteUntil {
                rallyMotionState.stillnessStartedAt = timestamp
                return (nil, [])
            }

            currentRallyState = newState

            if let timestamp, timestamp.isFinite {
                self.recordRallyTransitionLocked(from: previousState, to: newState, timestamp: timestamp)
            }

            switch newState {
            case .start:
                if previousState != .start {
                    resetRallyAnalysisStateLocked()
                    DispatchQueue.main.async {
                        self.afterRallyDebugItems = []
                    }
                    return (newState, [RallyFeedback.rallyStart.rawValue])
                }
                return (newState, [])

            case .end:
                let feedback = liveFeedbackMode == .afterRally && playFeedback && previousState == .start
                    ? afterRallyFeedbackMessagesLocked()
                    : []
                if liveFeedbackMode == .afterRally && playFeedback && previousState == .start {
                    recordAfterRallyFeedbackEventsLocked()
                }
                resetRallyAnalysisStateLocked()
                if !feedback.isEmpty {
                    audioFeedbackMuteUntil = CACurrentMediaTime() + RallyFeedbackSpeaker.estimatedDuration(for: feedback)
                    return (newState, feedback)
                }
                let endCue = playFeedback && previousState == .start
                    ? [RallyFeedback.rallyEnd.rawValue]
                    : []
                if !endCue.isEmpty {
                    audioFeedbackMuteUntil = CACurrentMediaTime() + RallyFeedbackSpeaker.estimatedDuration(for: endCue)
                }
                return (newState, endCue)
            }
        }

        guard let transitionedState = transitionResult.state else { return }

        updateRallyState(transitionedState)

        let feedbackToPlay = transitionResult.feedback
        guard !feedbackToPlay.isEmpty else { return }
        let muteDuration = rallyFeedbackSpeaker.speak(feedbackToPlay)
        rallyAnalysisQueue.async {
            self.audioFeedbackMuteUntil = max(self.audioFeedbackMuteUntil, CACurrentMediaTime() + muteDuration)
        }
    }

    private func recordRallyTransitionLocked(from previousState: RallyState, to newState: RallyState, timestamp: Double) {
        let normalizedTimestamp = normalizeRecordingTimestamp(timestamp)

        switch (previousState, newState) {
        case (.end, .start):
            currentRecordedRallyStartTime = normalizedTimestamp
        case (.start, .end):
            if let startTime = currentRecordedRallyStartTime {
                let endTime = max(normalizedTimestamp, startTime)
                recordedRallyIntervals.append(RallyInterval(startTime: startTime, endTime: endTime))
                currentRecordedRallyStartTime = nil
            }
        default:
            break
        }
    }

    private func recordAfterRallyFeedbackEventsLocked() {
        guard recordingHandednessMode == .rightRight else { return }
        guard let rallyInterval = recordedRallyIntervals.last else { return }

        for event in afterRallyFeedbackEvents {
            let eventTime = min(
                max(normalizeRecordingTimestamp(event.triggeredAt), rallyInterval.startTime),
                rallyInterval.endTime
            )
            recordedFeedbackEvents.append(
                TrackingSidecarFeedbackEvent(
                    kind: movementEventKind(for: event.kind).rawValue,
                    playerLabel: event.playerID,
                    startTime: eventTime,
                    endTime: min(rallyInterval.endTime, eventTime + 0.3)
                )
            )
        }
    }

    private func movementEventKind(for kind: AfterRallyFeedbackEvent.Kind) -> MovementEvent.Kind {
        switch kind {
        case .hittingZoneOverstay:
            return .failedToClearHittingZone
        case .wrongExitSide:
            return .wrongExitDirection
        case .directRetreatToWaiting:
            return .directRetreatToWaiting
        case .exitZoneOverstay:
            return .missingWaitingRecovery
        }
    }

    private func resetRallyAnalysisStateLocked() {
        rallyMotionState = RallyMotionState()
        activeHitterState = nil
        pendingDirectionalCue = nil
        livePlayerFeedbackPhases = [:]
        afterRallyFeedbackEvents = []
    }

    private func immediateExitDirectionCue(for point: CGPoint) -> RallyFeedback? {
        guard recordingHandednessMode == .rightRight else { return nil }
        return point.x < 0 ? .moveLeft : .moveRight
    }

    private func playImmediateFeedbackIfPossible(_ feedback: String) {
        let muteDuration = rallyFeedbackSpeaker.speak([feedback])
        rallyAnalysisQueue.async {
            self.audioFeedbackMuteUntil = CACurrentMediaTime() + muteDuration
        }
    }

    private func updateRallyFeedbackTracking(with players: [TrackedPlayerBox], timestamp: Double) {
        guard timestamp.isFinite else { return }

        let playerLookup = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        let hitterID = players.first(where: \.isCurrentHitter)?.id

        rallyAnalysisQueue.async {
            guard self.currentRallyState == .start else { return }

            switch self.liveFeedbackMode {
            case .duringRally:
                self.resolvePendingDirectionalCueLocked(
                    using: playerLookup,
                    currentHitterID: hitterID,
                    timestamp: timestamp
                )
            case .afterRally:
                self.updateAfterRallyFeedbackTrackingLocked(
                    using: playerLookup,
                    currentHitterID: hitterID,
                    timestamp: timestamp
                )
            }

            guard
                let hitterID,
                playerLookup[hitterID]?.playerAreaPoint != nil,
                playerLookup.keys.contains(where: { $0 != hitterID })
            else {
                return
            }

            if let activeHitterState = self.activeHitterState {
                if activeHitterState.hitterID != hitterID {
                    self.activeHitterState = ActiveHitterState(
                        hitterID: hitterID,
                        startedAt: timestamp
                    )
                    if self.liveFeedbackMode == .duringRally {
                        self.pendingDirectionalCue = PendingDirectionalCue(
                            hitterID: hitterID,
                            dueTime: timestamp + RallyFeedbackConstants.directionalCueDelay
                        )
                    }
                    return
                }
                return
            }

            self.activeHitterState = ActiveHitterState(
                hitterID: hitterID,
                startedAt: timestamp
            )
            if self.liveFeedbackMode == .duringRally {
                self.pendingDirectionalCue = PendingDirectionalCue(
                    hitterID: hitterID,
                    dueTime: timestamp + RallyFeedbackConstants.directionalCueDelay
                )
            }
        }
    }

    private func spokenDirectionalCue(for feedback: RallyFeedback, playerID: String) -> String {
        let prefix: String
        switch playerID {
        case "Player1":
            prefix = "Player 1"
        case "Player2":
            prefix = "Player 2"
        default:
            prefix = "Player"
        }
        return "\(prefix), \(feedback.rawValue)"
    }

    private func resolvePendingDirectionalCueLocked(
        using playerLookup: [String: TrackedPlayerBox],
        currentHitterID: String?,
        timestamp: Double
    ) {
        guard let pendingDirectionalCue else { return }
        guard timestamp >= pendingDirectionalCue.dueTime else { return }
        defer { self.pendingDirectionalCue = nil }

        guard
            currentHitterID == pendingDirectionalCue.hitterID,
            let hitterPoint = playerLookup[pendingDirectionalCue.hitterID]?.playerAreaPoint,
            let exitCue = immediateExitDirectionCue(for: hitterPoint)
        else {
            return
        }

        let directedCue = spokenDirectionalCue(for: exitCue, playerID: pendingDirectionalCue.hitterID)
        DispatchQueue.global(qos: .userInitiated).async {
            self.playImmediateFeedbackIfPossible(directedCue)
        }
    }

    private func updateAfterRallyFeedbackTrackingLocked(
        using playerLookup: [String: TrackedPlayerBox],
        currentHitterID: String?,
        timestamp: Double
    ) {
        guard recordingHandednessMode == .rightRight else {
            livePlayerFeedbackPhases = [:]
            afterRallyFeedbackEvents = []
            publishAfterRallyDebugItemsLocked()
            return
        }

        for playerID in TrackingConstants.playerLabels {
            guard
                let player = playerLookup[playerID],
                let point = player.playerAreaPoint
            else {
                livePlayerFeedbackPhases.removeValue(forKey: playerID)
                continue
            }

            if currentHitterID == playerID {
                let side = liveHittingSide(for: point)
                if liveZone(for: point, side: side) == .hitting {
                    if let phase = livePlayerFeedbackPhases[playerID],
                       phase.side == side,
                       phase.leftHittingZoneAt == nil {
                        // Keep current phase.
                    } else {
                        livePlayerFeedbackPhases[playerID] = LivePlayerFeedbackPhase(
                            side: side,
                            hittingZoneEnteredAt: timestamp,
                            leftHittingZoneAt: nil,
                            enteredExitZoneAt: nil,
                            skippedExitZoneAt: nil,
                            partnerBecameHitterAt: nil
                        )
                    }
                }
            }

            guard var phase = livePlayerFeedbackPhases[playerID] else { continue }
            let zone = liveZone(for: point, side: phase.side)

            if currentHitterID != playerID, phase.enteredExitZoneAt != nil, phase.partnerBecameHitterAt == nil {
                phase.partnerBecameHitterAt = timestamp
            }

            switch zone {
            case .hitting:
                if (timestamp - phase.hittingZoneEnteredAt) >= RallyFeedbackConstants.hittingZoneOverstayDuration {
                    afterRallyFeedbackEvents.insert(
                        AfterRallyFeedbackEvent(playerID: playerID, kind: .hittingZoneOverstay, triggeredAt: timestamp)
                    )
                }
            case .correctExit:
                if phase.leftHittingZoneAt == nil {
                    phase.leftHittingZoneAt = timestamp
                }
                if phase.enteredExitZoneAt == nil {
                    phase.enteredExitZoneAt = timestamp
                }
                if let partnerBecameHitterAt = phase.partnerBecameHitterAt,
                   (timestamp - partnerBecameHitterAt) >= RallyFeedbackConstants.exitToWaitingTransitionDuration {
                    afterRallyFeedbackEvents.insert(
                        AfterRallyFeedbackEvent(playerID: playerID, kind: .exitZoneOverstay, triggeredAt: timestamp)
                    )
                }
            case .wrongExit:
                if phase.leftHittingZoneAt == nil {
                    phase.leftHittingZoneAt = timestamp
                }
                afterRallyFeedbackEvents.insert(
                    AfterRallyFeedbackEvent(playerID: playerID, kind: .wrongExitSide, triggeredAt: timestamp)
                )
            case .waiting:
                if phase.leftHittingZoneAt == nil {
                    phase.leftHittingZoneAt = timestamp
                }
                if phase.enteredExitZoneAt == nil, phase.skippedExitZoneAt == nil {
                    phase.skippedExitZoneAt = timestamp
                    afterRallyFeedbackEvents.insert(
                        AfterRallyFeedbackEvent(playerID: playerID, kind: .directRetreatToWaiting, triggeredAt: timestamp)
                    )
                }
            case .other:
                if phase.leftHittingZoneAt == nil {
                    phase.leftHittingZoneAt = timestamp
                }
            }

            livePlayerFeedbackPhases[playerID] = phase
        }

        publishAfterRallyDebugItemsLocked()
    }

    private func afterRallyFeedbackMessagesLocked() -> [String] {
        guard recordingHandednessMode == .rightRight else { return [] }

        return afterRallyFeedbackEvents
            .sorted { lhs, rhs in
                if lhs.playerID == rhs.playerID {
                    return afterRallyFeedbackPriority(lhs.kind) < afterRallyFeedbackPriority(rhs.kind)
                }
                return lhs.playerID < rhs.playerID
            }
            .map { event in
                switch event.kind {
                case .hittingZoneOverstay:
                    return "\(spokenPlayerName(for: event.playerID)), you stayed in the hitting zone too long after the shot. Move out earlier to improve the next transition."
                case .wrongExitSide:
                    return "\(spokenPlayerName(for: event.playerID)), after hitting, you moved to the wrong side. Exit toward the outside of your hitting side so your partner has space to step in."
                case .directRetreatToWaiting:
                    return "\(spokenPlayerName(for: event.playerID)), don't move straight back after hitting. Exit to the outside first, or you will run into your partner."
                case .exitZoneOverstay:
                    return "\(spokenPlayerName(for: event.playerID)), don't stop on the side after rotating out. Move back earlier to reset for the next shot."
                }
            }
    }

    private func afterRallyDebugItemsLocked() -> [AfterRallyDebugItem] {
        afterRallyFeedbackEvents
            .sorted { lhs, rhs in
                if lhs.playerID == rhs.playerID {
                    return afterRallyFeedbackPriority(lhs.kind) < afterRallyFeedbackPriority(rhs.kind)
                }
                return lhs.playerID < rhs.playerID
            }
            .map { event in
                AfterRallyDebugItem(
                    code: afterRallyFeedbackCode(for: event),
                    label: afterRallyFeedbackCodeLabel(for: event)
                )
            }
    }

    private func afterRallyFeedbackPriority(_ kind: AfterRallyFeedbackEvent.Kind) -> Int {
        switch kind {
        case .hittingZoneOverstay:
            return 0
        case .wrongExitSide:
            return 1
        case .directRetreatToWaiting:
            return 2
        case .exitZoneOverstay:
            return 3
        }
    }

    private func spokenPlayerName(for playerID: String) -> String {
        switch playerID {
        case "Player1":
            return "Player 1"
        case "Player2":
            return "Player 2"
        default:
            return "Player"
        }
    }

    private func afterRallyFeedbackCode(for event: AfterRallyFeedbackEvent) -> Int {
        switch (event.playerID, event.kind) {
        case ("Player1", .hittingZoneOverstay):
            return 1
        case ("Player1", .wrongExitSide):
            return 2
        case ("Player1", .directRetreatToWaiting):
            return 3
        case ("Player1", .exitZoneOverstay):
            return 4
        case ("Player2", .hittingZoneOverstay):
            return 5
        case ("Player2", .wrongExitSide):
            return 6
        case ("Player2", .directRetreatToWaiting):
            return 7
        case ("Player2", .exitZoneOverstay):
            return 8
        default:
            return 0
        }
    }

    private func afterRallyFeedbackCodeLabel(for event: AfterRallyFeedbackEvent) -> String {
        switch (event.playerID, event.kind) {
        case ("Player1", .hittingZoneOverstay):
            return "1: P1 Hitting"
        case ("Player1", .wrongExitSide):
            return "2: P1 Wrong Exit"
        case ("Player1", .directRetreatToWaiting):
            return "3: P1 Direct Back"
        case ("Player1", .exitZoneOverstay):
            return "4: P1 Exit"
        case ("Player2", .hittingZoneOverstay):
            return "5: P2 Hitting"
        case ("Player2", .wrongExitSide):
            return "6: P2 Wrong Exit"
        case ("Player2", .directRetreatToWaiting):
            return "7: P2 Direct Back"
        case ("Player2", .exitZoneOverstay):
            return "8: P2 Exit"
        default:
            return "0: Unknown"
        }
    }

    private func publishAfterRallyDebugItemsLocked() {
        let items = afterRallyDebugItemsLocked()
        DispatchQueue.main.async {
            self.afterRallyDebugItems = items
        }
    }

    private func liveHittingSide(for point: CGPoint) -> LiveHittingSide {
        point.x < 0 ? .left : .right
    }

    private func liveZone(for point: CGPoint, side: LiveHittingSide) -> LiveCourtRoleZone {
        if liveHittingZoneRect(for: side).contains(point) {
            return .hitting
        }
        if liveExitZoneRect(for: side).contains(point) {
            return .correctExit
        }
        if liveExitZoneRect(for: oppositeSide(of: side)).contains(point) {
            return .wrongExit
        }
        if liveWaitingZoneRect(for: side).contains(point) {
            return .waiting
        }
        return .other
    }

    private func liveHittingZoneRect(for side: LiveHittingSide) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: -1.0, y: 0.0, width: 1.0, height: RallyFeedbackConstants.hittingZoneMaxY)
        case .right:
            return CGRect(x: 0.0, y: 0.0, width: 1.0, height: RallyFeedbackConstants.hittingZoneMaxY)
        }
    }

    private func liveExitZoneRect(for side: LiveHittingSide) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: -8.0, y: 0.0, width: 7.0, height: 8.0)
        case .right:
            return CGRect(x: 1.0, y: 0.0, width: 7.0, height: 8.0)
        }
    }

    private func liveWaitingZoneRect(for side: LiveHittingSide) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: -1.2, y: RallyFeedbackConstants.waitingZoneMinY, width: 1.3, height: 80.0)
        case .right:
            return CGRect(x: -0.1, y: RallyFeedbackConstants.waitingZoneMinY, width: 1.3, height: 80.0)
        }
    }

    private func oppositeSide(of side: LiveHittingSide) -> LiveHittingSide {
        switch side {
        case .left:
            return .right
        case .right:
            return .left
        }
    }

    private func updateRallyStateFromPlayerMovement(with players: [TrackedPlayerBox], timestamp: Double) {
        guard timestamp.isFinite else { return }

        let trackedPlayers = TrackingConstants.playerLabels.compactMap { label in
            players.first(where: { $0.id == label })
        }
        guard trackedPlayers.count == TrackingConstants.playerLabels.count else { return }

        rallyAnalysisQueue.async {
            if self.currentRallyState == .end, CACurrentMediaTime() < self.audioFeedbackMuteUntil {
                self.rallyMotionState.stillnessAnchorPlayers = trackedPlayers
                self.rallyMotionState.stillnessStartedAt = timestamp
                return
            }

            if self.rallyMotionState.stillnessAnchorPlayers.count != trackedPlayers.count {
                self.rallyMotionState.stillnessAnchorPlayers = trackedPlayers
                self.rallyMotionState.stillnessStartedAt = timestamp
                return
            }

            let isStill = self.playersAreStillRelativeToAnchorLocked(trackedPlayers)
            if !isStill {
                self.rallyMotionState.stillnessAnchorPlayers = trackedPlayers
                self.rallyMotionState.stillnessStartedAt = timestamp
                if self.currentRallyState == .start {
                    self.rallyMotionState.detectedLargeMovementSinceStart = true
                }
                return
            }

            if self.rallyMotionState.stillnessStartedAt == nil {
                self.rallyMotionState.stillnessStartedAt = timestamp
            }

            let stillnessStartedAt = self.rallyMotionState.stillnessStartedAt ?? timestamp
            guard (timestamp - stillnessStartedAt) >= RallyDetectionConstants.stillnessDuration else {
                return
            }

            switch self.currentRallyState {
            case .end:
                self.rallyMotionState.detectedLargeMovementSinceStart = false
                self.rallyMotionState.stillnessAnchorPlayers = trackedPlayers
                self.rallyMotionState.stillnessStartedAt = timestamp
                DispatchQueue.main.async {
                    self.transitionRallyState(to: .start, playFeedback: false, timestamp: timestamp)
                }
            case .start:
                guard self.rallyMotionState.detectedLargeMovementSinceStart else { return }
                self.rallyMotionState.detectedLargeMovementSinceStart = false
                self.rallyMotionState.stillnessAnchorPlayers = trackedPlayers
                self.rallyMotionState.stillnessStartedAt = timestamp
                DispatchQueue.main.async {
                    self.transitionRallyState(to: .end, playFeedback: true, timestamp: timestamp)
                }
            }
        }
    }

    private func playersAreStillRelativeToAnchorLocked(_ players: [TrackedPlayerBox]) -> Bool {
        let anchorLookup = Dictionary(uniqueKeysWithValues: rallyMotionState.stillnessAnchorPlayers.map { ($0.id, $0) })

        for player in players {
            guard let anchorPlayer = anchorLookup[player.id] else {
                return false
            }

            let centerShift = hypot(
                player.boundingBox.midX - anchorPlayer.boundingBox.midX,
                player.boundingBox.midY - anchorPlayer.boundingBox.midY
            )
            let widthShift = abs(player.boundingBox.width - anchorPlayer.boundingBox.width)
            let heightShift = abs(player.boundingBox.height - anchorPlayer.boundingBox.height)

            if centerShift > RallyDetectionConstants.maximumStillCenterShift ||
                widthShift > RallyDetectionConstants.maximumStillSizeShift ||
                heightShift > RallyDetectionConstants.maximumStillSizeShift {
                return false
            }
        }

        return true
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
                    updateRallyStateFromPlayerMovement(with: [], timestamp: timestamp)
                    appendRecordedTrackFrame(time: timestamp, players: [])
                } else if !latestTrackedPlayers.isEmpty {
                    updateRallyStateFromPlayerMovement(with: latestTrackedPlayers, timestamp: timestamp)
                    updateTrackedPlayers(latestTrackedPlayers)
                    updateTrackingDebugInfo(
                        source: detectionResult.source,
                        rectangleCandidates: detectionResult.rectangleCandidates.count,
                        bodyPoseCandidates: detectionResult.bodyPoseCandidates.count,
                        selectedCandidates: boundingBoxes.count,
                        players: latestTrackedPlayers
                    )
                    appendRecordedTrackFrame(time: timestamp, players: latestTrackedPlayers)
                } else {
                    updateTrackingDebugInfo(
                        source: detectionResult.source,
                        rectangleCandidates: detectionResult.rectangleCandidates.count,
                        bodyPoseCandidates: detectionResult.bodyPoseCandidates.count,
                        selectedCandidates: boundingBoxes.count,
                        players: []
                    )
                    updateRallyStateFromPlayerMovement(with: [], timestamp: timestamp)
                    appendRecordedTrackFrame(time: timestamp, players: [])
                }
                return
            }

            missedDetectionFrames = 0
            let players = associatedPlayers(from: boundingBoxes, previousPlayers: latestTrackedPlayers)
            let smoothedPlayers = smoothedPlayers(from: players)
            let annotatedPlayers = annotatePlayers(smoothedPlayers)
            updateRallyStateFromPlayerMovement(with: annotatedPlayers, timestamp: timestamp)
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
            appendRecordedTrackFrame(time: timestamp, players: annotatedPlayers)
        } catch {
            print("Failed to detect live players: \(error)")
            updateTrackingDebugInfo(
                source: "error",
                rectangleCandidates: 0,
                bodyPoseCandidates: 0,
                selectedCandidates: 0,
                players: latestTrackedPlayers
            )
            updateRallyStateFromPlayerMovement(with: latestTrackedPlayers, timestamp: timestamp)
            appendRecordedTrackFrame(time: timestamp, players: latestTrackedPlayers)
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
            .map(\.boundingBox)

        if strictMatches.count >= TrackingConstants.playerLabels.count {
            return HumanDetectionResult(
                source: "rectangles-strict",
                rectangleCandidates: observations.map(\.boundingBox),
                bodyPoseCandidates: [],
                selectedCandidates: selectNearestTwoPlayerBoxes(from: strictMatches)
            )
        }

        let relaxedRectangleMatches = observations
            .filter { observation in
                observation.confidence >= TrackingConstants.fallbackHumanConfidence &&
                (observation.boundingBox.width * observation.boundingBox.height) >= TrackingConstants.fallbackHumanArea
            }
            .map(\.boundingBox)

        if relaxedRectangleMatches.count >= TrackingConstants.playerLabels.count {
            return HumanDetectionResult(
                source: "rectangles-relaxed",
                rectangleCandidates: observations.map(\.boundingBox),
                bodyPoseCandidates: [],
                selectedCandidates: selectNearestTwoPlayerBoxes(from: relaxedRectangleMatches)
            )
        }

        let bodyPoseBoxes = try detectBodyPoseBoundingBoxes(in: pixelBuffer)
        if bodyPoseBoxes.count >= relaxedRectangleMatches.count {
            return HumanDetectionResult(
                source: "body-pose",
                rectangleCandidates: observations.map(\.boundingBox),
                bodyPoseCandidates: bodyPoseBoxes,
                selectedCandidates: selectNearestTwoPlayerBoxes(from: bodyPoseBoxes)
            )
        }

        return HumanDetectionResult(
            source: "rectangles-fallback",
            rectangleCandidates: observations.map(\.boundingBox),
            bodyPoseCandidates: bodyPoseBoxes,
            selectedCandidates: selectNearestTwoPlayerBoxes(from: relaxedRectangleMatches)
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
        stableTrackedPlayers(previousPlayers: previousPlayers, candidateBoxes: boundingBoxes)
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

            return TrackedPlayerBox(
                id: player.id,
                label: player.label,
                boundingBox: smoothedBox
            )
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
        normalizedPlayerFootPoint(for: boundingBox)
    }

    private func lateralPositionLabel(for point: CGPoint) -> String {
        switch point.x {
        case ..<(-0.33):
            return "left"
        case 0.33...:
            return "right"
        default:
            return "center"
        }
    }

    private func depthPositionLabel(for point: CGPoint) -> String {
        switch point.y {
        case ..<0.45:
            return "front"
        case 1.15...:
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
        case ..<0.35:
            spacingSummary = "間距過近"
        case 1.35...:
            spacingSummary = "間距過大"
        default:
            spacingSummary = "間距正常"
        }

        let holeSummary: String
        if mappedPlayers.allSatisfy({ $0.x < -0.2 }) {
            holeSummary = "右側站位漏洞"
        } else if mappedPlayers.allSatisfy({ $0.x > 0.2 }) {
            holeSummary = "左側站位漏洞"
        } else if mappedPlayers.allSatisfy({ $0.y < 0.45 }) {
            holeSummary = "後場站位漏洞"
        } else if mappedPlayers.allSatisfy({ $0.y > 1.05 }) {
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
            let boxSummary = "box:\(formatDebugValue(player.boundingBox.midX)),\(formatDebugValue(player.boundingBox.midY))"
            let footSummary = player.footPoint.map {
                " foot:\(formatDebugValue($0.x)),\(formatDebugValue($0.y))"
            } ?? " foot:nil"
            let areaSummary = player.playerAreaPoint.map {
                " area:\(formatDebugValue($0.x)),\(formatDebugValue($0.y))"
            } ?? " area:nil"
            let hitterSummary = player.isCurrentHitter ? " hitter" : ""
            return "\(player.label) \(boxSummary)\(footSummary)\(areaSummary)\(hitterSummary)"
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

    private func appendRecordedTrackFrame(time: Double, players: [TrackedPlayerBox]) {
        guard isRecording, time.isFinite else { return }
        let normalizedTime = normalizeRecordingTimestamp(time)
        lastRecordedFrameTime = normalizedTime
        recordedTrackFrames.append(PlayerTrackFrame(time: normalizedTime, players: players))
    }

    private func normalizeRecordingTimestamp(_ time: Double) -> Double {
        if let recordingStartTime {
            return max(time - recordingStartTime.seconds, 0)
        }
        if let firstRecordedTime = recordedTrackFrames.first?.time {
            return max(time - firstRecordedTime, 0)
        }
        return max(time, 0)
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

    private func writeTrackingSidecarIfNeeded() -> URL? {
        guard let recordingTrackingDataURL else { return nil }

        if let startTime = currentRecordedRallyStartTime {
            let endTime = max(lastRecordedFrameTime, startTime)
            recordedRallyIntervals.append(RallyInterval(startTime: startTime, endTime: endTime))
            currentRecordedRallyStartTime = nil
        }

        let sidecar = TrackingSidecarFile(
            frames: recordedTrackFrames.map(TrackingSidecarFrame.init),
            rallyIntervals: recordedRallyIntervals,
            feedbackEvents: recordedFeedbackEvents,
            handednessMode: recordingHandednessMode
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(sidecar)
            try data.write(to: recordingTrackingDataURL, options: .atomic)
            return recordingTrackingDataURL
        } catch {
            print("Failed to write tracking sidecar: \(error)")
            try? FileManager.default.removeItem(at: recordingTrackingDataURL)
            return nil
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
                    let trackingDataURL = self.writeTrackingSidecarIfNeeded()
                    self.finishStoppingSession(
                        with: RecordedSessionOutput(
                            videoURL: recordingURL,
                            trackingDataURL: trackingDataURL
                        )
                    )
                } else {
                    if let error = assetWriter.error {
                        print("Failed to finish writing video: \(error)")
                    }

                    if let recordingURL {
                        try? FileManager.default.removeItem(at: recordingURL)
                    }
                    if let trackingDataURL = self.recordingTrackingDataURL {
                        try? FileManager.default.removeItem(at: trackingDataURL)
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
