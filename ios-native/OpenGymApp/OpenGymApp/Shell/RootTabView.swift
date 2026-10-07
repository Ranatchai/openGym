import SwiftUI

struct RootTabView: View {
    private enum Destination: Hashable {
        case home, plan, stats, exercises
    }

    @Environment(\.language) private var t
    @State private var selection = Destination.home

    var body: some View {
        TabView(selection: $selection) {
            Tab(t("Home"), systemImage: "house", value: .home) {
                HomeView()
            }
            Tab(t("Plan"), systemImage: "calendar", value: .plan) {
                PlanView()
            }
            Tab(t("Stats"), systemImage: "chart.bar", value: .stats) {
                StatsView()
            }
            Tab(t("Exercises"), systemImage: "magnifyingglass", value: .exercises, role: .search) {
                ExercisesView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            WorkoutAccessory()
        }
    }
}

private struct HomeView: View {
    @Environment(\.language) private var t
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            List {
                Section(t("Today")) {
                    Label(t("Freestyle workout (pick as you go)"), systemImage: "dumbbell")
                }
                Section {
                    AuraProminentButton(title: t("Start workout"), systemImage: "play.fill") {}
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuraDesk() }
            .navigationTitle("openGym")
            .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
        }
    }
}

private struct PlanView: View {
    @Environment(\.language) private var t
    @Environment(\.locale) private var locale

    private var weekdays: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.standaloneWeekdaySymbols
        return Array(symbols[1...] + symbols[..<1])
    }

    var body: some View {
        NavigationStack {
            List {
                Section(t("This week")) {
                    ForEach(weekdays, id: \.self) { day in
                        LabeledContent(day, value: t("Rest day"))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuraDesk() }
            .navigationTitle(t("Plan"))
        }
    }
}

private struct StatsView: View {
    @Environment(\.language) private var t

    var body: some View {
        NavigationStack {
            List {
                Section(t("This week")) {
                    LabeledContent(t("Workouts")) { Text(0, format: .number).auraData() }
                    LabeledContent(t("Sets")) { Text(0, format: .number).auraData() }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuraDesk() }
            .navigationTitle(t("Stats"))
        }
    }
}
