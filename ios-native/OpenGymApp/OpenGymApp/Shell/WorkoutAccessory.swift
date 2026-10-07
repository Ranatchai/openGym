import SwiftUI

/// The idle state of the mini-player above the tab bar. With no workout running it offers
/// to start one; the running state arrives with the workout screen.
struct WorkoutAccessory: View {
    @Environment(\.language) private var t

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(.tint)
            Text(t("Start workout"))
                .fontWeight(.semibold)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout-accessory")
    }
}
