import SwiftUI

struct BudgetProgressBar: View {
    let spent: Double
    let total: Double
    let currency: String

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(spent / total, 1)
    }

    private var isOverBudget: Bool {
        total > 0 && spent > total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOverBudget ? Color.red : Color.green)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)

            Text(
                isOverBudget
                    ? "Over budget by \((spent - total).formattedCurrency(code: currency))"
                    : "\(spent.formattedCurrency(code: currency)) of \(total.formattedCurrency(code: currency))"
            )
            .font(.caption)
            .foregroundStyle(isOverBudget ? .red : .secondary)
        }
    }
}
