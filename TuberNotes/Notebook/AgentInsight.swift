import Foundation
import UIKit

/// Result of asking the agent to look at a page selection.
struct AgentInsight: Equatable {
    let summary: String
    let items: [String]
}

/// Boundary for "look at what I circled and tell me what you see". Complements the
/// existing `AgentClient`/`SpatialSelection` boundary (which returns `[Pin]`); this
/// one returns human-readable text for the toggleable assistant sidebar.
protocol AgentInsightClient {
    func analyze(_ selection: SpatialSelection, question: String?) async throws -> AgentInsight
}

/// Which gateway to route analysis through. Each case owns its endpoint, wire
/// format, and default model; the app just stores the raw value.
enum AgentProvider: String, CaseIterable, Identifiable {
    /// OpenAI-compatible Chat Completions (OpenAI, OpenRouter, Groq, …).
    case openAI
    /// right.codes Codex proxy — OpenAI *Responses* API, not chat/completions.
    case rightCode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI:    "OpenAI-compatible"
        case .rightCode: "right.codes (Codex)"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:    "gpt-4o-mini"
        case .rightCode: "gpt-5.5"
        }
    }

    /// Suggested models for the picker. Not exhaustive — the field stays editable
    /// so new gateway models can be typed in without a code change.
    var knownModels: [String] {
        switch self {
        case .openAI:
            ["gpt-4o-mini", "gpt-4o", "gpt-4.1", "gpt-4.1-mini"]
        case .rightCode:
            ["gpt-5.5", "gpt-5.5-openai-compact", "gpt-5.6-luna",
             "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.4", "gpt-5.4-mini",
             "codex-auto-review"]
        }
    }
}

/// Shared default instruction used when the user doesn't type their own question.
private func defaultInsightPrompt(_ question: String?) -> String {
    question ?? """
    This is a page from a handwritten notebook. The user has drawn on it and may have \
    circled or marked something. Describe what you see, focusing on anything circled or \
    marked. Reply with a one-paragraph summary, then a short bullet list (using "- ") of \
    the distinct things you notice. Keep it concise.
    """
}

/// Turns a model's raw text reply into a summary + bullet list.
private func parseInsight(_ text: String) -> AgentInsight {
    let lines = text
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    var summary = ""
    var items: [String] = []
    for line in lines {
        if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ") {
            items.append(String(line.dropFirst(2)))
        } else if summary.isEmpty {
            summary = line
        }
    }
    if summary.isEmpty { summary = text }
    return AgentInsight(summary: summary, items: items)
}

enum AgentError: LocalizedError {
    case server(String)
    case parse
    case noKey

    var errorDescription: String? {
        switch self {
        case .server(let m): "Service error: \(m)"
        case .parse:         "Couldn't read the assistant's response."
        case .noKey:         "No API key set."
        }
    }
}

/// Runs with no network/key so the app is fully functional out of the box.
struct MockAgentInsightClient: AgentInsightClient {
    func analyze(_ selection: SpatialSelection, question: String?) async throws -> AgentInsight {
        try? await Task.sleep(nanoseconds: 700_000_000)
        return AgentInsight(
            summary: "Demo mode. Add an OpenAI API key in the assistant settings to get real descriptions. I can see you've drawn on the page and marked a region.",
            items: [
                "Handwritten strokes detected",
                "One circled / marked area",
                "Add a key to enable real analysis"
            ]
        )
    }
}

/// Sends the captured page image to OpenAI's vision-capable chat endpoint.
///
/// Security note: putting an API key directly in the app is fine for local dev,
/// but for anything shipped you should proxy requests through your own backend
/// so the key never lives on device.
struct OpenAIVisionClient: AgentInsightClient {
    let apiKey: String
    var baseURL: URL = URL(string: "https://api.openai.com/v1/chat/completions")!
    var model: String = "gpt-4o-mini"

