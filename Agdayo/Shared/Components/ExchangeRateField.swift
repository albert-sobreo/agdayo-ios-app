import SwiftUI

/// Shown inside a Cost section when the entered currency differs from the
/// trip's own. Fetches a live rate once via `CurrencyConversionService` and
/// snapshots it into `rate`, but always leaves it editable so a manual entry
/// still works offline or can override a bad fetch. Renders nothing when the
/// two currencies already match.
struct ExchangeRateField: View {
    let amount: Double
    let fromCurrency: String
    let toCurrency: String
    @Binding var rate: Double?

    @State private var isFetching = false

    var body: some View {
        Group {
            if fromCurrency != toCurrency {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Rate to \(toCurrency)")
                        Spacer()
                        if isFetching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            TextField("Rate", value: $rate, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                    if let rate, amount > 0 {
                        Text("≈ \((amount * rate).formattedCurrency(code: toCurrency))")
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: fromCurrency) {
            guard fromCurrency != toCurrency, rate == nil else { return }
            isFetching = true
            rate = await CurrencyConversionService.fetchRate(from: fromCurrency, to: toCurrency)
            isFetching = false
        }
    }
}
