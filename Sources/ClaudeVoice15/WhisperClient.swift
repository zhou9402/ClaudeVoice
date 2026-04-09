import Foundation

final class WhisperClient {

    func transcribe(wavData: Data, engine: STTEngine = .qwen3, language: String? = nil) async throws -> String {
        let baseURL = Settings.shared.url(for: engine).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/v1/audio/transcriptions") else {
            throw NSError(domain: "WhisperClient", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid \(engine.displayName) URL"])
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = engine == .cohere ? 60 : 30

        // API key for engines that require it (e.g. mlx-qwen3-asr)
        let apiKey = Settings.shared.apiKey(for: engine)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        // model field (required by OpenAI-compatible API)
        appendFormField(&body, boundary: boundary, name: "model", value: engine.modelName)

        // language hint (optional)
        if let language {
            appendFormField(&body, boundary: boundary, name: "language", value: language)
        }

        // response_format
        appendFormField(&body, boundary: boundary, name: "response_format", value: "json")

        // audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "WhisperClient", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "\(engine.displayName) API error \(code): \(bodyStr)"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func appendFormField(_ body: inout Data, boundary: String, name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }
}
