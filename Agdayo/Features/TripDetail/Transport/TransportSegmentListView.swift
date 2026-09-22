import SwiftUI
import SwiftData

struct TransportSegmentListView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var editingSegment: TransportSegment?

    private var sorted: [TransportSegment] {
        trip.transportSegments.sorted { $0.departureDate < $1.departureDate }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                EmptyStateView(
                    iconName: "airplane",
                    title: "No Transport Yet",
                    message: "Add flights, buses, or other ways you'll get around.",
                    actionTitle: "Add Transport"
                ) {
                    isAdding = true
                }
            } else {
                List {
                    ForEach(sorted) { segment in
                        Button {
                            editingSegment = segment
                        } label: {
                            TransportSegmentRow(segment: segment, accentColor: trip.theme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Transport")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add Transport", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            TransportSegmentEditSheet(trip: trip)
        }
        .sheet(item: $editingSegment) { segment in
            TransportSegmentEditSheet(trip: trip, editingSegment: segment)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }
}

private struct TransportSegmentRow: View {
    let segment: TransportSegment
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: segment.mode.iconName)
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(segment.departureLocation) → \(segment.arrivalLocation)")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text("\(segment.departureDate.formatted(date: .abbreviated, time: .omitted)) · \(segment.departureTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PillTag(text: segment.mode.displayName, background: accentColor.opacity(0.15), foreground: accentColor)
        }
        .padding(.vertical, 6)
    }
}
