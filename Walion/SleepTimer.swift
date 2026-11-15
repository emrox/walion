import SwiftUI

/// Moon button in the now-playing bar. Shows the countdown while a timer runs.
struct SleepTimerMenu: View {
    @Environment(RadioPlayer.self) private var player
    @State private var isPickingCustom = false

    var body: some View {
        Menu {
            if player.sleepAt != nil {
                Button("Turn Off Sleep Timer", systemImage: "moon.zzz", role: .destructive) {
                    player.setSleepTimer(nil)
                }
                Divider()
            }
            Button("15 Minutes") { player.setSleepTimer(.seconds(15 * 60)) }
            Button("30 Minutes") { player.setSleepTimer(.seconds(30 * 60)) }
            Button("1 Hour") { player.setSleepTimer(.seconds(60 * 60)) }
            Button("Custom…") { isPickingCustom = true }
        } label: {
            Label("Sleep Timer", systemImage: player.sleepAt == nil ? "moon.zzz" : "moon.zzz.fill")
                .labelStyle(.iconOnly)
                .font(.title3)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .sheet(isPresented: $isPickingCustom) {
            CustomSleepTimer()
        }
        // Outside the menu label: in there iOS clips the countdown's leading digit.
        if let sleepAt = player.sleepAt {
            Text(sleepAt, style: .timer)
                .font(.caption)
                .monospacedDigit()
                .accessibilityLabel(Text("Sleep timer ends in \(sleepAt, style: .relative)"))
        }
    }
}

/// Free duration: hours and minutes.
private struct CustomSleepTimer: View {
    @Environment(RadioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 0
    @State private var minutes = 45

    var body: some View {
        NavigationStack {
            HStack {
                Picker("Hours", selection: $hours) {
                    ForEach(0...8, id: \.self) { Text("\($0) h").tag($0) }
                }
                Picker("Minutes", selection: $minutes) {
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text("\($0) min").tag($0) }
                }
            }
            #if os(iOS)
            .pickerStyle(.wheel)
            .labelsHidden()
            #endif
            .padding()
            .navigationTitle("Sleep Timer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        player.setSleepTimer(.seconds((hours * 60 + minutes) * 60))
                        dismiss()
                    }
                    .disabled(hours == 0 && minutes == 0)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
