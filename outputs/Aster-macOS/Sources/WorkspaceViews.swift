import SwiftUI

struct TaskBoardView: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var adding = false
    @State private var editing: WorkTask?
    @State private var completed = false
    @State private var companyID: UUID?
    @State private var query = ""
    @State private var quick = ""
    @State private var section = "Aster"
    @State private var addingAlert = false
    private var tasks: [WorkTask] {
        store.state.tasks.filter { (completed || !$0.done) && (companyID == nil || $0.companyID == companyID) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    /// Tasks by when they need attention: overdue, today, later, undated, and finished last.
    static func groups(_ tasks: [WorkTask], now: Date = Date(), calendar: Calendar = .current) -> [(title: String, items: [WorkTask])] {
        let today = calendar.startOfDay(for: now), tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        func bucket(_ task: WorkTask) -> Int {
            if task.done { return 4 }
            guard let due = task.due else { return 3 }
            return due < today ? 0 : due < tomorrow ? 1 : 2
        }
        let titles = ["Vencidas", "Hoy", "Próximas", "Sin fecha", "Terminadas"]
        return Dictionary(grouping: tasks, by: bucket).sorted { $0.key < $1.key }.map { key, items in
            (titles[key], items.sorted { ($0.due ?? .distantFuture, $1.created) < ($1.due ?? .distantFuture, $0.created) })
        }
    }
    var body: some View {
        let total = store.state.tasks.count, done = store.state.tasks.filter(\.done).count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Ideas que avanzan.", subtitle: "Próximos pasos para ti y para tus proyectos.") {
                    if total > 0 {
                        HStack(spacing: 9) {
                            ProgressRing(progress: Double(done) / Double(max(1, total))).frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(done)/\(total)").font(.asterDisplay(13)).monospacedDigit().contentTransition(.numericText())
                                Text(L("hechas")).font(.system(size: 10)).foregroundStyle(Color.asterMuted)
                            }
                        }.padding(.trailing, 4).accessibilityElement(children: .combine)
                    }
                    if section != "Apple" { GlassAction(title: section == "Avisos" ? "Nuevo aviso" : "Nueva tarea", symbol: "plus", prominent: true) { if section == "Avisos" { addingAlert = true } else { adding = true } } }
                }
                GlassSegmented(options: [("Aster", "Aster"), ("Apple", "Apple"), ("Avisos", L("Avisos"))], selection: $section).frame(width: 300)
                Group {
                    if section == "Aster" { asterTasks } else if section == "Apple" { appleReminders } else { alerts }
                }.transition(.opacity)
            }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 25).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity)
                .animation(AsterMotion.spring(reduceMotion), value: store.state.tasks.map(\.done))
                .animation(AsterMotion.spring(reduceMotion), value: store.state.tasks.count)
        }.scrollIndicators(.hidden)
         .sheet(isPresented: $adding) { TaskForm(initialCompanyID: companyID) }
         .sheet(item: $editing) { TaskForm(original: $0) }
         .sheet(isPresented: $addingAlert) { AlertForm() }
         .onChange(of: section) { _, new in if new == "Apple" { Task { await store.refreshReminders() } } }
    }
    @ViewBuilder private var asterTasks: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").font(.system(size: 17)).foregroundStyle(Color.asterAccent)
            TextField(L("Añadir una tarea y pulsar ↵"), text: $quick).textFieldStyle(.plain).font(.system(size: 13.5))
                .onSubmit { if store.addTask(quick, companyID: companyID) != nil { quick = "" } }
            if !quick.isEmpty { KeyCap("↵") }
        }.padding(.horizontal, 14).frame(height: 44).frostedSurface(16)
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.asterMuted)
                TextField(L("Buscar tareas…"), text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }.padding(.horizontal, 10).frame(height: 30).frame(maxWidth: 260).background(Color.asterWell, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.asterHairline, lineWidth: 1))
            Picker(L("Proyecto"), selection: $companyID) { Text(L("Todos los proyectos")).tag(nil as UUID?); ForEach(store.companies) { Text($0.name).tag(Optional($0.id)) } }.labelsHidden().frame(width: 190)
            Spacer()
            if completed && store.state.tasks.contains(where: \.done) { Button(L("Limpiar terminadas")) { store.clearCompletedTasks() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.asterAccent) }
            ModeChip(title: L("Terminadas"), selected: completed) { withAnimation(AsterMotion.spring(reduceMotion)) { completed.toggle() } }
        }.font(.system(size: 11))
        if tasks.isEmpty { WorkspaceEmpty(symbol: "checklist", title: "Un buen siguiente paso", detail: "Añade una tarea o pide al equipo que guarde los próximos pasos de una misión.") }
        ForEach(Self.groups(tasks), id: \.title) { group in
            HStack(spacing: 6) {
                MonoLabel(L(group.title), color: group.title == "Vencidas" ? .orange : .asterMuted, size: 9.5)
                Text("\(group.items.count)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Color.asterMuted)
            }.padding(.leading, 6).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(Color.asterHairline).frame(height: 1).padding(.leading, 46) }
                    TaskRow(item: item, edit: { editing = item })
                }
            }.frostedSurface(18)
        }
    }
    private var appleReminders: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(L(store.remindersStatus)).font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); ModeChip(title: L("Terminadas"), selected: completed) { completed.toggle() }; GlassAction(title: store.state.preferences.watchReminders == true ? "Actualizar" : "Conectar Recordatorios", symbol: "arrow.clockwise") { if store.state.preferences.watchReminders == true { Task { await store.refreshReminders() } } else { store.connectReminders() } } }
            if store.reminders.isEmpty { WorkspaceEmpty(symbol: "checklist", title: "Tus recordatorios de Apple", detail: "Conecta Recordatorios para ver tus listas aquí. Después puedes pedirle a Aster que cree o complete tareas.") }
            ForEach(store.reminders.filter { completed || !$0.completed }) { reminder in
                HStack(alignment: .top, spacing: 13) {
                    Button { store.completeReminder(reminder.id) } label: { Image(systemName: reminder.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 19, weight: .light)).foregroundStyle(reminder.completed ? Color.asterAccent : Color.asterMuted).contentTransition(.symbolEffect(.replace)) }.buttonStyle(FluidButtonStyle()).accessibilityLabel(reminder.completed ? L("Marcar pendiente") : L("Marcar terminada"))
                    VStack(alignment: .leading, spacing: 6) { Text(reminder.title).font(.system(size: 13, weight: .medium)).strikethrough(reminder.completed); if !reminder.notes.isEmpty { Text(reminder.notes).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }; HStack { Text(reminder.list); if let due = reminder.due { Text(AsterDate.stamp(due, date: .abbreviated, time: .shortened)) } }.font(.system(size: 10.5)).foregroundStyle(.secondary) }; Spacer()
                }.padding(16).frostedSurface(18)
            }
        }
    }
    private var alerts: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.state.preferences.notifications { HStack { Label(L("Activa las notificaciones para recibir tus avisos."), systemImage: "bell.badge").font(.system(size: 12)); Spacer(); Button(L("Permitir avisos"), action: store.requestNotifications).glassControl(prominent: true) }.padding(16).frostedSurface(18, tint: .asterPollen) }
            if store.state.alerts.isEmpty { WorkspaceEmpty(symbol: "bell", title: "Te lo recordaré.", detail: "Crea un aviso con fecha o pídeselo en la conversación. También puedes programarlo cada día o cada semana.") }
            ForEach(store.state.alerts.sorted { $0.date < $1.date }) { alert in
                HStack(spacing: 13) {
                    Image(systemName: alert.recurrence == "none" ? "bell" : "repeat").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.asterAccent).frame(width: 34, height: 34).background(Color.asterAccentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) { Text(alert.text).font(.system(size: 13, weight: .medium)); Text(AsterDate.stamp(alert.date, date: .abbreviated, time: .shortened) + " · " + L(alert.recurrence == "daily" ? "Cada día" : alert.recurrence == "weekly" ? "Cada semana" : "Una vez") + " · " + L(alert.scheduled ? "Programado en macOS" : "Pendiente de permiso")).font(.system(size: 10.5)).foregroundStyle(.secondary) }
                    Spacer(); GlassIconButton(symbol: "xmark", title: "Cancelar aviso") { store.cancelAlert(alert.id) }
                }.padding(16).frostedSurface(18)
            }
        }
    }
}

