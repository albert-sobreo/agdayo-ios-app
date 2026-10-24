import SwiftUI
import SwiftData
import FirebaseAuth

/// Adds or edits an idea: a title, optionally a place, a note and a link.
struct IdeaEditSheet: View {
    let trip: Trip
    var editingIdea: TripIdea?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService

    @State private var title: String
    @State private var location: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var note: String
    @State private var link: String

    init(trip: Trip, editingIdea: TripIdea? = nil) {
        self.trip = trip
        self.editingIdea = editingIdea
        _title = State(initialValue: editingIdea?.title ?? "")
        _location = State(initialValue: editingIdea?.location ?? "")
        _latitude = State(initialValue: editingIdea?.latitude)
        _longitude = State(initialValue: editingIdea?.longitude)
        _note = State(initialValue: editingIdea?.note ?? "")
        _link = State(initialValue: editingIdea?.link ?? "")
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FormCard(title: "Idea", icon: "lightbulb", accent: trip.theme.accentColor) {
                        FormField("Title") {
                            TextField("e.g. Sunset at the viewpoint", text: $title)
                        }
                        FormField("Place") {
                            LocationSearchField(
                                placeholder: "Optional",
                                text: $location,
                                regionBiasCenter: trip.coordinate,
                                onSelect: { name, coordinate in
                                    location = name
                                    latitude = coordinate?.latitude
                                    longitude = coordinate?.longitude
                                    if title.trimmingCharacters(in: .whitespaces).isEmpty { title = name }
                                }
                            )
                        }
                    }

                    FormCard(title: "Details", icon: "text.alignleft", accent: trip.theme.accentColor) {
                        FormField("Note") {
                            TextField("Why it's worth doing", text: $note, axis: .vertical)
                                .lineLimit(2...5)
                        }
                        FormField("Link") {
                            TextField("Optional", text: $link)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .brandForm(accent: trip.theme.accentColor)
            .navigationTitle(editingIdea == nil ? "Add Idea" : "Edit Idea")
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
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanLink = link.trimmingCharacters(in: .whitespaces)
        if let editingIdea {
            editingIdea.title = cleanTitle
            editingIdea.note = note
            editingIdea.location = location
            editingIdea.latitude = latitude
            editingIdea.longitude = longitude
            editingIdea.link = cleanLink
            TripIdeaService.update(editingIdea, in: trip)
        } else {
            let idea = TripIdea(
                title: cleanTitle,
                note: note,
                location: location,
                latitude: latitude,
                longitude: longitude,
                link: cleanLink,
                addedByUID: authService.firebaseUser?.uid ?? "local",
                trip: trip
            )
            modelContext.insert(idea)
            TripIdeaService.pushIfShared(idea, in: trip)
        }
        dismiss()
    }
}
