import Foundation

/// Authorization status for notifications.
/// Spec ref: NOTIF-02
public enum NotificationAuthStatus: Sendable {
    case notDetermined
    case authorized
    case denied
    case provisional
}
