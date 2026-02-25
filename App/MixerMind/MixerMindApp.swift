//
//  MixerMindApp.swift
//  MixerMind
//
//  Created by Test on 27.01.26.
//

import SwiftUI
import SwiftData

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
}

@main
struct MixerMindApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    let modelContainer: ModelContainer

    init() {
        // Bootstrap audio coordinator so session + remote commands are ready before any view
        let _: AudioPlaybackCoordinator = resolve()

        do {
            let schema = Schema([LocalMix.self, LocalTag.self, LocalMixTag.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema mismatch — delete the old store and recreate
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)
            do {
                let schema = Schema([LocalMix.self, LocalTag.self, LocalMixTag.self])
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .modelContainer(modelContainer)
                .task {
                    let service: MixCreationService = resolve()
                    let context = modelContainer.mainContext
                    service.resumeIncomplete(modelContext: context)
                }
        }
    }
}
