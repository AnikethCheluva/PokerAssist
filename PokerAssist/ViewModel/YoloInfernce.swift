import UIKit
import Foundation

enum InferenceError: Error {
    case invalidImage, invalidURL, invalidResponse, decodingError, busy
    case serverError(statusCode: Int)
}

// MARK: - API Models

struct BBox: Codable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
}

struct RemoteDetection: Codable {
    let label: String
    let confidence: Double
    let bbox: BBox
    let bbox_pixels: BBox?
}

struct InferenceResponse: Codable {
    let success: Bool
    let detections: [RemoteDetection]
    let count: Int
    // Notice the '?' below. This allows the app to stay alive
    // even if the server forgets to send the timing data.
    let inference_time_ms: Double?
}

// MARK: - Updated Client

actor YOLOInferenceClient {
    private let baseURL: String
    private let session: URLSession
    private var isProcessing = false
    private var priorityRequestInFlight = false // New: Priority Flag

    init(baseURL: String = "http://192.168.1.38:8000") {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5.0
        configuration.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: configuration)
    }

    func infer(image: UIImage, isPriority: Bool = false) async throws -> InferenceResponse {
        // 1. Precedence Logic:
        // If this is a normal frame and a priority request is waiting or running, drop it.
        if !isPriority && (isProcessing || priorityRequestInFlight) {
            throw InferenceError.busy
        }
        
        // 2. Wait logic for Priority:
        // If priority is pressed while a live frame is currently mid-flight,
        // we wait for that single frame to finish, then take the very next slot.
        if isPriority {
            priorityRequestInFlight = true
            while isProcessing {
                try await Task.sleep(nanoseconds: 10_000_000) // Wait 10ms increments
            }
        }

        isProcessing = true
        defer {
            isProcessing = false
            if isPriority { priorityRequestInFlight = false }
        }

        // --- Standard Request Logic ---
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { throw InferenceError.invalidImage }
        guard let url = URL(string: "\(baseURL)/infer") else { throw InferenceError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"image\"; filename=\"frame.jpg\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw InferenceError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        return try JSONDecoder().decode(InferenceResponse.self, from: data)
    }
}

// --- FIX 2: Essential Data Extension ---
fileprivate extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}
