import Foundation

final class CursorState: ObservableObject {
    @Published var activeModifiers: Set<String> = []

    func toggleModifier(_ modifier: String) {
        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
        } else {
            activeModifiers.insert(modifier)
        }
    }

    func clearModifiers() {
        activeModifiers.removeAll()
    }

    var modifierArray: [String] {
        Array(activeModifiers)
    }
}
