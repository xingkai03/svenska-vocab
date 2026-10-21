import SwiftUI

/// The Account row at the top of Settings.
struct AccountSection: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: SyncService

    var body: some View {
        Section {
            if !account.isConfigured {
                Label("Cloud sync is not set up in this build", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            } else if let session = account.session {
                NavigationLink {
                    AccountView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(session.email, systemImage: "person.crop.circle.fill")
                        SyncStatusText().font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                NavigationLink {
                    SignInView()
                } label: {
                    Label("Sign in or create account", systemImage: "person.crop.circle.badge.plus")
                }
            }
        } header: {
            Text("Account")
        } footer: {
            if account.isConfigured, !account.isSignedIn {
                Text("Back up your words, review progress, check-ins, settings and imported lists, and use them on all your devices. Everything keeps working offline.")
            }
        }
    }
}

struct SyncStatusText: View {
    @EnvironmentObject private var sync: SyncService

    var body: some View {
        if sync.isSyncing {
            Text("Syncing…")
        } else if let error = sync.lastError {
            Text(error).foregroundStyle(.red)
        } else if let date = sync.lastSyncedAt {
            Text("Synced \(date.formatted(.relative(presentation: .named)))")
        } else {
            Text("Not synced yet")
        }
    }
}

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: SyncService
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Email", value: account.session?.email ?? "")
                LabeledContent("Status") { SyncStatusText() }
                Button {
                    Task { await sync.sync() }
                } label: {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(sync.isSyncing)
            } footer: {
                Text("Syncs automatically when you open and leave the app, and every few minutes while you use it.")
            }

            Section {
                Button("Sign out") {
                    Task { await signOut() }
                }
            } footer: {
                Text("Your words stay on this device after you sign out.")
            }

            Section {
                Button("Delete account", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Permanently deletes your account and everything stored in the cloud. Data on this device is kept.")
            }
        }
        .navigationTitle("Account")
        .confirmationDialog("Delete your account and all cloud data?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
        }
        .alert("Account", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func signOut() async {
        await sync.sync()
        let userId = account.session?.userId
        await account.signOut()
        if let userId { sync.reset(userId: userId) }
        dismiss()
    }

    private func deleteAccount() async {
        let userId = account.session?.userId
        do {
            try await account.deleteAccount()
            if let userId { sync.reset(userId: userId) }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SignInView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Create account"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: SyncService
    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !isWorking
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
            } footer: {
                if mode == .signUp {
                    Text("At least 6 characters. The words already on this device are added to your new account.")
                } else {
                    Text("Words on this device are merged with the ones in your account.")
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        Spacer()
                        if isWorking { ProgressView() }
                    }
                }
                .disabled(!canSubmit)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            if let infoMessage {
                Section { Text(infoMessage) }
            }
        }
        .navigationTitle(mode.rawValue)
        .onChange(of: mode) { errorMessage = nil }
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            switch mode {
            case .signIn:
                try await account.signIn(email: email, password: password)
            case .signUp:
                guard try await account.signUp(email: email, password: password) else {
                    infoMessage = "Check your inbox for a confirmation email from Supabase, open the link, then come back and sign in."
                    mode = .signIn
                    return
                }
            }
            dismiss()
            await sync.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
