import SwiftUI

struct ActivityWorkspaceView: View {
    @EnvironmentObject var store: AsterStore
    @State private var editing: AgentRoutine?
    private var working: [Mission] { store.state.missions.filter { store.isRunning($0.id) } }
    private var attention: [Mission] { store.state.missions.filter { ["Por recuperar", "Fallida", "Cancelación pendiente"].contains($0.status) && $0.archived != true && !store.isRunning($0.id) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Tu equipo en marcha.", subtitle: "Cada agente conserva su conversación y su trabajo.") {
                    Picker(L("Trabajos simultáneos"), selection: Binding(get: { store.parallelLimit }, set: { store.state.preferences.parallelMissions = $0; store.save() })) { ForEach(1...6, id: \.self) { Text("\($0)").tag($0) } }.frame(width: 200)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Label(L("En curso"), systemImage: "waveform.path").font(.asterDisplay(15)); Spacer(); Text("\(working.count) / \(store.parallelLimit)").font(.asterDisplay(13)).monospacedDigit().foregroundStyle(.secondary) }
                    if working.isEmpty { Text(L("El equipo está listo. Puedes hablar con varios agentes a la vez.")).font(.system(size: 12)).foregroundStyle(.secondary) }
                    ForEach(working) { mission in
                        HStack(spacing: 12) {
                            ThinkingDots().frame(width: 22)
                            VStack(alignment: .leading, spacing: 5) { Text(agentName(mission.specialistID) + " · " + mission.title).font(.system(size: 12, weight: .medium)).lineLimit(1); Text(L(store.activity(for: mission.id))).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                            Spacer(); Button(L("Abrir")) { store.openMission(mission.id) }.glassControl(); Button(L("Detener")) { store.stop(missionID: mission.id) }.glassControl()
                        }
                    }
                }.padding(20).frostedSurface(22)
                HStack { Text(L("Rutinas")).font(.asterDisplay(19)); Spacer(); GlassAction(title: "Nueva rutina", symbol: "plus", prominent: true) { editing = AgentRoutine() } }.padding(.top, 6)
                Text(L("Se ejecutan con Aster abierto y el Mac despierto. Respetan el límite diario y las horas de descanso de Conexiones. Los resultados llegan a la bandeja.")).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                if store.state.routines.isEmpty {
                    HStack(spacing: 12) {
                        template("Preparar mi día", agent: "personal", prompt: "Consulta mi calendario y recordatorios conectados. Propón tres prioridades realistas para hoy, señala conflictos y di qué información falta. No cambies mis citas.")
                        template("Estudiar conmigo", agent: "study", prompt: "Revisa nuestras tareas y trabajo reciente. Prepara un ejercicio corto de repaso con pistas y una solución explicada aparte. No inventes asignaturas o fechas que no conoces.")
                        template("Avanzar mi empresa", agent: "director", prompt: "Revisa el objetivo, las tareas y el trabajo anterior de esta empresa. Prepara un entregable nuevo y concreto que la haga avanzar. Comprueba tus supuestos y guarda los próximos pasos como tareas locales.")
                    }
                }
                ForEach(store.state.routines) { routine in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) { Text(routine.title).font(.system(size: 14, weight: .semibold)); Text(agentName(routine.specialistID) + " · " + L(routine.enabled ? "Activa" : "En pausa")).font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer(); Button(L("Editar")) { editing = routine }.glassControl(); Button(L(routine.enabled ? "Pausar" : "Activar")) { store.toggleRoutine(routine.id) }.glassControl()
                            Button(L("Ejecutar ahora")) { store.runRoutine(routine.id) }.glassControl().disabled(!store.hasCapacity || store.isRunning(routine.lastMissionID))
                        }
                        Text(routine.instruction).font(.system(size: 11)).lineLimit(3).foregroundStyle(.secondary)
                        HStack { Text(L("Próxima ejecución") + ": " + routine.nextRunLabel + " · " + routine.timeZone).font(.system(size: 10)).foregroundStyle(.secondary); Spacer() }
                        if !routine.history.isEmpty { DisclosureGroup(L("Historial")) { ForEach(routine.history, id: \.self) { id in if let item = store.state.missions.first(where: { $0.id == id }) { Button { store.openMission(id) } label: { HStack { Text(AsterDate.stamp(item.updated, date: .abbreviated, time: .shortened)); Spacer(); Text(L(item.status)) } }.buttonStyle(.plain).font(.system(size: 11)).padding(.vertical, 5) } } } }
                    }.padding(20).frostedSurface(22)
                }
                if !attention.isEmpty {
                    Text(L("Necesitan atención")).font(.system(size: 15, weight: .semibold))
                    ForEach(Array(attention.prefix(8))) { item in
                        HStack { VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1); Text(item.error ?? L(item.status)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Button(L("Abrir")) { store.openMission(item.id) }.glassControl(); if item.sessionID != nil { Button(L("Recuperar")) { store.recover(missionID: item.id) }.glassControl().disabled(!store.hasCapacity) } }
                            .padding(15).frostedSurface(17)
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden).sheet(item: $editing) { routine in RoutineEditor(routine: routine) }
    }
    private func agentName(_ id: String) -> String { store.state.specialists.first { $0.id == id }?.title ?? "Aster" }
    private func template(_ title: String, agent: String, prompt: String) -> some View {
        Button { var value = AgentRoutine(); value.title = L(title); value.instruction = L(prompt); value.specialistID = agent; editing = value } label: { VStack(alignment: .leading, spacing: 9) { Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.asterAccent).frame(width: 30, height: 30).background(Color.asterAccentSoft, in: Circle()); Text(L(title)).font(.system(size: 13, weight: .semibold)); Text(L("Personalizar")).font(.system(size: 11)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).frostedSurface(18).contentShape(Rectangle()) }.buttonStyle(FluidButtonStyle(lift: 2))
    }
}

