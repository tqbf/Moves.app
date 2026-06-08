import Foundation
import Observation

@Observable
@MainActor
final class MovesStore {
    private(set) var moves: [Move] = []
    private(set) var loadError: String?

    private let db: Database?

    init() {
        do {
            self.db = try Database(path: Database.defaultURL().path(percentEncoded: false))
        } catch {
            self.db = nil
            self.loadError = "Database failed to open: \(error)"
        }
    }

    func load() async {
        guard let db else { return }
        do {
            moves = try await db.all()
            if moves.isEmpty {
                seedWelcomeRow()
            }
        } catch {
            loadError = "Load failed: \(error)"
        }
    }

    func add(title: String) {
        let move = Move(title: title)
        moves.insert(move, at: 0)
        persist(move)
    }

    func toggle(_ move: Move) {
        guard let idx = moves.firstIndex(of: move) else { return }
        moves[idx].done.toggle()
        persist(moves[idx])
    }

    func rename(_ move: Move, to title: String) {
        guard let idx = moves.firstIndex(of: move) else { return }
        moves[idx].title = title
        persist(moves[idx])
    }

    func delete(_ move: Move) {
        moves.removeAll { $0.id == move.id }
        guard let db else { return }
        Task { try? await db.delete(id: move.id) }
    }

    func move(id: Move.ID) -> Move? {
        moves.first { $0.id == id }
    }

    var pendingCount: Int { moves.lazy.filter { !$0.done }.count }

    private func persist(_ move: Move) {
        guard let db else { return }
        Task { try? await db.upsert(move) }
    }

    private func seedWelcomeRow() {
        add(title: "Welcome to Moves")
    }
}
