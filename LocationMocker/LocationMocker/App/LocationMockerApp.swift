import SwiftUI

@main
struct LocationMockerApp: App {
    @StateObject private var viewModel = MainViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear { ExpiryReminder.schedule() }
        }
    }
}
