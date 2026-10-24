import Foundation

/// A costed item that isn't in any budget category yet.
struct CategorySuggestionInput: Identifiable {
    enum Kind { case activity, stay, transport }

    let id: UUID
    let kind: Kind
    let title: String
    let iconName: String
}

struct CategorySuggestion: Identifiable {
    let id: UUID
    let kind: CategorySuggestionInput.Kind
    let title: String
    let categoryID: UUID
    let categoryName: String
}

/// Guesses which of the trip's own budget categories an uncategorized item
/// belongs to, from the item's kind, icon and the words in its title matched
/// against the category names. Nothing is changed here — the caller shows the
/// guesses and applies only the ones the person accepts.
enum BudgetCategorySuggester {
    static func suggest(
        for inputs: [CategorySuggestionInput],
        categories: [(id: UUID, name: String)]
    ) -> [CategorySuggestion] {
        guard !categories.isEmpty else { return [] }
        return inputs.compactMap { input in
            guard let concept = concept(for: input),
                  let match = category(for: concept, in: categories) else { return nil }
            return CategorySuggestion(
                id: input.id, kind: input.kind, title: input.title,
                categoryID: match.id, categoryName: match.name
            )
        }
    }

    private enum Concept: CaseIterable {
        case food, stay, transport, shopping, activities

        /// Words that, in a category's name, mean this concept.
        var categoryWords: [String] {
            switch self {
            case .food: return ["food", "meal", "dining", "eat", "restaurant", "drink", "cafe", "snack"]
            case .stay: return ["stay", "hotel", "accommodation", "lodging", "hostel", "airbnb", "room"]
            case .transport: return ["transport", "commute", "ride", "flight", "fare", "transit", "taxi", "travel"]
            case .shopping: return ["shopping", "souvenir", "gift", "pasalubong"]
            case .activities: return ["activit", "sightsee", "tour", "entertain", "experience", "attraction", "fun"]
            }
        }

        /// Words that, in an item's title, suggest this concept.
        var titleWords: Set<String> {
            switch self {
            case .food: return ["breakfast", "lunch", "dinner", "brunch", "restaurant", "cafe", "coffee", "food", "buffet", "eat", "seafood", "bbq", "ramen", "pizza", "snack", "drinks"]
            case .stay: return ["hotel", "hostel", "airbnb", "resort", "inn"]
            case .transport: return ["flight", "bus", "taxi", "grab", "ferry", "train", "transfer", "rental", "van", "jeepney", "tricycle"]
            case .shopping: return ["shopping", "mall", "market", "souvenir", "souvenirs", "store", "pasalubong"]
            case .activities: return ["tour", "museum", "hike", "hiking", "snorkeling", "diving", "zipline", "temple", "park", "beach", "island"]
            }
        }

        var iconNames: Set<String> {
            switch self {
            case .food: return ["fork.knife", "cup.and.saucer", "takeoutbag.and.cup.and.straw", "wineglass", "mug"]
            case .stay: return ["bed.double"]
            case .transport: return ["airplane", "bus", "tram", "car", "ferry", "car.circle"]
            case .shopping: return ["bag", "cart", "gift", "basket"]
            case .activities: return []
            }
        }
    }

    private static func concept(for input: CategorySuggestionInput) -> Concept? {
        switch input.kind {
        case .stay: return .stay
        case .transport: return .transport
        case .activity: break
        }
        if let byIcon = Concept.allCases.first(where: { $0.iconNames.contains(input.iconName) }) {
            return byIcon
        }
        let words = Set(input.title.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
        return Concept.allCases.first { !$0.titleWords.isDisjoint(with: words) }
    }

    private static func category(for concept: Concept, in categories: [(id: UUID, name: String)]) -> (id: UUID, name: String)? {
        categories.first { category in
            let name = category.name.lowercased()
            return concept.categoryWords.contains { name.contains($0) }
        }
    }
}
