import SwiftUI
import UIKit

/// A system alert whose buttons use the normal text color instead of the app's
/// tint. SwiftUI's `.alert` always takes the app's accent color for its buttons
/// and there's no per-alert override, so this builds the same system alert
/// directly where that color matters.
enum PlainAlert {
    struct Action {
        let title: String
        var isCancel = false
        let handler: () -> Void

        init(_ title: String, isCancel: Bool = false, handler: @escaping () -> Void = {}) {
            self.title = title
            self.isCancel = isCancel
            self.handler = handler
        }
    }

    @MainActor
    static func present(title: String, message: String, actions: [Action]) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return }
        // Show it above whatever is already on screen (a sheet, for example).
        while let presented = top.presentedViewController { top = presented }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.view.tintColor = .label
        for action in actions {
            alert.addAction(UIAlertAction(title: action.title, style: action.isCancel ? .cancel : .default) { _ in
                action.handler()
            })
        }
        top.present(alert, animated: true)
    }
}
