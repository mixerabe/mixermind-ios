import Foundation

enum OpenGraphService {
    static func fetch(_ urlString: String) async throws -> OGMetadata {
        guard let endpoint = URL(string: "\(Constants.backendURL)/api/og") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": urlString])
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        return OGMetadata(
            title: json["title"] as? String,
            description: json["description"] as? String,
            imageUrl: json["image_url"] as? String,
            host: json["host"] as? String ?? urlString
        )
    }
}
