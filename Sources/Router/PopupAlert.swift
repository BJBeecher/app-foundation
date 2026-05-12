import Foundation
import SwiftUI

public struct PopupAlert: Identifiable, RouterAlert {
    public let id: String
    public let title: String
    public let message: String?
    public let buttons: [AlertButton]
    public var tapped: (@Sendable (AlertButton) -> Void)?

    public init(
        id: String? = nil,
        title: String,
        message: String? = nil,
        buttons: [AlertButton]
    ) {
        self.id = id ?? title.lowercased()
        self.title = title
        self.message = message
        self.buttons = buttons
    }

    public mutating func setTappedHandler(_ handler: @escaping @Sendable (AlertButton) -> Void) {
        tapped = handler
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.message == rhs.message &&
        lhs.buttons == rhs.buttons
    }
}

public struct AlertButton: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let role: ButtonRole?

    public init(
        id: String? = nil,
        title: String,
        role: ButtonRole? = nil
    ) {
        self.id = id ?? title.lowercased()
        self.title = title
        self.role = role
    }

    public static let dismissed = AlertButton(id: "dismissed", title: "Dismissed", role: .cancel)
}

public protocol RouterAlert: Equatable, Sendable {
    mutating func setTappedHandler(_ handler: @escaping @Sendable (AlertButton) -> Void)
}
