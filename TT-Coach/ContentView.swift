import SwiftUI
import AVFoundation
import AVKit
import UIKit
import Vision

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var speechCoach = SpeechCoach()
    @StateObject private var videoLibrary = VideoLibraryManager()

    @State private var isCoachingMode = false
    @State private var permissionMessage: String?
    @State private var isVideoLibraryPresented = false
    @State private var isClosingSession = false
    @State private var showSaveRecordingDialog = false

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
                    cameraManager.requestPermissionAndStart { started in
                        if started {
                            isCoachingMode = true
                        } else {
                            permissionMessage = "請先允許相機權限，才能進入 AI 教練模式。"
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

                Text("按下開始後會開啟相機、進入 AI 教練模式，並自動開始錄影")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.bottom, 40)
            }
        }
    }

    private var coachingView: some View {
        ZStack {
            CameraPreview(session: cameraManager.session, trackedPlayers: cameraManager.trackedPlayers)
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .center) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)

                        Text("REC")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.65))
                    .foregroundColor(.white)
                    .clipShape(Capsule())

                    Spacer()

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
                .padding()

                Spacer()

                GeometryReader { geometry in
                    let horizontalPadding: CGFloat = 20
                    let spacing: CGFloat = 16
                    let padWidth = max((geometry.size.width - (horizontalPadding * 2) - spacing) / 2, 140)

                    HStack(alignment: .bottom, spacing: spacing) {
                        DirectionPad(title: "Player1") { command in
                            speechCoach.speak(command.rawValue, side: .left)
                        }
                        .frame(width: padWidth)

                        DirectionPad(title: "Player2") { command in
                            speechCoach.speak(command.rawValue, side: .right)
                        }
                        .frame(width: padWidth)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, horizontalPadding)
                }
                .frame(height: 220)
                .padding(.bottom, 36)
            }
        }
    }

    private func closeCoachingMode(saveRecording: Bool) {
        isClosingSession = true

        cameraManager.stopSession(saveRecording: saveRecording) { temporaryURL in
            if let temporaryURL, let savedVideo = videoLibrary.saveVideo(from: temporaryURL) {
                print("Saved video at \(savedVideo.url)")
            }

            isClosingSession = false
            isCoachingMode = false
        }
    }
}

struct DirectionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .background(.ultraThinMaterial)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

enum DirectionCommand: String {
    case forward = "Forward"
    case back = "Back"
    case left = "Left"
    case right = "Right"
}

struct DirectionPad: View {
    let title: String
    let action: (DirectionCommand) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())

            VStack(spacing: 14) {
                DirectionButton(title: DirectionCommand.forward.rawValue) {
                    action(.forward)
                }

                HStack(spacing: 12) {
                    DirectionButton(title: DirectionCommand.left.rawValue) {
                        action(.left)
                    }

                    DirectionButton(title: DirectionCommand.back.rawValue) {
                        action(.back)
                    }

                    DirectionButton(title: DirectionCommand.right.rawValue) {
                        action(.right)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct TrackedPlayerBox: Identifiable, Equatable {
    let id: String
    let label: String
    let boundingBox: CGRect
}

struct SavedVideo: Identifiable, Hashable {
    let url: URL
    let createdAt: Date

    var id: URL { url }

    var title: String {
        url.deletingPathExtension().lastPathComponent
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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                InlineVideoPlayer(player: player, videoGravity: .resizeAspectFill)
                    .ignoresSafeArea()
                    .rotationEffect(.degrees(presentationInfo.rotationDegrees))
            }
            .navigationTitle(video.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                presentationInfo = Self.loadVideoPresentationInfo(for: video.url)
                let item = AVPlayerItem(url: video.url)
                player.replaceCurrentItem(with: item)
                player.play()
            }
            .onDisappear {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
        }
    }

    private static func loadVideoPresentationInfo(for url: URL) -> VideoPresentationInfo {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return VideoPresentationInfo() }

        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)

        guard width > 0, height > 0 else { return VideoPresentationInfo() }

        let aspectRatio = width / height
        if aspectRatio > 1 {
            return VideoPresentationInfo(rotationDegrees: 90)
        } else {
            return VideoPresentationInfo(rotationDegrees: 0)
        }
    }
}

struct VideoPresentationInfo {
    var rotationDegrees: Double = 0
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

final class SpeechCoach: ObservableObject {
    enum AudioSide {
        case left
        case right
    }

    private let synthesizer = AVSpeechSynthesizer()