/// One task: tick it, open its mission, hand it to Aster, or edit and delete it.
private struct TaskRow: View {
    @EnvironmentObject var store: AsterStore
    var item: WorkTask
    var edit: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { store.toggleTask(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.system(size: 19, weight: .light)).foregroundStyle(item.done ? Color.asterAccent : Color.asterMuted)
                    .contentTransition(.symbolEffect(.replace)).frame(width: 24, height: 24).contentShape(Rectangle())
            }.buttonStyle(FluidButtonStyle()).accessibilityLabel(item.done ? L("Marcar pendiente") : L("Marcar terminada"))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 13, weight: .medium)).strikethrough(item.done).foregroundStyle(item.done ? Color.asterMuted : Color.primary).textSelection(.enabled).lineLimit(3)
                HStack(spacing: 7) {
                    Text(store.state.companies.first { $0.id == item.companyID }?.name ?? L("Personal"))
                    if let mode = store.state.specialists.first(where: { $0.id == item.specialistID }), mode.id != "director" { Text("·"); Label(mode.mode, systemImage: mode.symbol).labelStyle(TightLabelStyle()) }
                    if let due = item.due { Text("·"); Text(AsterDate.day(due)).foregroundStyle(due < Calendar.current.startOfDay(for: Date()) && !item.done ? Color.orange : Color.asterMuted) }
                }.font(.system(size: 10.5)).foregroundStyle(Color.asterMuted)
            }
            Spacer(minLength: 10)
            HStack(spacing: 4) {
                icon("pencil", "Editar tarea", action: edit)
                icon("trash", "Eliminar") { store.deleteTask(item.id) }
            }.opacity(hovering ? 1 : 0)
            if let id = item.missionID, store.state.missions.contains(where: { $0.id == id }) { GlassIconButton(symbol: "bubble.left", title: "Ver misión") { store.openMission(id) } }
            if !item.done { GlassAction(title: "Trabajar en ello", symbol: "sparkle") { store.executeTask(item) }.disabled(!store.hasCapacity) }
        }.padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
            .onHover { hovering = $0 }.animation(.easeOut(duration: 0.14), value: hovering)
            .contextMenu {
                Button(L("Editar tarea"), action: edit)
                Button(L(item.done ? "Marcar pendiente" : "Marcar terminada")) { store.toggleTask(item.id) }
                Divider(); Button(L("Eliminar"), role: .destructive) { store.deleteTask(item.id) }
            }
    }
    private func icon(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Color.asterMuted).frame(width: 26, height: 26).hoverFill(Circle()).contentShape(Circle()) }
            .buttonStyle(.plain).accessibilityLabel(L(title)).help(L(title))
    }
}

