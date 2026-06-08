import Foundation
import Observation

/// Main-actor-bound view-model root for the app. Owns the database actor and
/// the repositories, and surfaces the slice of state the (currently
/// throwaway) phase-1 views need: a list of threads. Phases 3–5 will
/// replace this surface with the real popover/main-window state.
@Observable
@MainActor
final class AppStore {
  private(set) var threads: [Thread] = []
  private(set) var loadError: String?

  let database: Database?
  let threadRepository: ThreadRepository?
  let segmentRepository: SegmentRepository?
  let itemRepository: ItemRepository?
  let alertRepository: AlertRepository?
  let currentStateRepository: CurrentStateRepository?
  let timeLogRepository: TimeLogRepository?
  let settingsRepository: SettingsRepository?

  init() {
    do {
      let db = try Database(path: Database.defaultURL().path(percentEncoded: false))
      self.database = db
      self.threadRepository = ThreadRepository(database: db)
      self.segmentRepository = SegmentRepository(database: db)
      self.itemRepository = ItemRepository(database: db)
      self.alertRepository = AlertRepository(database: db)
      self.currentStateRepository = CurrentStateRepository(database: db)
      self.timeLogRepository = TimeLogRepository(database: db)
      self.settingsRepository = SettingsRepository(database: db)
    } catch {
      self.database = nil
      self.threadRepository = nil
      self.segmentRepository = nil
      self.itemRepository = nil
      self.alertRepository = nil
      self.currentStateRepository = nil
      self.timeLogRepository = nil
      self.settingsRepository = nil
      self.loadError = "Database failed to open: \(error)"
    }
  }

  // MARK: - Lifecycle

  func load() async {
    guard let threadRepository else { return }
    do {
      threads = try await threadRepository.all()
    } catch {
      loadError = "Load failed: \(error)"
    }
  }

  // MARK: - Thread editing (throwaway phase-1 plumbing)

  func addThread(title: String) {
    guard let threadRepository else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let thread = Thread(title: trimmed)
    threads.insert(thread, at: 0)
    Task { [threadRepository] in
      do { try await threadRepository.insert(thread) }
      catch { self.report("Insert failed: \(error)") }
    }
  }

  func rename(_ thread: Thread, to title: String) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != thread.title else { return }
    threads[idx].title = trimmed
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
  }

  func updateBreadcrumb(_ thread: Thread, to breadcrumb: String) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    threads[idx].breadcrumb = breadcrumb
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
  }

  func setStatus(_ thread: Thread, to status: ThreadStatus) {
    guard let idx = threads.firstIndex(of: thread) else { return }
    threads[idx].status = status
    threads[idx].updatedAt = Int64(Date().timeIntervalSince1970)
    persist(threads[idx])
  }

  func delete(_ thread: Thread) {
    threads.removeAll { $0.id == thread.id }
    guard let threadRepository else { return }
    Task { [threadRepository, id = thread.id] in
      do { try await threadRepository.delete(id: id) }
      catch { self.report("Delete failed: \(error)") }
    }
  }

  func thread(id: String) -> Thread? {
    threads.first { $0.id == id }
  }

  var activeCount: Int { threads.lazy.filter { $0.status == .active }.count }

  // MARK: - Internal

  private func persist(_ thread: Thread) {
    guard let threadRepository else { return }
    Task { [threadRepository] in
      do { try await threadRepository.update(thread) }
      catch { self.report("Update failed: \(error)") }
    }
  }

  private func report(_ message: String) {
    loadError = message
  }
}
