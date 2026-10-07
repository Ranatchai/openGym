import OpenGymCore
import SwiftUI

struct ExercisesView: View {
    private static let catalogue: [Exercise] = {
        let url = Bundle.main.url(forResource: "exercises", withExtension: "json")!
        let exercises = try! JSONDecoder().decode([Exercise].self, from: Data(contentsOf: url))
        return exercises.sorted { $0.n.localizedStandardCompare($1.n) == .orderedAscending }
    }()

    @Environment(\.language) private var t
    @State private var query = ""

    private var matches: [Exercise] {
        query.isEmpty ? Self.catalogue : Self.catalogue.filter { $0.n.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(matches) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.n.capitalized)
                    Text(t(exercise.tg).capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuraDesk() }
            .navigationTitle(t("Exercises"))
            .searchable(text: $query, prompt: t("Search {0} exercises…", Self.catalogue.count.formatted()))
        }
    }
}
