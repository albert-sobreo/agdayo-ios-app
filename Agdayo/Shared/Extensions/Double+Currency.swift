import Foundation

extension Double {
    func formattedCurrency(code: String) -> String {
        self.formatted(.currency(code: code))
    }
}

extension Optional where Wrapped == Double {
    func formattedCurrency(code: String) -> String? {
        self?.formattedCurrency(code: code)
    }
}

/// Common currency codes, matching the breadth of the web app's currency picker.
enum CurrencyCode {
    static let common = ["PHP", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "HKD", "KRW", "CNY", "THB"]
}