    init() {
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String, side: AudioSide) {
        synthesizer.stopSpeaking(at: .immediate)

        if let error = configureAudioSession(for: side) {
            print("Failed to configure audio session: \(error)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    private func configureAudioSession(for side: AudioSide) -> Error? {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            synthesizer.outputChannels = nil
            return error
        }

        let channels = session.currentRoute.outputs
            .compactMap(\.channels)
            .flatMap { $0 }
            .sorted { $0.channelNumber < $1.channelNumber }

        guard channels.count >= 2 else {
            synthesizer.outputChannels = nil
            return nil
        }

        switch side {
        case .left:
            synthesizer.outputChannels = [channels.first!]
        case .right:
            synthesizer.outputChannels = [channels.last!]
        }

        return nil
    }
}

final class CameraManager: NSObject, ObservableObject {
    enum RecordingDecision {
        case save
        case discard
    }

    private enum TrackingConstants {
        static let playerLabels = ["Player1", "Player2"]
    }

    let session = AVCaptureSession()
    @Published private(set) var trackedPlayers: [TrackedPlayerBox] = []

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "TTCoach.CameraSessionQueue", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "TTCoach.HumanDetectionQueue", qos: .userInitiated)
    private let ciContext = CIContext()

    private var isConfigured = false
    private var frameCounter = 0
    private var latestTrackedPlayers: [TrackedPlayerBox] = []
    private var trackingRequests: [VNTrackObjectRequest] = []
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

    func requestPermissionAndStart(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession()
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.configureAndStartSession()
                }

                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            print("Camera permission denied or restricted.")
            completion(false)
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

            guard !self.session.isRunning else {
                self.startRecordingIfNeeded()
                return
            }

            self.session.startRunning()
            self.startRecordingIfNeeded()
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
        } catch {
            print("Failed to create camera input: \(error)")
        }

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: visionQueue)

        guard session.canAddOutput(videoDataOutput) else {
            print("Failed to add video data output.")
            return
        }

        session.addOutput(videoDataOutput)

        if let connection = videoDataOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private func startRecordingIfNeeded() {
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

        if session.isRunning {
            session.stopRunning()
        }

        latestTrackedPlayers = []
        trackingRequests = []
        frameCounter = 0

        DispatchQueue.main.async {
            self.trackedPlayers = []
        }

        let completion = stopCompletion
        stopCompletion = nil

        DispatchQueue.main.async {
            completion?(outputURL)
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard output === videoDataOutput else { return }
        appendFrameToRecording(sampleBuffer)

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if trackingRequests.count == TrackingConstants.playerLabels.count {
            trackPlayers(in: pixelBuffer)
        } else {
            frameCounter += 1
            guard frameCounter.isMultiple(of: 3) else { return }
            detectInitialPlayers(in: pixelBuffer)
        }
    }

    private func detectInitialPlayers(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            try handler.perform([request])

            let observations = (request.results ?? [])
                .sorted { $0.boundingBox.midX < $1.boundingBox.midX }

            guard observations.count >= TrackingConstants.playerLabels.count else { return }

            let selectedObservations = Array(observations.prefix(TrackingConstants.playerLabels.count))
            trackingRequests = selectedObservations.map { observation in
                let trackRequest = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: observation.boundingBox))
                trackRequest.trackingLevel = .accurate
                return trackRequest
            }

            let players = zip(selectedObservations, TrackingConstants.playerLabels).map { observation, label in
                TrackedPlayerBox(id: label, label: label, boundingBox: observation.boundingBox)
            }

            updateTrackedPlayers(players)
        } catch {
            print("Failed to detect initial players: \(error)")
        }
    }

    private func trackPlayers(in pixelBuffer: CVPixelBuffer) {
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            try handler.perform(trackingRequests)

            var updatedPlayers: [TrackedPlayerBox] = []

            for (index, request) in trackingRequests.enumerated() {
                guard
                    let observation = request.results?.first as? VNDetectedObjectObservation,
                    observation.confidence >= 0.2
                else {
                    return
                }

                request.inputObservation = observation
                updatedPlayers.append(
                    TrackedPlayerBox(
                        id: TrackingConstants.playerLabels[index],
                        label: TrackingConstants.playerLabels[index],
                        boundingBox: observation.boundingBox
                    )
                )
            }

            updateTrackedPlayers(updatedPlayers)
        } catch {
            print("Failed to track players: \(error)")
        }
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

        context.setStrokeColor(UIColor.systemGreen.cgColor)
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
            context.stroke(rect.insetBy(dx: 1, dy: 1))

            let bubbleSize = CGSize(width: 132, height: 52)
            let labelRect = CGRect(x: rect.minX, y: max(rect.minY - 34, 8), width: 120, height: 28)
            let bubbleOrigin = CGPoint(
                x: min(max(rect.midX - (bubbleSize.width / 2), 12), CGFloat(width) - bubbleSize.width - 12),
                y: max(labelRect.minY - bubbleSize.height - 10, 12)
            )
            let bubbleRect = CGRect(origin: bubbleOrigin, size: bubbleSize)
            let bubblePath = UIBezierPath(roundedRect: bubbleRect, cornerRadius: 16)

            let tailPath = UIBezierPath()
            tailPath.move(to: CGPoint(x: bubbleRect.midX - 10, y: bubbleRect.maxY))
            tailPath.addLine(to: CGPoint(x: bubbleRect.midX, y: bubbleRect.maxY + 10))
            tailPath.addLine(to: CGPoint(x: bubbleRect.midX + 10, y: bubbleRect.maxY))
            tailPath.close()

            context.setFillColor(UIColor.white.cgColor)
            context.addPath(bubblePath.cgPath)
            context.fillPath()
            context.addPath(tailPath.cgPath)
            context.fillPath()

            let bubbleTextAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            drawVideoText(
                "sample",
                in: bubbleRect.insetBy(dx: 16, dy: 12),
                attributes: bubbleTextAttributes,
                context: context,
                canvasHeight: height
            )

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
        CGRect(
            x: 1 - orientedBoundingBox.origin.y - orientedBoundingBox.height,
            y: orientedBoundingBox.origin.x,
            width: orientedBoundingBox.height,
            height: orientedBoundingBox.width
        )
    }

    private func makeRecordingGeometry(canvasSize: CGSize) -> (cropRect: CGRect, renderSize: CGSize) {
        let screenSize = UIScreen.main.bounds.size
        let targetAspect = screenSize.width / screenSize.height

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

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.updateTrackedPlayers(trackedPlayers)
    }
}

