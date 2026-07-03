import Foundation

/// Coarse severity for product analytics and bug-alert classification.
enum MacAnalyticsSeverity: String, Sendable {
    case info
    case warning
    case error
    case critical
}
