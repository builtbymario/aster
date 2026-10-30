import SwiftUI
import AppKit

/// Projects: a list on the left, and the open project with its team and its own conversation.
struct ProjectsView: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var creating: ProjectTemplate?
    @State private var editing: Company?
    @State private var draft = ""
    @FocusState private var composing: Bool
    private var project: Company? { store.companies.first { $0.id == store.selectedProject } ?? store.companies.first }

    var body: some View {
        HStack(spacing: 0) {
            if let project {
                list
                Rectangle().fill(Color.asterHairline).frame(width: 1)
                detail(project).id(project.id)
            } else { start }
        }
        .sheet(item: $creating) { template in
            ProjectForm(template: template) { name, goal, notes, kind, modes in
                if let created = store.createProject(name: name, goal: goal, notes: notes, kind: kind, modes: modes) { store.selectedProject = created.id; composing = true }
            }
        }
        .sheet(item: $editing) { project in
            ProjectForm(original: project) { name, goal, notes, kind, modes in
                var edited = project; edited.name = name; edited.goal = goal; edited.notes = notes; edited.kind = kind; edited.modes = modes; store.updateCompany(edited)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MonoLabel(L("Proyectos"))
                Spacer()
                Menu {
                    ForEach(ProjectTemplate.all) { template in Button { creating = template } label: { Label(L(template.name), systemImage: template.symbol) } }
                } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("Nuevo proyecto")).accessibilityLabel(L("Nuevo proyecto"))
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.companies) { item in
                        let selected = item.id == project?.id
                        Button { withAnimation(AsterMotion.quick(reduceMotion)) { store.selectedProject = item.id } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.template.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(selected ? Color.asterAccent : Color.asterMuted).frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                                    Text(L(item.template.name)).font(.system(size: 10)).foregroundStyle(Color.asterMuted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if store.isRunning(store.projectChat(item.id)?.id) { ThinkingDots().scaleEffect(0.7) }
                            }.padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected ? Color.asterAccentSoft : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous)).contentShape(Rectangle())
                        }.buttonStyle(.plain).contextMenu {
                            Button(L("Editar proyecto")) { editing = item }
                            Button(L("Archivar proyecto")) { store.archiveCompany(item.id) }
                        }
                    }
                }
            }.scrollIndicators(.never)
            if store.state.companies.contains(where: { $0.archived == true }) {
                DisclosureGroup(L("Archivados")) {
                    ForEach(store.state.companies.filter { $0.archived == true }) { item in
                        HStack { Text(item.name).lineLimit(1); Spacer(); Button(L("Restaurar")) { store.archiveCompany(item.id, archived: false) }.buttonStyle(.plain).foregroundStyle(Color.asterAccent) }.font(.system(size: 11)).padding(.vertical, 3)
                    }
                }.font(.system(size: 11)).foregroundStyle(Color.asterMuted)
            }
        }.padding(14).frame(width: 220)
    }

    /// No project yet: one card per template.
    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Un espacio para cada cosa que te importa.")).font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                    Text(L("Cada proyecto tiene su propio chat, su equipo de agentes, sus tareas y su memoria. Elige por dónde empezar.")).font(.system(size: 13)).foregroundStyle(Color.asterMuted)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(ProjectTemplate.all) { template in
                        Button { creating = template } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: template.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.asterAccent).frame(width: 34, height: 34).background(Color.asterAccentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(L(template.name)).font(.system(size: 14, weight: .semibold))
                                Text(L(template.detail)).font(.system(size: 11)).foregroundStyle(Color.asterMuted).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Text(template.modes.compactMap { id in store.state.specialists.first { $0.id == id }?.mode }.joined(separator: " · "))
                                    .font(.asterMono(9)).foregroundStyle(Color.asterAccentText).lineLimit(2)
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading).frostedSurface(16).contentShape(Rectangle())
                        }.buttonStyle(FluidButtonStyle(lift: 1))
                    }
                }
            }.padding(30)
        }
    }

    private func detail(_ project: Company) -> some View {
        let chat = store.projectChat(project.id)
        let working = store.isRunning(chat?.id)
        let messages = (chat?.messages ?? []).filter { !$0.text.isEmpty }
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: project.template.symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Color.asterAccent).frame(width: 40, height: 40).background(Color.asterAccentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.system(size: 22, weight: .semibold)).tracking(-0.5).lineLimit(1)
                        Text(project.goal).font(.system(size: 12)).foregroundStyle(Color.asterMuted).lineLimit(2).textSelection(.enabled)
                    }
                    Spacer()
                    GlassIconButton(symbol: "square.and.pencil", title: "Nueva conversación") { store.newProjectConversation(project.id); draft = "" }.disabled(working || chat == nil)
                    GlassIconButton(symbol: "slider.horizontal.3", title: "Editar proyecto") { editing = project }
                }
                HStack(spacing: 14) {
                    MonoLabel(L("Equipo"), size: 9)
                    team(project.team, size: 10)
                    Spacer()
                    let missions = store.state.missions.filter { $0.companyID == project.id && $0.id != chat?.id }.count
                    let tasks = store.state.tasks.filter { $0.companyID == project.id && !$0.done }.count
                    Button { store.projectFilter = project.id; store.page = "Misiones" } label: { Label(LF("%d misiones", missions), systemImage: "square.stack.3d.up") }.buttonStyle(.plain).disabled(missions == 0)
                    Button { store.page = "Tareas" } label: { Label(LF("%d tareas pendientes", tasks), systemImage: "checklist") }.buttonStyle(.plain).disabled(tasks == 0)
                }.font(.system(size: 10)).foregroundStyle(Color.asterMuted)
            }.padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 16)
            Rectangle().fill(Color.asterHairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if messages.isEmpty && !working { welcome(project) }
                        ForEach(messages) { message in
                            if message.role == "user" {
                                Text(message.text).font(.system(size: 13)).textSelection(.enabled).padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.asterRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    MonoLabel(modeLabel(chat, message: message), color: Color.asterAccentText, size: 9)
                                    RichMessage(text: AsterMarkup.display(message.text)).equatable().textSelection(.enabled)
                                }
                            }
                        }
                        if working {
                            HStack(spacing: 9) { ThinkingDots(); Text(L(store.activity(for: chat?.id).isEmpty ? "Pensando" : store.activity(for: chat?.id))).font(.system(size: 11)).foregroundStyle(Color.asterMuted) }
                        } else if let steps = chat?.suggestions, !steps.isEmpty {
                            NextSteps(steps: steps, enabled: store.hasCapacity) { step in store.sendProject(step, projectID: project.id) }.frame(maxWidth: 560, alignment: .leading)
                        }
                        if !working, let learned = chat?.learned, let id = chat?.id { LearnedNote(facts: learned) { store.forgetLearned($0, in: id) } }
                        if let error = chat?.error, !error.isEmpty { Label(L(error), systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange) }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(.horizontal, 26).padding(.vertical, 20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: chat?.messages.last?.text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            composer(project, chat: chat, working: working)
        }
    }

    /// Before the first message: what the team can do, as one tap each.
    private func welcome(_ project: Company) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("¿Por dónde empezamos?")).font(.system(size: 16, weight: .semibold))
            Text(L("Aster trabaja aquí solo con el equipo de este proyecto y recuerda su objetivo, sus tareas y lo que ya habéis hecho.")).font(.system(size: 12)).foregroundStyle(Color.asterMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                ForEach(project.template.actions, id: \.title) { action in
                    Button { if store.startProjectAction(action, projectID: project.id) { draft = "" } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(action.kickoff ? Color.asterOnAccent : Color.asterAccent).frame(width: 28, height: 28)
                                .background(action.kickoff ? Color.asterAccent : Color.asterAccentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(L(action.title)).font(.system(size: 12, weight: .medium))
                            Spacer(minLength: 0)
                        }.padding(10).frame(maxWidth: .infinity).frostedSurface(12).contentShape(Rectangle())
                    }.buttonStyle(FluidButtonStyle(lift: 1)).disabled(!store.hasCapacity)
                }
            }
        }
    }

    private func composer(_ project: Company, chat: Mission?, working: Bool) -> some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 10) {
            TextField(LF("Escribe sobre %@…", project.name), text: $draft, axis: .vertical).lineLimit(1...5).textFieldStyle(.plain).font(.system(size: 13)).focused($composing)
                .onSubmit { send(project) }
            DictationButton(listener: store.listener) { dictate(project) }
            Button { if working { store.stop(missionID: chat?.id) } else { send(project) } } label: {
                Image(systemName: working ? "stop.fill" : "arrow.up").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
                    .foregroundStyle(Color.asterOnAccent).background(Color.asterAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }.buttonStyle(FluidButtonStyle()).disabled(!working && (empty || !store.hasCapacity)).accessibilityLabel(L(working ? "Detener" : "Enviar"))
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frostedSurface(16)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(composing ? Color.asterAccent.opacity(0.6) : .clear, lineWidth: 1))
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private func send(_ project: Company) {
        if store.sendProject(draft, projectID: project.id) { draft = "" }
    }
    private func dictate(_ project: Company) {
        if store.listener.active { store.listener.finish(); return }
        let typed = draft, prefix = typed.isEmpty || typed.hasSuffix(" ") ? typed : typed + " "
        store.startDictation(onUpdate: { draft = prefix + $0 }, onFinish: { heard in
            draft = prefix + heard
            if store.sendProject(draft, projectID: project.id, spoken: true) { draft = "" }
        })
    }
    private func modeLabel(_ chat: Mission?, message: Message) -> String {
        guard message.id == chat?.messages.last(where: { $0.role == "assistant" })?.id, let mode = chat?.activeMode, mode != "director",
              let chosen = store.state.specialists.first(where: { $0.id == mode }) else { return "Aster" }
        return "Aster · " + chosen.mode
    }
    /// The team as labeled chips, or as symbols when the names do not fit.
    private func team(_ modes: [String], size: CGFloat) -> some View {
        let members = modes.compactMap { id in store.state.specialists.first { $0.id == id } }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                ForEach(members) { mode in
                    Label(mode.mode, systemImage: mode.symbol).font(.system(size: size, weight: .medium)).labelStyle(TightLabelStyle()).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Color.asterRaised, in: Capsule()).foregroundStyle(.primary)
                }
            }
            HStack(spacing: 4) {
                ForEach(members) { mode in
                    Image(systemName: mode.symbol).font(.system(size: size)).frame(width: 20, height: 20).background(Color.asterRaised, in: Circle()).help(mode.mode).accessibilityLabel(mode.mode)
                }
            }
        }
    }
}

