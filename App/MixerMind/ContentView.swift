import SwiftUI

struct ContentView: View {
    @State private var isConnected = SupabaseManager.shared.isConfigured

    var body: some View {
        if isConnected {
            HomeView(onDisconnect: {
                SupabaseManager.shared.disconnect()
                isConnected = false
            })
        } else {
            SetupView(onConnected: {
                isConnected = true
            })
        }
    }
}

#Preview {
    ContentView()
}
