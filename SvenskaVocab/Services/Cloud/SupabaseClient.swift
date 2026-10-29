import Foundation
import Security

/// Project URL and public anon key, read from Config/Supabase.plist (git-ignored; see supabase/Supabase.example.plist).
/// Without it the app works exactly as before, offline only.
struct SupabaseConfig {
    let url: URL
    let anonKey: String

    static let current: SupabaseConfig? = {
        guard let file = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: file) as? [String: Any],
              let urlString = (dict["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespaces),
              let url = URL(string: urlString), url.host() != nil, !urlString.contains("YOUR-PROJECT"),
              let key = (dict["SUPABASE_ANON_KEY"] as? String)?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty, !key.hasPrefix("YOUR-")
        else { return nil }
        return SupabaseConfig(url: url, anonKey: key)
    }()
}

/// A signed-in Supabase Auth session.
struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
    var email: String
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case notSignedIn
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: L("Cloud sync is not set up in this build.")
        case .notSignedIn: L("You are signed out.")
        case let .server(_, message): message
        }
    }

    var status: Int? {
        if case let .server(status, _) = self { status } else { nil }
    }
}

/// Minimal client for Supabase Auth (GoTrue) and the REST API (PostgREST) over URLSession.
struct SupabaseClient {
    let config: SupabaseConfig

    // MARK: Auth

    /// Creates an account. Returns nil when the project requires the email address to be confirmed first.
    func signUp(email: String, password: String) async throws -> AuthSession? {
        let json = try await send("auth/v1/signup", body: ["email": email, "password": password])
        return Self.session(from: json)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let json = try await send("auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
                                  body: ["email": email, "password": password])
        guard let session = Self.session(from: json) else { throw Self.unexpected }
        return session
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        let json = try await send("auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                  body: ["refresh_token": session.refreshToken])
        guard let fresh = Self.session(from: json) else { throw Self.unexpected }
        return fresh
    }

    func signOut(_ session: AuthSession) async {
        _ = try? await send("auth/v1/logout", body: [:], token: session.accessToken)
    }

    private static var unexpected: SupabaseError {
        .server(status: 0, message: L("Unexpected response from the server."))
    }

    private static func session(from json: Any) -> AuthSession? {
        guard let dict = json as? [String: Any],
              let access = dict["access_token"] as? String,
              let refresh = dict["refresh_token"] as? String,
              let user = dict["user"] as? [String: Any],
              let id = user["id"] as? String
        else { return nil }
        let expiresIn = (dict["expires_in"] as? Double) ?? 3600
        return AuthSession(accessToken: access, refreshToken: refresh,
                           expiresAt: .now.addingTimeInterval(expiresIn),
                           userId: id, email: user["email"] as? String ?? "")
    }

    // MARK: REST

    /// GET rows of a table. `query` holds PostgREST filters, e.g. `updated_at=gt.…`.
    func select(_ table: String, query: [URLQueryItem], token: String) async throws -> Data {
        try await request("rest/v1/\(table)", method: "GET", query: query, body: nil, token: token).0
    }

    /// Inserts rows, updating (or, with `ignoreDuplicates`, keeping) rows whose primary key already exists.
    func upsert(_ table: String, rows: Data, onConflict: String, ignoreDuplicates: Bool = false, token: String) async throws {
        let resolution = ignoreDuplicates ? "ignore-duplicates" : "merge-duplicates"
        _ = try await request("rest/v1/\(table)", method: "POST",
                              query: [URLQueryItem(name: "on_conflict", value: onConflict)], body: rows, token: token,
                              headers: ["Prefer": "resolution=\(resolution),return=minimal"])
    }

    /// Calls a Postgres function.
    func rpc(_ function: String, token: String) async throws {
        _ = try await request("rest/v1/rpc/\(function)", method: "POST", query: [], body: Data("{}".utf8), token: token)
    }

    /// Calls an Edge Function and returns its answer.
    func invoke(_ function: String, body: Data, token: String) async throws -> Data {
        try await request("functions/v1/\(function)", method: "POST", query: [], body: body, token: token).0
    }

    // MARK: Transport

    private func send(_ path: String, query: [URLQueryItem] = [], body: [String: String], token: String? = nil) async throws -> Any {
        let data = try JSONSerialization.data(withJSONObject: body)
        let (response, _) = try await request(path, method: "POST", query: query, body: data, token: token)
        return (try? JSONSerialization.jsonObject(with: response)) ?? [:]
    }

    private func request(_ path: String, method: String, query: [URLQueryItem], body: Data?, token: String?,
                         headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var url = config.url.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard let http, (200..<300).contains(status) else {
            throw SupabaseError.server(status: status, message: Self.message(from: data, status: status))
        }
        return (data, http)
    }

    private static func message(from data: Data, status: Int) -> String {
        let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        for key in ["error_description", "msg", "message", "error"] {
            if let text = dict[key] as? String, !text.isEmpty { return text }
        }
        return L("Server error (%lld).", status)
    }
}

/// Stores the auth session in the Keychain.
enum SessionStore {
    private static let service = "SvenskaVocab.supabase"
    private static let account = "session"

    static func load() -> AuthSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func save(_ session: AuthSession?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// The signed-in account. Hands out fresh access tokens, refreshing them when they are about to expire.
@MainActor
final class AccountService: ObservableObject {
    @Published private(set) var session: AuthSession?

    let client: SupabaseClient?
    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { session != nil }

    private var refreshTask: Task<AuthSession, Error>?

    init(config: SupabaseConfig? = .current) {
        client = config.map(SupabaseClient.init)
        session = client == nil ? nil : SessionStore.load()
    }

    /// Returns true when signed in straight away, false when the email address must be confirmed first.
    func signUp(email: String, password: String) async throws -> Bool {
        guard let client else { throw SupabaseError.notConfigured }
        guard let session = try await client.signUp(email: email, password: password) else { return false }
        store(session)
        return true
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw SupabaseError.notConfigured }
        store(try await client.signIn(email: email, password: password))
    }

    func signOut() async {
        if let client, let session { await client.signOut(session) }
        store(nil)
    }

    /// Permanently deletes the account and everything stored in the cloud. Local data stays on the device.
    func deleteAccount() async throws {
        guard let client else { throw SupabaseError.notConfigured }
        try await client.rpc("delete_account", token: try await accessToken())
        store(nil)
    }

    /// A valid access token, refreshed if it expires within a minute.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let client else { throw SupabaseError.notConfigured }
        guard let current = session else { throw SupabaseError.notSignedIn }
        if !forceRefresh, current.expiresAt > .now.addingTimeInterval(60) { return current.accessToken }

        if refreshTask == nil {
            refreshTask = Task { try await client.refresh(current) }
        }
        defer { refreshTask = nil }
        do {
            let fresh = try await refreshTask!.value
            store(fresh)
            return fresh.accessToken
        } catch let error as SupabaseError where (400..<500).contains(error.status ?? 0) {
            // The refresh token was revoked or has expired: the learner has to sign in again.
            store(nil)
            throw SupabaseError.notSignedIn
        }
    }

    /// Calls one of the project's Edge Functions as the signed-in learner; retries once with a fresh token on 401.
    func invoke(_ function: String, body: Data) async throws -> Data {
        guard let client else { throw SupabaseError.notConfigured }
        do {
            return try await client.invoke(function, body: body, token: try await accessToken())
        } catch let error as SupabaseError where error.status == 401 {
            return try await client.invoke(function, body: body, token: try await accessToken(forceRefresh: true))
        }
    }

    private func store(_ session: AuthSession?) {
        self.session = session
        SessionStore.save(session)
    }
}
