import SwiftUI

/// Home: Aster greets the user, shows what is waiting for them today and offers its modes.
struct HomeView: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var draft: String
    var focusComposer: () -> Void
    var customize: () -> Void
    @State private var week: [(day: Date, count: Int)] = []
    @State private var quickTask = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                greeting.arrive(0)
                tiles.arrive(1)
                HStack(alignment: .top, spacing: 14) {
                    recents.frame(maxWidth: .infinity)
                    today.frame(maxWidth: .infinity)
                }.arrive(2)
                HStack(alignment: .top, spacing: 14) {
                    modes.frame(maxWidth: .infinity)
                    activity.frame(width: 280)
                }.arrive(3)
                starters.arrive(4)
            }.padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 18).frame(maxWidth: 940, alignment: .leading).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
            .task(id: store.state.missions.count) { week = store.weekActivity() }
    }

    private func navigate(_ page: String) { withAnimation(AsterMotion.spring(reduceMotion)) { store.page = page } }

    // MARK: Greeting

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base = L(hour < 6 || hour >= 21 ? "Buenas noches" : hour < 14 ? "Buenos días" : "Buenas tardes")
        let name = store.settings.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? base : base + ", " + name
    }
    private var greeting: some View {
        HStack(alignment: .center, spacing: 20) {
            AvatarStage(style: store.agent.style, mood: store.mood(for: store.agent.id) == .calm ? store.previewMood : store.mood(for: store.agent.id), dimension: 128)
                .id(store.agent.id).transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            VStack(alignment: .leading, spacing: 9) {
                Text(AsterDate.today()).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.asterMuted)
                Text(greetingText).font(.asterDisplay(36)).tracking(-0.8).lineLimit(2)
                Text(L(store.busy ? "Estoy trabajando en lo que me pediste. Puedes seguir hablándome mientras." : "Cuéntame qué tienes entre manos y lo hacemos juntos."))
                    .font(.system(size: 14)).foregroundStyle(Color.asterMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.animation(AsterMotion.spring(reduceMotion), value: store.agent.id)
    }

    // MARK: Numbers

    private var tiles: some View {
        let running = store.state.missions.filter { store.isRunning($0.id) }.count
        let pending = store.state.tasks.filter { !$0.done }.count
        return HStack(spacing: 12) {
            StatTile(value: "\(running)", label: L("En marcha"), symbol: "sparkle", tint: .asterPollen, live: running > 0) { navigate(running > 0 ? "Actividad" : "Misiones") }
            StatTile(value: "\(pending)", label: L("Tareas pendientes"), symbol: "checklist", tint: .asterAccent) { navigate("Tareas") }
            StatTile(value: "\(store.unread)", label: L("Novedades"), symbol: "tray", tint: Color(red: 0.25, green: 0.6, blue: 1)) { navigate("Bandeja") }
            StatTile(value: "\(store.state.memories.count)", label: L("Recuerdos"), symbol: "brain", tint: Color(red: 0.2, green: 0.72, blue: 0.56)) { navigate("Memoria") }
        }
    }

    // MARK: Continue

    private var recents: some View {
        let items = store.recentMissions(limit: 4)
        return HomeCard(title: "Continuar", symbol: "clock.arrow.circlepath", action: items.isEmpty ? nil : ("Ver todas", { navigate("Misiones") })) {
            if items.isEmpty {
                HomeEmpty(symbol: "bubble.left.and.text.bubble.right", text: "Tus conversaciones aparecerán aquí para retomarlas donde las dejaste.")
            } else {
                VStack(spacing: 2) {
                    ForEach(items) { mission in
                        Button { store.openMission(mission.id) } label: {
                            HStack(spacing: 10) {
                                Circle().fill(store.isRunning(mission.id) ? Color.asterPollen : mission.error != nil ? Color.orange : Color.asterAccent.opacity(0.55)).frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mission.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                    Text((store.state.specialists.first { $0.id == mission.specialistID }?.mode ?? "Auto") + " · " + AsterDate.relative(mission.updated))
                                        .font(.system(size: 10.5)).foregroundStyle(Color.asterMuted).lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.asterMuted.opacity(0.7))
                            }.padding(.horizontal, 8).padding(.vertical, 7).hoverFill(10).contentShape(Rectangle())
                        }.buttonStyle(FluidButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Today

    private var today: some View {
        let open = Array(store.openTasks.prefix(4))
        return HomeCard(title: "Hoy", symbol: "sun.max", action: store.state.tasks.isEmpty ? nil : ("Todas las tareas", { navigate("Tareas") })) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(open) { task in
                    HStack(spacing: 10) {
                        Button { withAnimation(AsterMotion.spring(reduceMotion)) { store.toggleTask(task.id) } } label: {
                            Image(systemName: "circle").font(.system(size: 15, weight: .light)).foregroundStyle(Color.asterMuted).frame(width: 20, height: 20).contentShape(Rectangle())
                        }.buttonStyle(FluidButtonStyle()).accessibilityLabel(L("Marcar terminada"))
                        Text(task.title).font(.system(size: 12.5)).lineLimit(1)
                        Spacer(minLength: 6)
                        if let due = task.due {
                            Text(AsterDate.day(due)).font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(due < Calendar.current.startOfDay(for: Date()) ? Color.orange : Color.asterMuted)
                        }
                    }.padding(.horizontal, 6).padding(.vertical, 6).hoverFill(10).transition(.opacity.combined(with: .move(edge: .leading)))
                }
                if open.isEmpty { HomeEmpty(symbol: "checkmark.circle", text: "Nada pendiente. Apunta lo siguiente que quieras hacer.") }
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.asterMuted).frame(width: 20)
                    TextField(L("Añadir una tarea…"), text: $quickTask).textFieldStyle(.plain).font(.system(size: 12.5))
                        .onSubmit { withAnimation(AsterMotion.spring(reduceMotion)) { if store.addTask(quickTask) != nil { quickTask = "" } } }
                }.padding(.horizontal, 6).padding(.vertical, 7)
                    .background(Color.asterWell, in: RoundedRectangle(cornerRadius: 10, style: .continuous)).padding(.top, 6)
            }
        }
    }

    // MARK: Modes

    private var modes: some View {
        HomeCard(title: "Modos", symbol: "sparkles", action: ("Personalizar", customize)) {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 7) {
                    ForEach(Specialist.modeOrder.compactMap { id in store.state.specialists.first { $0.id == id } }) { agent in
                        let selected = store.agent.id == agent.id
                        Button { withAnimation(AsterMotion.spring(reduceMotion)) { store.select(agent.id) } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: agent.symbol).font(.system(size: 10.5, weight: .semibold))
                                Text(agent.mode).font(.asterDisplay(12.5, weight: .medium))
                            }.foregroundStyle(selected ? Color.asterOnAccent : Color.primary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(selected ? AnyShapeStyle(Color.asterAccent) : AnyShapeStyle(Color.asterWell), in: Capsule(style: .continuous))
                                .overlay(Capsule(style: .continuous).strokeBorder(selected ? Color.white.opacity(0.2) : Color.asterHairline, lineWidth: 1))
                                .shadow(color: Color.asterAccent.opacity(selected ? 0.3 : 0), radius: 7, y: 3)
                        }.buttonStyle(FluidButtonStyle(lift: 1)).accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Text(L(store.agent.detail)).font(.system(size: 12)).foregroundStyle(Color.asterMuted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity).animation(AsterMotion.quick(reduceMotion), value: store.agent.id)
            }
        }
    }

    // MARK: Week

    private var activity: some View {
        let top = max(1, week.map(\.count).max() ?? 1)
        let total = week.map(\.count).reduce(0, +)
        return HomeCard(title: "Tu semana", symbol: "chart.bar", action: nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(total)").font(.asterDisplay(26)).contentTransition(.numericText())
                    Text(L("mensajes con Aster")).font(.system(size: 11)).foregroundStyle(Color.asterMuted)
                }
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(index == week.count - 1 ? AnyShapeStyle(Color.asterAccent) : AnyShapeStyle(Color.asterAccent.opacity(item.count == 0 ? 0.12 : 0.4)))
                                .frame(height: max(4, 46 * CGFloat(item.count) / CGFloat(top)))
                            Text(AsterDate.weekday(item.day)).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.asterMuted)
                        }.frame(maxWidth: .infinity).help("\(item.count)")
                    }
                }.frame(height: 64, alignment: .bottom).animation(AsterMotion.spring(reduceMotion), value: total)
            }
        }
    }

    // MARK: Starters

    private var starters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Para empezar")).font(.asterDisplay(15)).padding(.leading, 4)
            HStack(spacing: 12) {
                starter("Pensar una idea", detail: "Una pregunta útil y enfoques concretos", symbol: "lightbulb", text: "Ayúdame a explorar una idea. Empieza con una pregunta útil y propón enfoques concretos.")
                starter("Crear algo nuevo", detail: "De una dirección a un primer resultado", symbol: "wand.and.stars", text: "Quiero crear algo original. Ayúdame a encontrar una dirección y convertirla en un primer resultado.")
                starter("Hacer avanzar un proyecto", detail: "El próximo paso con más impacto, hecho plan", symbol: "arrow.up.forward", text: "Ayúdame a elegir el próximo paso de mayor impacto para uno de mis proyectos y convertirlo en un plan concreto.")
            }
        }
    }
    private func starter(_ title: String, detail: String, symbol: String, text: String) -> some View {
        Button { draft = L(text); focusComposer() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.asterAccent).frame(width: 30, height: 30).background(Color.asterAccentSoft, in: Circle())
                Text(L(title)).font(.system(size: 13, weight: .semibold))
                Text(L(detail)).font(.system(size: 11.5)).foregroundStyle(Color.asterMuted).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading).frostedSurface(18).contentShape(Rectangle())
        }.buttonStyle(FluidButtonStyle(lift: 2))
    }
}