    func analyze(_ selection: SpatialSelection, question: String?) async throws -> AgentInsight {
        let dataURL = "data:image/jpeg;base64,\(selection.imageData.base64EncodedString())"
        let prompt = defaultInsightPrompt(question)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 500,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": dataURL]]
                ]
            ]]
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AgentError.server(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw AgentError.parse }

        return parseInsight(content)
    }
}

/// Sends the page image to the right.codes Codex proxy, which speaks OpenAI's
/// **Responses** API (`wire_api = "responses"`) rather than chat/completions.
/// Request uses `input`/`input_image`; the reply is parsed out of `output[]`.
struct RightCodeResponsesClient: AgentInsightClient {
    let apiKey: String
    var baseURL: URL = URL(string: "https://right.codes/codex/v1/responses")!
    var model: String = "gpt-5.5"

    func analyze(_ selection: SpatialSelection, question: String?) async throws -> AgentInsight {
        let dataURL = "data:image/jpeg;base64,\(selection.imageData.base64EncodedString())"
        let prompt = defaultInsightPrompt(question)

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "input": [[
                "role": "user",
                "content": [
                    ["type": "input_text", "text": prompt],
                    ["type": "input_image", "image_url": dataURL]
                ]
            ]]
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AgentError.server(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        // The proxy streams Server-Sent Events (like the Codex CLI), so the body
        // is an event stream, not a single JSON object. Try SSE first, then fall
        // back to a plain JSON body in case a non-streaming path is ever used.
        guard let content = Self.extractSSEText(from: data) ?? Self.extractText(from: data) else {
            let raw = String(data: data, encoding: .utf8) ?? "<non-text response>"
            throw AgentError.server("Unexpected response shape:\n\(raw.prefix(600))")
        }
        return parseInsight(content)
    }

    /// Reassembles the assistant text from a Responses-API SSE stream by
    /// concatenating `response.output_text.delta` events, with fallbacks to the
    /// terminal `.done`/`.completed` events.
    static func extractSSEText(from data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("data:") else { return nil }

        var deltas = ""
        var doneText: String?
        var completedText: String?

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]",
                  let d = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }

            switch type {
            case "response.output_text.delta":
                if let delta = obj["delta"] as? String { deltas += delta }
            case "response.output_text.done":
                if let t = obj["text"] as? String { doneText = t }
            case "response.completed", "response.incomplete":
                if let resp = obj["response"] as? [String: Any],
                   let respData = try? JSONSerialization.data(withJSONObject: resp) {
                    completedText = extractText(from: respData)
                }
            default:
                break
            }
        }

        for candidate in [doneText, deltas.isEmpty ? nil : deltas, completedText] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }

    /// Pulls the assistant text out of a Responses-API payload. The `output`
    /// array can contain reasoning items before the message, so we scan for the
    /// `output_text` part(s) and concatenate them.
    static func extractText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // 1. SDK-style convenience field.
        if let text = json["output_text"] as? String, !text.isEmpty { return text }

        // 2. Canonical Responses API: output[].content[] of type "output_text".
        if let output = json["output"] as? [[String: Any]] {
            var pieces: [String] = []
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                for part in content where (part["type"] as? String) == "output_text" {
                    if let text = part["text"] as? String { pieces.append(text) }
                }
            }
            let joined = pieces.joined(separator: "\n")
            if !joined.isEmpty { return joined }
        }

        // 3. Chat-completions shape, in case the proxy normalizes to it.
        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        return nil
    }
}

enum AgentClientFactory {
    /// Returns the real client for the chosen provider when a key is present,
    /// otherwise the offline demo client.
    static func make(
        apiKey: String,
        provider: AgentProvider = .openAI,
        model: String? = nil
    ) -> AgentInsightClient {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return MockAgentInsightClient() }

        let chosenModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = (chosenModel?.isEmpty == false ? chosenModel! : provider.defaultModel)

        switch provider {
        case .openAI:
            return OpenAIVisionClient(apiKey: key, model: resolvedModel)
        case .rightCode:
            return RightCodeResponsesClient(apiKey: key, model: resolvedModel)
        }
    }
}
