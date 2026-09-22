import Foundation

/// Curated SF Symbol names for the activity icon picker, grouped by category.
/// UI concern only — not persisted as a model concept.
enum ActivityIconLibrary {
    static let categories: [(name: String, icons: [String])] = [
        ("Travel", ["airplane", "airplane.departure", "airplane.arrival", "car", "bicycle", "figure.walk"]),
        ("Transport", ["bus", "tram", "ferry", "fuelpump", "parkingsign.circle"]),
        ("Accommodation", ["bed.double", "house", "building.2", "tent"]),
        ("Food", ["fork.knife", "cup.and.saucer", "wineglass", "birthday.cake"]),
        ("Fun", ["figure.walk.motion", "camera", "ticket", "gamecontroller", "music.note", "theatermasks"]),
        ("Planning", ["calendar", "checklist", "clock", "map"]),
        ("Social", ["person.2", "person.3"]),
        ("Weather", ["sun.max", "cloud.rain", "snowflake"]),
        ("Budgeting", ["banknote", "creditcard", "wallet.pass"]),
        ("Misc", ["mappin.and.ellipse", "star", "flag", "questionmark.circle"]),
    ]

    static let allIcons: [String] = categories.flatMap { $0.icons }
}
