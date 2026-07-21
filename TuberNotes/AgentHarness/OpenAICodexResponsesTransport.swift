import Foundation

/// Redacted protocol-shape diagnostics for the opt-in citation demo. The log
/// never records prompts, images, retrieved excerpts, response prose, headers,
/// credentials, or raw provider bodies.
actor AgentRuntimeDiagnostics {
    static let shared = AgentRuntimeDiagnostics()

    private let processRunID = UUID().uuidString
#if TEXTBOOK_CITATION_DEMO
    private let logURL: URL? = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("agent-runtime-diagnostics.jsonl")
#else
    private let logURL: URL? = nil
#endif

    func record(_ event: String, fields: [String: String] = [:]) {
        guard let logURL else { return }
        if let size = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 512 * 1_024 {
            try? FileManager.default.removeItem(at: logURL)
        }

        var object = fields.mapValues(Self.redactedShapeValue)
        object["timestamp"] = ISO8601DateFormatter().string(from: Date())
        object["run_id"] = processRunID
        object["event"] = Self.redactedShapeValue(event)
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8)?.data(using: .utf8) else { return }
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            return
        }
    }

    private static func redactedShapeValue(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || "._,:;=+-/".unicodeScalars.contains($0)
        }
        return String(String.UnicodeScalarView(allowed).prefix(240))
    }
}

/// Redacted failures from the temporary direct-Codex bridge. Provider response
/// bodies and request metadata never leave AgentHarness.
enum OpenAICodexTransportError: Error {
    case unauthorized(generation: UUID)
    case unsupported
    case unavailable
    case invalidResponse
}

/// The only sender for normal-app requests authenticated by the temporary
/// OpenAI session. Capability clients own prompts and parsers; this type owns
/// the endpoint, authorization headers, response bounds, and status policy.
struct OpenAICodexResponsesTransport: Sendable {
    private let session: URLSession

    init(
        session: URLSession = OpenAICodexNetworking.ephemeralSession(
            requestTimeout: 90,
            resourceTimeout: 180
        )
    ) {
        self.session = session
    }

    func send(
        body: Data,
        route: AgentResponseRoute,
        capability: AgentCapability,
        maximumRequestBytes: Int = 12 * 1_024 * 1_024,
        maximumResponseBytes: Int
    ) async throws -> Data {
        guard !body.isEmpty,
              body.count <= maximumRequestBytes else {
            throw OpenAICodexTransportError.invalidResponse
        }
        guard Date.now < route.expiresAt else {
            throw OpenAICodexTransportError.unauthorized(generation: route.generation)
        }
        _ = capability

        do {
            var request = URLRequest(url: OpenAICodexConstants.codexAPIEndpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
            route.prepare(&request)
            request.httpBody = body

            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else {
                await AgentRuntimeDiagnostics.shared.record("transport_rejected", fields: [
                    "gate": "non_http_response"
                ])
                throw OpenAICodexTransportError.unavailable
            }
            await AgentRuntimeDiagnostics.shared.record("transport_http_response", fields: [
                "status": String(http.statusCode),
                "status_class": "\(http.statusCode / 100)xx"
            ])
            switch http.statusCode {
            case 200..<300:
                break
            case 401, 403:
                throw OpenAICodexTransportError.unauthorized(generation: route.generation)
            case 400, 404, 405, 415, 422:
                throw OpenAICodexTransportError.unsupported
            default:
                throw OpenAICodexTransportError.unavailable
            }

            var data = Data()
            data.reserveCapacity(min(maximumResponseBytes, 256 * 1_024))
            for try await byte in bytes {
                guard data.count < maximumResponseBytes else {
                    await AgentRuntimeDiagnostics.shared.record("transport_rejected", fields: [
                        "gate": "response_size_limit",
                        "maximum_bytes": String(maximumResponseBytes)
                    ])
                    throw OpenAICodexTransportError.invalidResponse
                }
                data.append(byte)
            }
            guard !data.isEmpty else {
                await AgentRuntimeDiagnostics.shared.record("transport_rejected", fields: [
                    "gate": "empty_response"
                ])
                throw OpenAICodexTransportError.invalidResponse
            }
            await AgentRuntimeDiagnostics.shared.record("transport_body_completed", fields: [
                "byte_count": String(data.count)
            ])
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpenAICodexTransportError {
            throw error
        } catch {
            await AgentRuntimeDiagnostics.shared.record("transport_rejected", fields: [
                "gate": "network_or_stream_error"
            ])
            throw OpenAICodexTransportError.unavailable
        }
    }
}