private struct RoutineEditor: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.dismiss) var dismiss
    @State var routine: AgentRoutine
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(L("Tu rutina")).font(.asterDisplay(24))
            TextField(L("Nombre"), text: $routine.title)
            HStack { Picker(L("Compañero"), selection: $routine.specialistID) { ForEach(store.state.specialists) { Text($0.name).tag($0.id) } }; Picker(L("Espacio"), selection: $routine.companyID) { Text(L("Personal")).tag(nil as UUID?); ForEach(store.companies) { Text($0.name).tag(Optional($0.id)) } } }
            Text(L("Qué debe hacer y cómo comprobar el resultado")).font(.system(size: 12))
            TextEditor(text: $routine.instruction).font(.system(size: 13)).frame(height: 130).padding(8).background(Color.asterWell, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.asterHairline, lineWidth: 1))
            HStack { Picker(L("Frecuencia"), selection: $routine.cadence) { Text(L("Cada día")).tag("daily"); Text(L("De lunes a viernes")).tag("weekdays") }; Picker(L("Hora"), selection: $routine.hour) { ForEach(0...23, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 105); Picker(L("Minuto"), selection: $routine.minute) { ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 110) }
            TextField(L("Zona horaria"), text: $routine.timeZone)
            Toggle(L("Activar al guardar"), isOn: $routine.enabled)
            Text(L("Si el Mac estaba apagado, Aster hará una sola ejecución al volver. Si una ejecución necesita revisión, la rutina se pausa para no repetir acciones.")).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            HStack { Button(L("Cancelar")) { dismiss() }.buttonStyle(.plain).foregroundStyle(Color.asterMuted).keyboardShortcut(.cancelAction); Spacer(); Button(L("Guardar rutina")) { store.saveRoutine(routine); dismiss() }.buttonStyle(AsterButtonStyle(prominent: true)).disabled(routine.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || routine.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || TimeZone(identifier: routine.timeZone) == nil).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 540).textFieldStyle(.aster).background(AmbientBackdrop(tint: Color.asterAccent, vibrant: false))
    }
}
