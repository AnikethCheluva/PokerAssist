import MWDATCamera
import MWDATCore
import SwiftUI
import Vision
import Combine
import Foundation

// MARK: - Supporting Types
enum StreamingStatus {
    case streaming
    case waiting
    case stopped
}

@MainActor
class StreamManager: ObservableObject {
    @Published var currentVideoFrame: UIImage?
    @Published var streamingStatus: StreamingStatus = .stopped
    @Published var hasActiveDevice: Bool = false
    @Published var lastInferenceTime: Double = 0
    
    private let inferenceClient = YOLOInferenceClient(baseURL: "http://192.168.1.38:8000")
    var onCardsFound: (([RemoteDetection]) -> Void)?
    var onHandCaptureReady: (([RemoteDetection]) -> Void)?

    private var streamSession: StreamSession
    private var stateListenerToken: AnyListenerToken?
    private var videoFrameListenerToken: AnyListenerToken?
    
    private let wearables: WearablesInterface
    private let deviceSelector: AutoDeviceSelector
    private var deviceMonitorTask: Task<Void, Never>?
    
    // Performance Tracking
    private var frameCounter = 0
    private let inferenceSkipFactor = 2 // Run inference every 2nd frame (~10 FPS)

    var isStreaming: Bool {
        streamingStatus == .streaming
    }

    init(wearables: WearablesInterface) {
        print("🛠️ [MANAGER] Initializing StreamManager...")
        self.wearables = wearables
        self.deviceSelector = AutoDeviceSelector(wearables: wearables)
        
        // High resolution provides 720x1280
        let config = StreamSessionConfig(
            videoCodec: VideoCodec.raw,
            resolution: StreamingResolution.high,
            frameRate: 20
        )
        
        self.streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

        setupListeners()
    }

    private func setupListeners() {
        // 1. High-FPS Video Pipe
        videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            guard let self = self else { return }
            
            guard let image = videoFrame.makeUIImage(),
                  let cencrop = image.extractModelInput(targetSize: 720) else {
                return
            }

            Task { @MainActor in
                self.currentVideoFrame = cencrop
                self.frameCounter += 1
                
                // Trigger Remote Inference with Frame Skipping
                // Trigger Remote Inference with Frame Skipping
                if self.frameCounter % self.inferenceSkipFactor == 0 {
                    // Pass isPriority: false (default)
                    self.runRemoteInference(image: cencrop)
                }
            }
        }

        // 2. Session State Monitor
        stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
            print("📱 [SDK STATE] -> \(state)")
            Task { @MainActor in
                self?.updateStatusFromState(state)
            }
        }
        
        // 3. Hardware Availability Monitor
        deviceMonitorTask = Task { @MainActor in
            for await device in self.deviceSelector.activeDeviceStream() {
                let isConnected = device != nil
                print("👓 [HARDWARE] Connected: \(isConnected)")
                self.hasActiveDevice = isConnected
            }
        }
    }
    
    // MARK: - Remote Inference Logic
    
    private func runRemoteInference(image: UIImage) {
        Task {
            do {
                // Call our Actor-based Inference Client
                let response = try await inferenceClient.infer(image: image)
                
                if response.success {
                    await MainActor.run {
                        self.lastInferenceTime = response.inference_time_ms ?? 0.0
                        self.onCardsFound?(response.detections)
                    }
                }
            } catch InferenceError.busy {
                // Network/Server is still busy, skip this frame silently
            } catch {
                print("📡 [REMOTE ERROR] \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Public Interface
    
    func handleStartStreaming() async {
        print("🚀 [ACTION] Requesting Stream...")
        let permission = Permission.camera
        do {
            let status = try await wearables.checkPermissionStatus(permission)
            if status == .granted {
                await startSession()
            } else {
                let requestStatus = try await wearables.requestPermission(permission)
                if requestStatus == .granted { await startSession() }
            }
        } catch {
            print("❌ [AUTH ERROR] \(error.localizedDescription)")
        }
    }

    func startSession() async {
        guard let device = deviceSelector.activeDevice else {
            print("❌ [SESSION] No device found.")
            return
        }
        print("🟢 [SESSION] Starting: \(device)")
        await streamSession.start()
    }

    func stopSession() async {
        print("🛑 [SESSION] Stopping...")
        await streamSession.stop()
    }

    private func updateStatusFromState(_ state: StreamSessionState) {
        switch state {
        case .stopped: streamingStatus = .stopped
        case .streaming: streamingStatus = .streaming
        case .starting: streamingStatus = .waiting
        default: streamingStatus = .waiting
        }
    }
    
    deinit {
        deviceMonitorTask?.cancel()
    }
    
    
    func captureHand() {
        guard let snapshot = self.currentVideoFrame else { return }
        
        Task {
            do {
                print("🚀 [PRIORITY] Snap requested. Clearing the path...")
                // Pass isPriority: true to force the client to wait for a slot
                let response = try await inferenceClient.infer(image: snapshot, isPriority: true)
                
                await MainActor.run {
                    self.onHandCaptureReady?(response.detections)
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            } catch {
                print("❌ [HAND CAPTURE] Priority request failed: \(error)")
            }
        }
    }
    
}

// MARK: - Native Pixel Extensions

extension UIImage {
    /// Extracts a 1:1 center crop from the native sensor buffer without scaling artifacts.
    func extractModelInput(targetSize: CGFloat = 720) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        
        let srcWidth = CGFloat(cgImage.width)   // Expected 720
        let srcHeight = CGFloat(cgImage.height) // Expected 1280
        
        // Center-crop logic for 720x1280 -> 720x720
        let xOffset = (srcWidth - targetSize) / 2
        let yOffset = (srcHeight - targetSize) / 2
        let cropRect = CGRect(x: xOffset, y: yOffset, width: targetSize, height: targetSize)
        
        guard let croppedCg = cgImage.cropping(to: cropRect) else { return nil }
        
        // Return native pixels with scale 1.0 to prevent iOS auto-scaling
        return UIImage(cgImage: croppedCg, scale: 1.0, orientation: self.imageOrientation)
    }
}