struct TaskForm: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var companyID: UUID?
    @State private var agentID: String
    @State private var hasDue: Bool
    @State private var due: Date
    private let original: WorkTask?
    init(initialCompanyID: UUID? = nil, original: WorkTask? = nil) {
        self.original = original
        _title = State(initialValue: original?.title ?? ""); _companyID = State(initialValue: original?.companyID ?? initialCompanyID)
        _agentID = State(initialValue: original?.specialistID ?? "director"); _hasDue = State(initialValue: original?.due != nil)
        _due = State(initialValue: original?.due ?? Date().addingTimeInterval(86400))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(L(original == nil ? "Un siguiente paso." : "Editar tarea")).font(.asterDisplay(26)); Spacer(); GlassIconButton(symbol: "xmark", title: "Cerrar") { dismiss() } }
            TextField(L("¿Qué hay que hacer?"), text: $title, axis: .vertical).lineLimit(2...4).textFieldStyle(.aster)
            VStack(alignment: .leading, spacing: 12) {
                Picker(L("Proyecto"), selection: $companyID) { Text(L("Personal")).tag(nil as UUID?); ForEach(store.companies) { Text($0.name).tag(Optional($0.id)) } }
                Picker(L("Modo"), selection: $agentID) { ForEach(store.state.specialists) { Text($0.mode + " · " + L($0.role)).tag($0.id) } }
                Toggle(L("Añadir fecha"), isOn: $hasDue.animation()).toggleStyle(.switch)
                if hasDue { DatePicker(L("Para el"), selection: $due, displayedComponents: .date) }
            }.padding(16).frostedSurface(18)
            HStack {
                Button(L("Cancelar")) { dismiss() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.asterMuted).keyboardShortcut(.cancelAction)
                Spacer()
                Button { save() } label: { Label(L(original == nil ? "Guardar tarea" : "Guardar"), systemImage: "checkmark").labelStyle(TightLabelStyle()) }
                    .buttonStyle(AsterButtonStyle(prominent: true)).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)
            }
        }.font(.system(size: 12)).padding(26).frame(width: 480).background(AmbientBackdrop(tint: Color.asterAccent, vibrant: false))
    }
    private func save() {
        if var task = original { task.title = title; task.companyID = companyID; task.specialistID = agentID; task.due = hasDue ? due : nil; store.updateTask(task) }
        else { store.addTask(title, companyID: companyID, specialistID: agentID, due: hasDue ? due : nil) }
        dismiss()
    }
}

