import Foundation
import Auth
import Supabase

final class SupabaseManager: Observable {
    static let shared = SupabaseManager()

    private(set) var client: SupabaseClient?

    var isConfigured: Bool { client != nil }

    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: Constants.appGroupId) ?? .standard
    }

    private init() {
        migrateToSharedDefaults()
        loadFromDefaults()
    }

    func configure(url: String, key: String) {
        sharedDefaults.set(url, forKey: Constants.supabaseURLKey)
        sharedDefaults.set(key, forKey: Constants.supabaseKeyKey)
        client = SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: key,
            options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    func disconnect() {
        sharedDefaults.removeObject(forKey: Constants.supabaseURLKey)
        sharedDefaults.removeObject(forKey: Constants.supabaseKeyKey)
        client = nil
    }

    private func loadFromDefaults() {
        guard let url = sharedDefaults.string(forKey: Constants.supabaseURLKey),
              let key = sharedDefaults.string(forKey: Constants.supabaseKeyKey),
              let _ = URL(string: url) else {
            return
        }
        client = SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: key,
            options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    /// One-time migration: copy config from standard defaults to shared suite
    private func migrateToSharedDefaults() {
        let migrationKey = "app.remindr.migrated_to_shared_defaults"
        guard !sharedDefaults.bool(forKey: migrationKey) else { return }

        let standard = UserDefaults.standard
        if let url = standard.string(forKey: Constants.supabaseURLKey),
           let key = standard.string(forKey: Constants.supabaseKeyKey) {
            sharedDefaults.set(url, forKey: Constants.supabaseURLKey)
            sharedDefaults.set(key, forKey: Constants.supabaseKeyKey)
        }
        sharedDefaults.set(true, forKey: migrationKey)
    }
}