final class PreviewView: UIView {
    private let overlayLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        overlayLayer.masksToBounds = true
        layer.addSublayer(overlayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayLayer.frame = bounds
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func updateTrackedPlayers(_ players: [TrackedPlayerBox]) {
        overlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let positionedPlayers = players.compactMap { player -> (player: TrackedPlayerBox, rect: CGRect)? in
            let box = player.boundingBox
            let metadataRect = CGRect(
                x: box.origin.x,
                y: 1 - box.origin.y - box.size.height,
                width: box.size.width,
                height: box.size.height
            )
            let convertedRect = videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
            return (player, convertedRect)
        }
        .sorted { $0.rect.minX < $1.rect.minX }

        for (index, item) in positionedPlayers.enumerated() {
            let convertedRect = item.rect
            let displayLabel = index == 0 ? "Player1" : "Player2"
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = UIBezierPath(rect: convertedRect).cgPath
            shapeLayer.strokeColor = UIColor.systemGreen.cgColor
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.lineWidth = 3
            shapeLayer.cornerRadius = 12
            overlayLayer.addSublayer(shapeLayer)

            let bubbleLayer = CAShapeLayer()
            let bubbleSize = CGSize(width: 132, height: 52)
            let labelFrame = CGRect(
                x: convertedRect.minX,
                y: max(convertedRect.minY - 28, 8),
                width: 92,
                height: 22
            )
            let bubbleOrigin = CGPoint(
                x: min(max(convertedRect.midX - (bubbleSize.width / 2), 12), bounds.width - bubbleSize.width - 12),
                y: max(labelFrame.minY - bubbleSize.height - 10, 12)
            )
            let bubbleRect = CGRect(origin: bubbleOrigin, size: bubbleSize)
            let bubblePath = UIBezierPath(roundedRect: bubbleRect, cornerRadius: 16)
            bubbleLayer.path = bubblePath.cgPath
            bubbleLayer.fillColor = UIColor.white.cgColor
            overlayLayer.addSublayer(bubbleLayer)

            let tailLayer = CAShapeLayer()
            let tailPath = UIBezierPath()
            tailPath.move(to: CGPoint(x: bubbleRect.midX - 10, y: bubbleRect.maxY))
            tailPath.addLine(to: CGPoint(x: bubbleRect.midX, y: bubbleRect.maxY + 10))
            tailPath.addLine(to: CGPoint(x: bubbleRect.midX + 10, y: bubbleRect.maxY))
            tailPath.close()
            tailLayer.path = tailPath.cgPath
            tailLayer.fillColor = UIColor.white.cgColor
            overlayLayer.addSublayer(tailLayer)

            let bubbleTextLayer = CATextLayer()
            bubbleTextLayer.string = "sample"
            bubbleTextLayer.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
            bubbleTextLayer.fontSize = 22
            bubbleTextLayer.alignmentMode = .center
            bubbleTextLayer.foregroundColor = UIColor.black.cgColor
            bubbleTextLayer.contentsScale = UIScreen.main.scale
            bubbleTextLayer.frame = bubbleRect.insetBy(dx: 12, dy: 12)
            overlayLayer.addSublayer(bubbleTextLayer)

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
}

#Preview {
    ContentView()
}