/// Creating or editing a project: its kind, name, goal, context and team.
struct ProjectForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AsterStore
    @State private var kind: String
    @State private var name: String
    @State private var goal: String
    @State private var notes: String
    @State private var modes: [String]
    private let editing: Bool
    let save: (String, String, String, String, [String]) -> Void
    init(template: ProjectTemplate? = nil, original: Company? = nil, save: @escaping (String, String, String, String, [String]) -> Void) {
        let template = original?.template ?? template ?? ProjectTemplate.all[0]
        _kind = State(initialValue: template.id); _name = State(initialValue: original?.name ?? ""); _goal = State(initialValue: original?.goal ?? "")
        _notes = State(initialValue: original?.notes ?? ""); _modes = State(initialValue: original?.team ?? template.modes)
        editing = original != nil; self.save = save
    }
    private var template: ProjectTemplate { ProjectTemplate.all.first { $0.id == kind } ?? ProjectTemplate.all[0] }
    private var ready: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !modes.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L(editing ? "Editar proyecto" : "Nuevo proyecto")).font(.system(size: 22, weight: .semibold)).tracking(-0.5)
                Spacer(); GlassIconButton(symbol: "xmark", title: "Cerrar") { dismiss() }
            }
            Picker(L("Tipo"), selection: Binding(get: { kind }, set: { value in
                // A new kind brings its team unless the user already chose one by hand.
                if modes == template.modes { modes = ProjectTemplate.all.first { $0.id == value }?.modes ?? modes }
                kind = value
            })) { ForEach(ProjectTemplate.all) { Label(L($0.name), systemImage: $0.symbol).tag($0.id) } }
            VStack(alignment: .leading, spacing: 8) {
                field("Nombre") { TextField(L(template.id == "study" ? "Ingeniería Industrial" : "Ponle un nombre"), text: $name).textFieldStyle(.roundedBorder) }
                field("¿Qué quieres conseguir?") { TextField(L(template.goalHint), text: $goal, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder) }
                field("Contexto (opcional)") { TextField(L("Lo que Aster debería saber: audiencia, recursos, fechas, nivel…"), text: $notes, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Equipo")).font(.system(size: 12, weight: .medium))
                Text(L("Los agentes que trabajan en este proyecto. Auto elige entre ellos en cada mensaje.")).font(.system(size: 11)).foregroundStyle(Color.asterMuted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(Specialist.modeOrder.filter { $0 != "director" }, id: \.self) { id in
                        if let mode = store.state.specialists.first(where: { $0.id == id }) {
                            let on = modes.contains(id)
                            Button { if on { modes.removeAll { $0 == id } } else { modes.append(id) } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: on ? "checkmark.circle.fill" : mode.symbol).font(.system(size: 10)).foregroundStyle(on ? Color.asterAccent : Color.asterMuted)
                                    Text(mode.mode).font(.system(size: 11, weight: .medium)); Spacer(minLength: 0)
                                }.padding(.horizontal, 9).padding(.vertical, 7)
                                    .background(on ? Color.asterAccentSoft : Color.asterSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Color.asterAccent.opacity(0.5) : Color.asterHairline, lineWidth: 0.5))
                            }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            HStack {
                Button(L("Cancelar")) { dismiss() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.asterMuted)
                Spacer()
                Button(L(editing ? "Guardar" : "Crear proyecto")) { save(name, goal, notes, kind, Specialist.modeOrder.filter(modes.contains)); dismiss() }
                    .buttonStyle(AsterButtonStyle(prominent: true, large: true)).disabled(!ready).keyboardShortcut(.defaultAction)
            }
        }.font(.system(size: 12)).padding(24).frame(width: 500).background(Color.asterCanvas)
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(L(title)).font(.system(size: 12, weight: .medium)); content() }
    }
}
