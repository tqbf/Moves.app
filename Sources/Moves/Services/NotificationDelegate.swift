import Foundation
import UserNotifications

/// `UNUserNotificationCenterDelegate` that routes snooze actions back into
/// `AppStore` and records `Alert.fired_at` on delivery.
///
/// Lives for the lifetime of the app. Installed in `MovesApp.init` via
/// `UNUserNotificationCenter.current().delegate = …`. Holds a weak ref to
/// the store so we don't create a retain cycle through the singleton
/// notification center.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  private weak var store: AppStore?

  init(store: AppStore) {
    self.store = store
    super.init()
  }

  // MARK: - Foreground presentation

  /// Show notifications even while Moves is foregrounded. The menu-bar
  /// popover is often the *only* visible Moves surface; without this the
  /// user wouldn't see anything fire from inside it.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  // MARK: - Response handling

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping @Sendable () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let actionId = response.actionIdentifier
    let title = response.notification.request.content.title

    let itemId = userInfo[ReminderScheduler.UserInfoKey.itemId] as? String
    let alertId = userInfo[ReminderScheduler.UserInfoKey.alertId] as? String

    Task { @MainActor [weak self] in
      defer { completionHandler() }
      guard let self, let store = self.store, let itemId, let alertId else { return }
      await store.handleNotificationResponse(
        actionId: actionId,
        itemId: itemId,
        alertId: alertId,
        title: title
      )
    }
  }
}
