import SwiftUI
import AppKit
import ServiceManagement
import CoreImage.CIFilterBuiltins

enum PortableSetup {
    static func importPreparedKey() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aster/.key-import")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Another program could plant this file; accept only a private regular file owned by this user.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), isTrustedImport(attributes) else { return }
        do {
            if !CredentialVault.contains("openai-api-key") {
                let value = try AgentAPI.keyFromFile(url.path)
                guard !value.isEmpty else { return }; try CredentialVault.save(Data(value.utf8), account: "openai-api-key")
            }
            try FileManager.default.removeItem(at: url)
        } catch { /* Keep the private migration file if Keychain is locked. */ }
    }
    static func isTrustedImport(_ attributes: [FileAttributeKey: Any], user: UInt32 = getuid()) -> Bool {
        attributes[.type] as? FileAttributeType == .typeRegular
            && (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == user
            && ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0
    }
}
/// Where Aster's intelligence comes from: the user's own OpenAI or Claude key, kept in the Keychain.
struct AIConnectionView: View {
    @EnvironmentObject var store: AsterStore
    @State private var key = ""
    @State private var saving = false
    @State private var message = ""
    private var provider: AIProvider { store.settings.usesClaude ? .anthropic : .openai }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.asterAccent).frame(width: 28, height: 28).background(Color.asterAccentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(L("Tu IA")).font(.asterDisplay(15))
                Spacer()
                Circle().fill(store.connectionReady ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(L(store.connectionStatus)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            GlassSegmented(options: [(AIProvider.anthropic, AIProvider.anthropic.name), (AIProvider.openai, AIProvider.openai.name)], selection: Binding(get: { provider }, set: { store.choose($0); message = ""; key = "" })).frame(maxWidth: 260)
            Text(LF("Aster piensa con tu propia cuenta de %@. La clave queda en el Llavero de este Mac y solo se envía a %@.", provider.name, provider == .anthropic ? "Anthropic" : "OpenAI")).font(.caption).foregroundStyle(.secondary)
            HStack {
                SecureField(provider.hasKey ? L("Sustituir la clave guardada") : LF("Clave de API de %@", provider.name), text: $key).textFieldStyle(.aster).onSubmit { connect(key) }
                Button(L(saving ? "Comprobando…" : "Conectar")) { connect(key) }.glassControl(prominent: true).disabled(saving || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if store.connectionReady || !store.availableModels.isEmpty { ModelPicker() }
            HStack {
                if provider == .openai {
                    Button(L("Importar mi configuración")) {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true; panel.message = L("Selecciona tu archivo de configuración de OpenAI. Solo se importa la clave al Llavero.")
                        if panel.runModal() == .OK, let url = panel.url { do { connect(try AgentAPI.keyFromFile(url.path)) } catch { message = error.localizedDescription } }
                    }.glassControl().disabled(saving)
                }
                Button(L("Comprobar conexión"), action: store.refreshConnection).glassControl().disabled(store.checkingConnection || saving || !provider.hasKey)
                Spacer(); Link(L("Obtener mi clave"), destination: provider.keysURL)
            }.font(.caption)
            if !message.isEmpty { Text(L(message)).font(.caption).textSelection(.enabled) }
            Text(L(provider == .anthropic
                   ? "Con Claude, el chat, las misiones, el control del Mac y las explicaciones de pantalla usan tu saldo de Anthropic. Las voces naturales son de OpenAI; sin esa clave, Aster habla con las voces de macOS."
                   : "Las respuestas, las misiones y la voz natural usan el saldo de tu cuenta de OpenAI.")).font(.caption2).foregroundStyle(.secondary)
            Text(L("Cada Mac utiliza su propia clave. No se incluye en el instalador ni se envía al iPhone.")).font(.caption2).foregroundStyle(.secondary)
        }.padding(20).frostedSurface(20)
    }
    private func connect(_ candidate: String) {
        guard !saving else { return }; saving = true; message = ""
        Task {
            do { try await store.connect(provider, key: candidate); key = ""; message = "Conexión guardada en el Llavero." }
            catch { message = error.localizedDescription }
            saving = false
        }
    }
}

/// The model Aster thinks with, chosen from those the user's key can use.
struct ModelPicker: View {
    @EnvironmentObject var store: AsterStore
    var body: some View {
        let settings = store.settings
        let options = AIProvider.chatModels(store.availableModels, provider: settings.usesClaude ? .anthropic : .openai, keeping: settings.workModel)
        Picker(L("Modelo"), selection: Binding(get: { settings.workModel }, set: { store.chooseModel($0) })) {
            ForEach(options, id: \.self) { Text(AIProvider.label($0)).tag($0) }
        }
    }
}

struct RemoteSettingsView: View {
    @ObservedObject var remote: MacRemoteBridge
    @State private var relay = ""
    @State private var reveal = false
    @State private var confirmRevoke = false
    @State private var loginMessage = ""
    private var qr: NSImage? {
        guard let code = remote.pairing?.code else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(code.utf8); filter.correctionLevel = "M"
        guard let result = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 5, y: 5)), let cg = CIContext().createCGImage(result, from: result.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.and.arrow.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.asterAccent).frame(width: 28, height: 28).background(Color.asterAccentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("Tu Mac, desde tu iPhone").font(.asterDisplay(15)); Spacer(); Circle().fill(remote.connection.peerOnline ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7); Text(remote.connection.status).font(.caption).foregroundStyle(.secondary) }
            Text("Habla con tus agentes, sigue sus tareas y abre la pantalla del Mac estés donde estés. El Mac necesita Internet, Aster abierto y la sesión iniciada.").font(.caption).foregroundStyle(.secondary)
            if remote.pairing == nil {
                TextField("Servidor de enlace · wss://…", text: $relay).textFieldStyle(.aster)
                HStack { Button("Crear enlace privado") { remote.createPairing(relay: relay); reveal = remote.pairing != nil }.glassControl(prominent: true).disabled(relay.isEmpty); Text("La dirección la proporciona quien despliega Aster Relay.").font(.caption2).foregroundStyle(.secondary) }
            } else {
                Toggle("Disponible para mi iPhone", isOn: Binding(get: { remote.enabled }, set: { $0 ? remote.start() : remote.stop() })).toggleStyle(.switch)
                Toggle("Permitir controlar este Mac", isOn: $remote.allowControl).toggleStyle(.switch)
                Text("Permite que tu iPhone inicie tareas en pantalla y use el control manual. Puedes desactivarlo aquí en cualquier momento.").font(.caption2).foregroundStyle(.secondary)
                if remote.sharing { Label("Tu iPhone está viendo esta pantalla", systemImage: "rectangle.inset.filled.and.person.filled").font(.caption).foregroundStyle(.green) }
                HStack { Button(reveal ? "Ocultar código" : "Enlazar mi iPhone") { withAnimation(.easeInOut(duration: 0.2)) { reveal.toggle() } }.glassControl(); Button("Desvincular iPhone", role: .destructive) { confirmRevoke = true }.glassControl() }
                if reveal, let qr {
                    HStack(alignment: .center, spacing: 20) {
                        Image(nsImage: qr).interpolation(.none).resizable().scaledToFit().frame(width: 205, height: 205).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 12) {
                            Text("1. Abre Aster Remote en tu iPhone.\n2. Pulsa «Escanear el código».\n3. Apunta a este código para enlazar.").font(.callout).lineSpacing(7)
                            Button("Copiar enlace") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(remote.pairing!.code, forType: .string) }
                            Text("Este código da acceso a tu Aster. Guárdalo para ti. Desvincular lo invalida.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            if !remote.error.isEmpty { Text(remote.error).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack {
                Button("Abrir Aster al iniciar sesión") {
                    do { try SMAppService.mainApp.register(); loginMessage = "Inicio de sesión configurado. Revisa Ítems de inicio si macOS solicita confirmación." }
                    catch { loginMessage = error.localizedDescription }
                }
                Button("Ajustes de inicio") { SMAppService.openSystemSettingsLoginItems() }
            }.glassControl()
            if !loginMessage.isEmpty { Text(loginMessage).font(.caption2).foregroundStyle(.secondary) }
            Text("Mientras el acceso remoto está activo, Aster evita el reposo por inactividad. Cerrar la tapa, apagar el Mac o perder Internet interrumpe la conexión. Bloquearlo detiene la pantalla y el control.").font(.caption2).foregroundStyle(.secondary)
        }.padding(20).frostedSurface(20)
        .confirmationDialog("¿Desvincular el iPhone? Tendrás que escanear un código nuevo para volver a conectarlo.", isPresented: $confirmRevoke) { Button("Desvincular", role: .destructive) { remote.revoke(); reveal = false } }
    }
}
