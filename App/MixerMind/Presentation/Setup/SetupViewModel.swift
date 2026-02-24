import Foundation

@Observable @MainActor
final class SetupViewModel {
    // MARK: - Mode Toggle

    var isManualMode = false

    // MARK: - Auto Setup

    var accessToken = ""
    var isSettingUp = false
    var setupProgress = ""
    var showAlreadyExistsAlert = false
    var existingProjectName = ""

    // MARK: - Manual Connect

    var supabaseURL = ""
    var supabaseKey = ""
    var isConnecting = false

    // MARK: - Shared

    var errorMessage: String?

    // MARK: - Auto Setup

    func setupProject() async -> SetupResult {
        let trimmed = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter your access token"
            return .failed
        }

        isSettingUp = true
        errorMessage = nil
        setupProgress = "Connecting to Supabase..."

        do {
            // Step 1: Create project (or detect existing)
            let createResult = try await callSetupFunction(body: ["access_token": trimmed])

            switch createResult.status {
            case "already_exists":
                existingProjectName = createResult.projectName ?? "remindr"
                showAlreadyExistsAlert = true
                isSettingUp = false
                return .alreadyExists

            case "creating":
                guard let ref = createResult.projectRef else {
                    throw SetupError.serverError("No project ref returned")
                }
                // Step 2: Poll until ready, then set up
                return try await pollUntilReady(token: trimmed, projectRef: ref)

            case "created":
                // Edge function finished setup in one call (unlikely but handle it)
                return try await finishSetup(createResult)

            case "error":
                throw SetupError.serverError(createResult.message ?? "Unknown error")

            default:
                throw SetupError.serverError("Unexpected response: \(createResult.status)")
            }
        } catch let error as SetupError {
            errorMessage = error.localizedDescription
            isSettingUp = false
            return .failed
        } catch {
            errorMessage = error.localizedDescription
            isSettingUp = false
            return .failed
        }
    }

    private func pollUntilReady(token: String, projectRef: String) async throws -> SetupResult {
        setupProgress = "Creating your project (this may take a few minutes)..."

        let maxAttempts = 60
        for i in 0..<maxAttempts {
            try await Task.sleep(for: .seconds(5))

            let pollResult = try await callSetupFunction(body: [
                "access_token": token,
                "action": "poll",
                "project_ref": projectRef,
            ])

            switch pollResult.status {
            case "creating":
                // Still waiting
                if i > 6 {
                    setupProgress = "Still setting up... hang tight"
                }
                continue

            case "created":
                return try await finishSetup(pollResult)

            case "error":
                throw SetupError.serverError(pollResult.message ?? "Setup failed")

            default:
                throw SetupError.serverError("Unexpected status: \(pollResult.status)")
            }
        }

        throw SetupError.serverError("Project creation timed out. Check your Supabase dashboard.")
    }

    private func finishSetup(_ result: SetupResponse) async throws -> SetupResult {
        guard let projectUrl = result.projectUrl, let anonKey = result.anonKey else {
            throw SetupError.missingCredentials
        }
        setupProgress = "Configuring app..."
        SupabaseManager.shared.configure(url: projectUrl, key: anonKey)

        setupProgress = "Adding starter mixes..."
        try await SeedManager.seedMixes()

        isSettingUp = false
        return .created
    }

    private func callSetupFunction(body: [String: String]) async throws -> SetupResponse {
        var request = URLRequest(url: URL(string: "\(Constants.backendURL)/api/setup-project")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(SetupResponse.self, from: data)
    }

    // MARK: - Manual Connect

    func manualConnect() async -> Bool {
        guard URL(string: supabaseURL) != nil else {
            errorMessage = "Invalid URL"
            return false
        }

        isConnecting = true
        errorMessage = nil

        SupabaseManager.shared.configure(url: supabaseURL, key: supabaseKey)

        do {
            let repo = MixRepository()
            _ = try await repo.listMixes()
            isConnecting = false
            return true
        } catch {
            SupabaseManager.shared.disconnect()
            isConnecting = false
            errorMessage = "Connection failed. Check your URL, key, and that the mixes table exists."
            return false
        }
    }
}

// MARK: - Supporting Types

enum SetupResult {
    case created
    case alreadyExists
    case failed
}

enum SetupError: LocalizedError {
    case missingCredentials
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Server did not return project credentials"
        case .serverError(let message):
            return message
        }
    }
}

struct SetupResponse: Decodable {
    let status: String
    let projectUrl: String?
    let anonKey: String?
    let projectName: String?
    let projectRef: String?
    let message: String?
}