/// A number about the user's day that opens where it lives.
private struct StatTile: View {
    var value: String
    var label: String
    var symbol: String
    var tint: Color
    var live = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .symbolEffect(.pulse, isActive: live)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value).font(.asterDisplay(22)).contentTransition(.numericText()).monospacedDigit()
                    Text(label).font(.system(size: 11)).foregroundStyle(Color.asterMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity).frostedSurface(18).contentShape(Rectangle())
        }.buttonStyle(FluidButtonStyle(lift: 2)).accessibilityLabel(label + ": " + value)
    }
}

/// A titled glass card of the home page, with an optional link in its corner.
private struct HomeCard<Content: View>: View {
    var title: String
    var symbol: String
    var action: (title: String, run: () -> Void)?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.asterAccent)
                Text(L(title)).font(.asterDisplay(14.5))
                Spacer()
                if let action {
                    Button(action: action.run) { Text(L(action.title)).font(.system(size: 11, weight: .medium)) }.buttonStyle(.plain).foregroundStyle(Color.asterAccent)
                }
            }.padding(.horizontal, 4)
            content()
        }.padding(14).frame(maxWidth: .infinity, alignment: .topLeading).frostedSurface(20)
    }
}

private struct HomeEmpty: View {
    var symbol: String
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .light)).foregroundStyle(Color.asterMuted)
            Text(L(text)).font(.system(size: 11.5)).foregroundStyle(Color.asterMuted).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 6).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
    }
}