struct AlertForm: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date().addingTimeInterval(3600)
    @State private var recurrence = "none"
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text(L("Te lo recordaré.")).font(.asterDisplay(26)); Spacer(); GlassIconButton(symbol: "xmark", title: "Cerrar") { dismiss() } }
            TextField(L("¿Qué quieres que te recuerde?"), text: $text, axis: .vertical).lineLimit(2...4).textFieldStyle(.aster)
            DatePicker(L("Cuándo"), selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            Picker(L("Repetir"), selection: $recurrence) { Text(L("Una vez")).tag("none"); Text(L("Cada día")).tag("daily"); Text(L("Cada semana")).tag("weekly") }
            Text(L("macOS entrega el aviso a la hora programada. Puedes verlo y cancelarlo en Tareas → Avisos.")).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            HStack { Spacer(); GlassAction(title: "Guardar aviso", symbol: "bell.badge", prominent: true) { store.addAlert(text: text, date: date, recurrence: recurrence); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.font(.system(size: 12)).padding(28).frame(width: 490).background(AmbientBackdrop(tint: Color.asterAccent, vibrant: false))
    }
}

struct MemoryView: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var companyID: UUID?
    @State private var editing: MemoryEntry?
    @State private var query = ""
    @State private var learnedOnly = false
    private var entries: [MemoryEntry] {
        store.state.memories.filter { (!learnedOnly || $0.learned == true) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Que te conozca mejor.", subtitle: "Tus preferencias, tu contexto y las cosas que merece recordar.")
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("Añadir un recuerdo"), systemImage: "plus.circle").font(.asterDisplay(14.5))
                    TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden).frame(height: 76).padding(10).background(Color.asterWell, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.asterHairline, lineWidth: 1))
                    HStack {
                        Picker(L("Contexto"), selection: $companyID) { Text(L("Personal · todas las misiones")).tag(nil as UUID?); ForEach(store.companies) { Text($0.name).tag(Optional($0.id)) } }.frame(maxWidth: 300)
                        Spacer(); GlassAction(title: "Recordar", symbol: "plus", prominent: true) { store.addMemory(text, companyID: companyID); if store.notice.isEmpty { text = "" } }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.padding(18).frostedSurface(20)
                Text(L(!store.settings.useMemory ? "La memoria está desactivada. Puedes activarla en Ajustes." : store.settings.learns ? "Aster aprende de lo que le cuentas y mantiene esta memoria al día; lo marcado como aprendido lo puedes editar o eliminar. Los recuerdos de un proyecto solo se usan en ese proyecto." : "La memoria se incluye en tus misiones. Los recuerdos de un proyecto solo se usan en ese proyecto.")).font(.system(size: 11.5)).foregroundStyle(.secondary).lineSpacing(4).padding(.horizontal, 4)
                if store.state.memories.isEmpty { WorkspaceEmpty(symbol: "brain", title: "Un poco más de ti", detail: "Guarda cómo te gusta trabajar, tus objetivos o contexto útil. Aster también aprende de lo que le cuentas en vuestras conversaciones.") }
                else {
                    HStack(spacing: 8) {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.asterMuted)
                            TextField(L("Buscar en la memoria…"), text: $query).textFieldStyle(.plain).font(.system(size: 12))
                        }.padding(.horizontal, 10).frame(height: 30).frame(maxWidth: 280).background(Color.asterWell, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.asterHairline, lineWidth: 1))
                        ModeChip(title: L("Aprendido"), selected: learnedOnly) { withAnimation(AsterMotion.spring(reduceMotion)) { learnedOnly.toggle() } }
                        Spacer()
                        Text(LF("%d recuerdos", entries.count)).font(.system(size: 11)).foregroundStyle(Color.asterMuted).contentTransition(.numericText())
                    }
                    if entries.isEmpty { Text(L("Nada coincide con tu búsqueda.")).font(.system(size: 12)).foregroundStyle(Color.asterMuted).padding(8) }
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 11) {
                        Text(entry.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                        HStack(spacing: 8) {
                            if entry.learned == true { Label(L("Aprendido"), systemImage: "sparkle").labelStyle(TightLabelStyle()).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.asterPollen).padding(.horizontal, 8).padding(.vertical, 3).background(Color.asterPollenSoft, in: Capsule()) }
                            Text(store.state.companies.first { $0.id == entry.companyID }?.name ?? L("Personal")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            Text("· " + AsterDate.relative(entry.date)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            Spacer(); Button(L("Editar")) { editing = entry }; Button(L("Eliminar")) { withAnimation(AsterMotion.spring(reduceMotion)) { store.removeMemory(entry.id) } }
                        }.font(.system(size: 11)).glassControl()
                    }.padding(18).frostedSurface(19).transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 25).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden).sheet(item: $editing) { entry in MemoryEditor(entry: entry) }
    }
}

