import Foundation
import SwiftUI

/// A short confirmation shown at the bottom of the window. `undo` puts back what was removed.
struct AsterToast: Identifiable {
    let id = UUID()
    var text: String
    var symbol = "checkmark"
    var undo: (() -> Void)?
}

/// Housekeeping the interface offers on top of the store: removing things (with undo),
/// editing tasks, clearing the inbox, and the numbers shown on the home page.
extension AsterStore {
    func show(_ text: String, symbol: String = "checkmark", undo: (() -> Void)? = nil) {
        toast = AsterToast(text: text, symbol: symbol, undo: undo)
    }

    // MARK: Missions

    func deleteMission(_ id: UUID) {
        guard !isRunning(id) else { notice = "Espera a que termine esta misión para eliminarla."; return }
        guard let index = state.missions.firstIndex(where: { $0.id == id }) else { return }
        let removed = state.missions.remove(at: index)
        if selectedMission == id { selectedMission = nil }
        save()
        show(L("Misión eliminada"), symbol: "trash") { [weak self] in
            guard let self, !self.state.missions.contains(where: { $0.id == id }) else { return }
            self.state.missions.insert(removed, at: min(index, self.state.missions.count)); self.save()
        }
    }
    /// Conversations worth returning to, newest first: no archived ones and nothing empty.
    func recentMissions(limit: Int = 4) -> [Mission] {
        Array(state.missions.filter { $0.archived != true && $0.messages.contains { !$0.text.isEmpty } }.sorted { $0.updated > $1.updated }.prefix(limit))
    }

    // MARK: Tasks

    func deleteTask(_ id: UUID) {
        guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        let removed = state.tasks.remove(at: index); save()
        show(L("Tarea eliminada"), symbol: "trash") { [weak self] in
            guard let self, !self.state.tasks.contains(where: { $0.id == id }) else { return }
            self.state.tasks.insert(removed, at: min(index, self.state.tasks.count)); self.save()
        }
    }
    func updateTask(_ task: WorkTask) {
        var task = task
        task.title = String(task.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        guard !task.title.isEmpty, let index = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[index] = task; save()
    }
    func clearCompletedTasks() {
        let done = state.tasks.filter(\.done); guard !done.isEmpty else { return }
        let before = state.tasks
        state.tasks.removeAll(where: \.done); save()
        show(LF("%d tareas terminadas eliminadas", done.count), symbol: "trash") { [weak self] in self?.state.tasks = before; self?.save() }
    }
    /// Open tasks in the order they need attention: overdue, due today, later, then undated.
    var openTasks: [WorkTask] {
        state.tasks.filter { !$0.done }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.created > b.created
            }
        }
    }

    // MARK: Inbox

    func deleteNote(_ id: UUID) {
        guard let index = state.inbox.firstIndex(where: { $0.id == id }) else { return }
        let removed = state.inbox.remove(at: index); save()
        show(L("Novedad eliminada"), symbol: "trash") { [weak self] in
            guard let self, !self.state.inbox.contains(where: { $0.id == id }) else { return }
            self.state.inbox.insert(removed, at: min(index, self.state.inbox.count)); self.save()
        }
    }
    func markAllRead() {
        guard unread > 0 else { return }
        for index in state.inbox.indices { state.inbox[index].read = true }
        save()
    }

    // MARK: Home

    /// Messages exchanged with Aster on each of the last seven days, oldest first.
    func weekActivity(now: Date = Date(), calendar: Calendar = .current) -> [(day: Date, count: Int)] {
        let today = calendar.startOfDay(for: now)
        var counts: [Date: Int] = [:]
        for mission in state.missions {
            for message in mission.messages where !message.text.isEmpty {
                let day = calendar.startOfDay(for: message.date)
                if let age = calendar.dateComponents([.day], from: day, to: today).day, (0..<7).contains(age) { counts[day, default: 0] += 1 }
            }
        }
        return (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { ($0, counts[$0] ?? 0) }
        }
    }
}
