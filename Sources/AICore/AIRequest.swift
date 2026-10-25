import Foundation

public struct AIRequest: Sendable {
    public let profile: AIProfile
    public let key: String
    public let system: String
    public let messages: [AIMessage]
    public init(profile: AIProfile, key: String, system: String, messages: [AIMessage]) {
        self.profile = profile; self.key = key; self.system = system; self.messages = messages
    }
    public func urlRequest() throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.missingKey }
        guard messages.first?.role == .user, messages.last?.role == .user else { throw AIError.configuration }
        try AIInputBudget.validate(messages)
        guard profile.supportsImages || messages.allSatisfy({ $0.image == nil }) else { throw AIError.imageUnsupported }
        var request = URLRequest(url: try profile.endpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any]
        switch profile.api {
        case .chatCompletions, .responses:
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            let responses = profile.api == .responses
            var input: [[String: Any]] = messages.map { message in
                guard let image = message.image else { return ["role": message.role.rawValue, "content": message.text] }
                let url = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
                let content: [[String: Any]] = responses
                    ? [["type": "input_text", "text": message.text], ["type": "input_image", "image_url": url]]
                    : [["type": "text", "text": message.text], ["type": "image_url", "image_url": ["url": url]]]
                return ["role": message.role.rawValue, "content": content]
            }
            if responses { body = ["model": profile.modelID, "instructions": system, "input": input, "stream": true, "store": false] }
            else {
                input.insert(["role": "system", "content": system], at: 0)
                body = ["model": profile.modelID, "messages": input, "stream": true]
            }
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let input: [[String: Any]] = messages.map { message in
                var content: [[String: Any]] = [["type": "text", "text": message.text]]
                if let image = message.image { content.append(["type": "image", "source": ["type": "base64", "media_type": image.mimeType, "data": image.data.base64EncodedString()]]) }
                return ["role": message.role.rawValue, "content": content]
            }
            body = ["model": profile.modelID, "system": system, "messages": input, "max_tokens": 8192, "stream": true]
        case .gemini:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let input: [[String: Any]] = messages.map { message in
                var parts: [[String: Any]] = [["text": message.text]]
                if let image = message.image { parts.append(["inlineData": ["mimeType": image.mimeType, "data": image.data.base64EncodedString()]]) }
                return ["role": message.role == .assistant ? "model" : "user", "parts": parts]
            }
            body = ["systemInstruction": ["parts": [["text": system]]], "contents": input]
        }
        if let limit=profile.maxOutputTokens {
            guard (1...1_000_000).contains(limit) else { throw AIError.configuration }
            switch profile.api {
            case .chatCompletions: body[profile.reasoning?.mode == .deepSeek ? "max_tokens" : "max_completion_tokens"]=limit
            case .responses: body["max_output_tokens"]=limit
            case .anthropic: body["max_tokens"]=limit
            case .gemini: body["generationConfig"]=["maxOutputTokens":limit]
            }
        }
        try profile.reasoning?.apply(to:&body,api:profile.api)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
