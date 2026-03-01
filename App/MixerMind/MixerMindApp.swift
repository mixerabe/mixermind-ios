//
//  MixerMindApp.swift
//  MixerMind
//
//  Created by Test on 27.01.26.
//

import SwiftUI
import CoreData

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
}

@main
struct MixerMindApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    let coreDataStack = CoreDataStack.shared

    init() {
        // Bootstrap audio coordinator so session + remote commands are ready before any view
        let _: AudioPlaybackCoordinator = resolve()
        coreDataStack.seedDefaultTagsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(\.managedObjectContext, coreDataStack.viewContext)
        }
    }
}
