import Foundation

final class LLMRefiner {
    private let ollamaURL: String
    private let model: String

    init(ollamaURL: String = "http://localhost:11434", model: String = "qwen3:1.7b") {
        self.ollamaURL = ollamaURL
        self.model = model
    }

    /// Check if Ollama is available
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(ollamaURL)/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Refine transcription: remove filler words, fix grammar, keep meaning
    func refine(_ text: String) async -> String {
        guard !text.isEmpty else { return text }

        let prompt = """
        Clean up this voice transcription. Remove filler words (呃、嗯、那个、就是、然后、like、um、uh、you know), \
        fix punctuation, but keep the original meaning and language exactly. Do NOT translate. \
        Output ONLY the cleaned text, nothing else.

        Input: \(text)
        """

        guard let url = URL(string: "\(ollamaURL)/api/generate") else { return text }

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.1, "num_predict": 512]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return text }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let refined = (json?["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // If LLM returned something reasonable, use it; otherwise keep original
            return refined.isEmpty || refined.count > text.count * 3 ? text : refined
        } catch {
            return text
        }
    }
}
