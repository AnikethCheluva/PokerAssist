//import UIKit
//import Vision
//import CoreML
//
//final class CardDetector {
//    var onCardsDetected: (([Card]) -> Void)?
//    private let visionQueue = DispatchQueue(label: "vision.card.detector.queue", qos: .userInteractive)
//    private var isBusy = false
//    private let confidenceThreshold: Float = 0.85
//
//    private lazy var yoloModel: VNCoreMLModel? = {
//        print("🔍 [DEBUG] Initializing YOLO model...")
//        let config = MLModelConfiguration()
//        config.computeUnits = .cpuAndGPU // Ensure this is using the Neural Engine if possible
//        
//        do {
//            let modelInstance = try yolo11(configuration: config)
//            let model = try VNCoreMLModel(for: modelInstance.model)
//            print("✅ [DEBUG] Model loaded successfully.")
//            return model
//        } catch {
//            print("❌ [DEBUG] Failed to load model: \(error.localizedDescription)")
//            return nil
//        }
//    }()
//
//    func process(frame image: UIImage) {
//        guard !isBusy else {
//            // Un-comment if you want to see how many frames you are dropping
//            // print("⚠️ [DEBUG] System busy, skipping frame.")
//            return
//        }
//        
//        guard let cgImage = image.cgImage, let model = yoloModel else {
//            print("❌ [DEBUG] Missing image data or model.")
//            return
//        }
//        
//        isBusy = true
//        let startTime = CFAbsoluteTimeGetCurrent() // Start performance timer
//
//        visionQueue.async { [weak self] in
//            let request = VNCoreMLRequest(model: model) { request, error in
//                let executionTime = CFAbsoluteTimeGetCurrent() - startTime
//                print(String(format: "⏱️ [DEBUG] Inference time: %.3f ms", executionTime * 1000))
//                self?.handleDetection(request: request, error: error)
//            }
//            let handler = VNImageRequestHandler(cgImage: cgImage)
//            
//            do {
//                try handler.perform([request])
//            } catch {
//                print("❌ [DEBUG] Request perform error: \(error.localizedDescription)")
//                self?.isBusy = false
//            }
//        }
//    }
//
//    private func handleDetection(request: VNRequest, error: Error?) {
//        defer { isBusy = false }
//        
//        if let error = error {
//            print("❌ [DEBUG] Detection error: \(error.localizedDescription)")
//            return
//        }
//
//        guard let results = request.results as? [VNRecognizedObjectObservation] else {
//            print("ℹ️ [DEBUG] No objects recognized in frame.")
//            return
//        }
//
//        print("📊 [DEBUG] Total Raw Detections: \(results.count)")
//
//        let detectedCards = results.compactMap { observation -> Card? in
//            guard let topLabel = observation.labels.first else { return nil }
//            
//            // Log every detection below the threshold to see if your threshold is too high
//            if topLabel.confidence < self.confidenceThreshold {
//                print("⬇️ [DEBUG] Filtered: \(topLabel.identifier) (Conf: \(String(format: "%.2f", topLabel.confidence)))")
//                return nil
//            }
//
//            guard let (rank, suit) = self.parseLabel(topLabel.identifier) else {
//                print("❓ [DEBUG] Parse fail for label: \(topLabel.identifier)")
//                return nil
//            }
//            
//            let location: CardLocation = (observation.boundingBox.midY < 0.35) ? .hand : .board
//            print("🃏 [DEBUG] Confirmed: \(rank)\(suit) at \(location) (Conf: \(String(format: "%.2f", topLabel.confidence)))")
//            
//            return Card(rank: rank, suit: suit, location: location, observation: observation)
//        }
//        
//        if !detectedCards.isEmpty {
//            DispatchQueue.main.async {
//                self.onCardsDetected?(detectedCards)
//            }
//        }
//    }
//
//    private func parseLabel(_ label: String) -> (String, Suit)? {
//        let suitChar = String(label.last ?? " "), rankPart = String(label.dropLast())
//        let suit: Suit
//        switch suitChar.uppercased() {
//            case "H": suit = .hearts; case "D": suit = .diamonds; case "C": suit = .clubs; case "S": suit = .spades; default: return nil
//        }
//        return (rankPart, suit)
//    }
//}
