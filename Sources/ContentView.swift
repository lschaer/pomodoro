import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var timer: PomodoroTimer

    var body: some View {
        VStack(spacing: 14) {
            if timer.taskLocked {
                // Fixed topic; × removes it when you're done with this work package.
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timer.task)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Button { timer.clearTask() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!timer.canClearTask)
                    .opacity(timer.canClearTask ? 1 : 0.3)
                    .help(timer.canClearTask ? "Done with this topic" : "Can be cleared after the focus session")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            } else {
                TextField("What are you working on?", text: $timer.task)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(spacing: 2) {
                Text(timer.phase.label.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(timer.phase == .focus ? Color.red : Color.green)
                HStack(spacing: 12) {
                    Text("\(timer.minutesLeft)")
                        .font(.system(size: 52, weight: .light, design: .rounded))
                        .monospacedDigit()
                    SecondDotsRing(lit: timer.litDots,
                                   color: timer.phase == .focus ? .red : .green)
                }
            }

            ProgressView(value: timer.progress)
                .tint(timer.phase == .focus ? .red : .green)

            HStack {
                Button(timer.isRunning ? "Pause" : (timer.isPaused ? "Resume" : "Start")) {
                    timer.toggle()
                }
                .keyboardShortcut(.defaultAction)
                Button("Reset") { timer.reset() }
                    .disabled(!timer.isActive)
                Button("Skip") { timer.skip() }
            }

            if !timer.isActive {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Focus (min)").font(.caption).foregroundStyle(.secondary)
                    Picker("Focus", selection: $timer.focusMinutes) {
                        ForEach(PomodoroTimer.focusOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Text("Break").font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Picker("Break", selection: $timer.breakMinutes) {
                        ForEach(PomodoroTimer.breakOptions, id: \.self) { m in
                            Text(m == PomodoroTimer.lunchMinutes ? "Lunch 1h" : "\(m)m").tag(m)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            if !timer.todayLog.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(timer.todayLog.reversed().prefix(6))) { entry in
                        HStack(spacing: 8) {
                            Text(entry.start, format: .dateTime.hour().minute())
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(entry.task).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 4)
                            Text("\(entry.minutes)m").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }

            HStack(spacing: 10) {
                let total = timer.todayLog.reduce(0) { $0 + $1.minutes }
                Text("Today: \(timer.completedToday) · \(total / 60)h \(total % 60)m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !timer.todayLog.isEmpty {
                    Button("Copy log") { timer.copyTodayLog() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            Toggle("Open at login", isOn: $timer.openAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear { timer.refreshLoginItem() }
        }
        .padding(16)
        .frame(width: 300)
    }
}
