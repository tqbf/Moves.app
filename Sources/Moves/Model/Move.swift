import Foundation

struct Move: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var done: Bool
    var created: Date

    init(id: UUID = UUID(), title: String, done: Bool = false, created: Date = .now) {
        self.id = id
        self.title = title
        self.done = done
        self.created = created
    }
}