struct MemoryEditor: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: MemoryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L("Editar recuerdo")).font(.asterDisplay(24))
            TextEditor(text: $entry.text).font(.system(size: 13)).frame(height: 180).scrollContentBackground(.hidden).padding(12).frostedSurface(16)
            HStack { Button(L("Cancelar")) { dismiss() }.buttonStyle(.plain).foregroundStyle(Color.asterMuted).keyboardShortcut(.cancelAction); Spacer(); GlassAction(title: "Guardar", symbol: "checkmark", prominent: true) { store.updateMemory(entry); dismiss() }.disabled(entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(26).frame(width: 480).background(AmbientBackdrop(tint: Color.asterAccent, vibrant: false))
    }
}

struct RenameMissionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AsterStore
    let mission: Mission
    @State var title: String
    init(mission: Mission) { self.mission = mission; _title = State(initialValue: mission.title) }
    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            Text(L("Renombrar misión")).font(.asterDisplay(24))
            TextField(L("Nombre"), text: $title).textFieldStyle(.aster)
            HStack { Button(L("Cancelar")) { dismiss() }.buttonStyle(.plain).foregroundStyle(Color.asterMuted).keyboardShortcut(.cancelAction); Spacer(); GlassAction(title: "Guardar", symbol: "checkmark", prominent: true) { store.renameMission(mission.id, title: title); dismiss() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(26).frame(width: 460).background(AmbientBackdrop(tint: Color.asterAccent, vibrant: false))
    }
}

struct WorkspaceEmpty: View {
    var symbol: String
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Color.asterAccent).frame(width: 58, height: 58)
                .background(Color.asterAccentSoft.opacity(0.7), in: Circle()).overlay(Circle().strokeBorder(GlassRim.gradient, lineWidth: 1))
            Text(L(title)).font(.asterDisplay(19))
            Text(L(detail)).font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4).frame(maxWidth: 400)
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity).arrive()
    }
}
