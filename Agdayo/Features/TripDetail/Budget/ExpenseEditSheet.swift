import SwiftUI
import SwiftData
import FirebaseAuth

/// Add/edit a standalone purchase that isn't tied to any Activity/
/// Accommodation/Transport (e.g. a souvenir bought on the go). Unlike those
/// other cost-tracking sheets, a budget category (or individual budget) is
/// mandatory here — see `isValid` — since attaching the expense somewhere
/// is the whole point of tracking it separately.
struct ExpenseEditSheet: View {
    let trip: Trip
    var editingExpense: Expense?
    var memberProfiles: [AppUserProfile] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService

    @State private var name: String
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var costText: String
    @State private var costCurrency: String
    @State private var exchangeRate: Double?
    @State private var budgetCategoryID: UUID?
    @State private var budgetMemberUID: String?
    @State private var paidByUID: String?
    @State private var splitUIDs: Set<String>
    @State private var splitAmounts: [String: Double]

    init(trip: Trip, editingExpense: Expense? = nil, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.editingExpense = editingExpense
        self.memberProfiles = memberProfiles
        _name = State(initialValue: editingExpense?.name ?? "")
        _hasDate = State(initialValue: editingExpense?.date != nil)
        _date = State(initialValue: editingExpense?.date ?? trip.startDate)
        _hasTime = State(initialValue: editingExpense?.time != nil)
        _time = State(initialValue: Self.time(from: editingExpense?.time ?? "12:00"))
        _costText = State(initialValue: editingExpense.flatMap { $0.cost == 0 ? nil : String($0.cost) } ?? "")
        _costCurrency = State(initialValue: editingExpense?.costCurrency ?? trip.currency)
        _exchangeRate = State(initialValue: editingExpense?.exchangeRateToTripCurrency)
        _budgetCategoryID = State(initialValue: editingExpense?.budgetCategoryID)
        _budgetMemberUID = State(initialValue: editingExpense?.budgetMemberUID)
        _paidByUID = State(initialValue: editingExpense?.paidByUID)
        if let editingExpense, !editingExpense.splitUIDs.isEmpty {
            _splitUIDs = State(initialValue: Set(editingExpense.splitUIDs))
        } else {
            _splitUIDs = State(initialValue: Set(memberProfiles.map(\.uid)))
        }
        _splitAmounts = State(initialValue: editingExpense?.splitAmounts ?? [:])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (budgetCategoryID != nil || budgetMemberUID != nil)
            && (Double(costText) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FormCard(title: "Expense", icon: "receipt", accent: trip.theme.accentColor) {
                        FormField("Name") {
                            TextField("e.g. Souvenirs", text: $name)
                        }
                        FormField {
                            BudgetCategoryPicker(categories: trip.budgetCategories, memberProfiles: memberProfiles, categoryID: $budgetCategoryID, memberUID: $budgetMemberUID)
                        }
                    }

                    FormCard(title: "When", icon: "clock", accent: trip.theme.accentColor) {
                        FormField {
                            Toggle("Add date", isOn: $hasDate)
                        }
                        if hasDate {
                            FormField {
                                DatePicker("Date", selection: $date, in: trip.startDate...trip.endDate, displayedComponents: .date)
                            }
                        }
                        FormField {
                            Toggle("Add time", isOn: $hasTime)
                        }
                        if hasTime {
                            FormField {
                                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            }
                        }
                    }

                    FormCard(title: "Cost", icon: "wallet.pass", accent: trip.theme.accentColor) {
                        FormField("Amount") {
                            TextField("Amount", text: $costText)
                                .keyboardType(.decimalPad)
                        }
                        FormField {
                            Picker("Currency", selection: $costCurrency) {
                                ForEach(CurrencyCode.common, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .onChange(of: costCurrency) { _, _ in exchangeRate = nil }
                        }
                        if costCurrency != trip.currency {
                            FormField {
                                ExchangeRateField(amount: Double(costText) ?? 0, fromCurrency: costCurrency, toCurrency: trip.currency, rate: $exchangeRate)
                            }
                        }
                    }

                    ExpenseSplitSection(
                        memberProfiles: memberProfiles,
                        totalCost: Double(costText) ?? 0,
                        currencyCode: costCurrency,
                        accentColor: trip.theme.accentColor,
                        paidByUID: $paidByUID,
                        splitUIDs: $splitUIDs,
                        splitAmounts: $splitAmounts
                    )
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .brandForm(accent: trip.theme.accentColor)
            .navigationTitle(editingExpense == nil ? "Add Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .onAppear {
            if editingExpense == nil, paidByUID == nil {
                paidByUID = authService.firebaseUser?.uid
            }
        }
    }

    private func save() {
        let cost = Double(costText) ?? 0
        let rate = costCurrency == trip.currency ? nil : exchangeRate
        let expenseDate: Date? = hasDate ? date : nil
        let expenseTime: String? = hasTime ? Self.timeString(from: time) : nil

        let expense: Expense
        if let editingExpense {
            expense = editingExpense
            expense.name = name.trimmingCharacters(in: .whitespaces)
            expense.date = expenseDate
            expense.time = expenseTime
            expense.cost = cost
            expense.costCurrency = costCurrency
            expense.exchangeRateToTripCurrency = rate
            expense.budgetCategoryID = budgetCategoryID
            expense.budgetMemberUID = budgetMemberUID
            expense.paidByUID = paidByUID
            expense.splitUIDs = Array(splitUIDs)
            expense.splitAmounts = splitAmounts
        } else {
            expense = Expense(
                name: name.trimmingCharacters(in: .whitespaces),
                date: expenseDate,
                time: expenseTime,
                cost: cost,
                costCurrency: costCurrency,
                exchangeRateToTripCurrency: rate,
                budgetCategoryID: budgetCategoryID,
                budgetMemberUID: budgetMemberUID,
                paidByUID: paidByUID,
                splitUIDs: Array(splitUIDs),
                splitAmounts: splitAmounts,
                trip: trip
            )
            modelContext.insert(expense)
        }
        if trip.ownerUID != nil {
            let tripID = trip.id
            let expenseID = expense.id
            let dto = expense.dto
            Task {
                try? await FirestoreCollectionSync.push(tripID: tripID, collection: "expenses", docID: expenseID, data: dto)
            }
        }
        dismiss()
    }

    private static func time(from string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: string) ?? .now
    }

    private static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
