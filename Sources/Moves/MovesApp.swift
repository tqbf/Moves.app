import SwiftUI

@main
struct MovesApp: App {
  @State private var store = AppStore()

  var body: some Scene {
    Window("Moves", id: "main") {
      MainView()
        .environment(store)
        .frame(minWidth: 720, minHeight: 440)
        .task { await store.load() }
    }
    .defaultSize(width: 920, height: 600)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Thread") { store.addThread(title: "New Thread") }
          .keyboardShortcut("n")
      }
    }

    MenuBarExtra {
      MenuBarContent()
        .environment(store)
    } label: {
      Image(systemName: "figure.walk.motion")
    }
    .menuBarExtraStyle(.window)
  }
}
