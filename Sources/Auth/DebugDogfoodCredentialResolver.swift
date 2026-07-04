#if DEBUG
import Foundation

/// Resolves dogfood Stack credentials for the macOS DEBUG auto-sign-in path.
///
/// A tagged `mosaic DEV` build is a separate bundle (separate keychain), so it
/// starts signed out and shows the sign-in window. iOS already auto-signs-in on
/// DEBUG launch by injecting `MOSAIC_UITEST_STACK_EMAIL` / `MOSAIC_UITEST_STACK_PASSWORD`
/// into the app's environment (SIMCTL / devicectl), which the existing
/// `MosaicAuthAutoLoginCredentials` path reads. The macOS app needs the same
/// behavior, but a `mosaic DEV` opened from Finder or the MOSAIC Tag Opener does
/// **not** inherit a shell's environment, so an env-only approach never fires on
/// those launches. This resolver adds a file-read fallback so the creds are
/// found regardless of how the app was launched.
///
/// Resolution order is **dogfood account first, then agent account**, so the
/// dog Mac comes up as the human dogfood account (`lawrence@emergent.inc`) even
/// when an agent's `MOSAIC_UITEST_*` creds are also present (the iOS dogfood flow
/// commonly leaves those in the environment / `~/.secrets`). Within each
/// account, env wins over `~/.secrets/mosaicterm-dev.env`, which wins over
/// `~/.secrets/mosaic.env`:
///
///   1. env `MOSAIC_DOGFOOD_STACK_EMAIL` / `MOSAIC_DOGFOOD_STACK_PASSWORD`
///   2. file `~/.secrets/mosaicterm-dev.env` dogfood keys
///   3. file `~/.secrets/mosaic.env` dogfood keys
///   4. env `MOSAIC_UITEST_STACK_EMAIL` / `MOSAIC_UITEST_STACK_PASSWORD`
///   5. file `~/.secrets/mosaicterm-dev.env` uitest keys
///   6. file `~/.secrets/mosaic.env` uitest keys
///
/// The resolved pair is merged into the launch environment dict as the existing
/// `MOSAIC_UITEST_STACK_*` keys, so the already-tested `MosaicAuthAutoLoginCredentials`
/// + `AuthLaunchOptions.shouldStartAutoLogin` gate (`hasCredentials && !hasStoredTokens`)
/// fires unchanged. This type holds no autoLogin logic of its own.
///
/// The whole type is compiled out of release builds (`#if DEBUG`), so it can
/// never run in production. It takes its environment and a file-reader seam via
/// `init`, so tests drive every precedence branch without touching the real
/// filesystem or `~/.secrets`.
struct DebugDogfoodCredentialResolver {
    /// A resolved email/password pair.
    ///
    /// Kept nested in this file under the file-organization carve-out for small,
    /// closely-bound helpers: two stored fields plus synthesized `Equatable`, no
    /// meaningful body, used only by this resolver and its tests.
    struct ResolvedCredentials: Equatable {
        let email: String
        let password: String
    }

    /// The launch environment to read env-var credentials from.
    private let environment: [String: String]
    /// Ordered secret-file candidate paths (highest precedence first), already
    /// expanded to absolute paths by the caller.
    private let secretFilePaths: [String]
    /// Reads the contents of a secret file at the given path, or `nil` when the
    /// file is absent/unreadable. Injected so tests never read real files.
    private let readFile: (String) -> String?

    /// Creates a resolver.
    ///
    /// - Parameters:
    ///   - environment: The launch environment (env-var credential source).
    ///   - secretFilePaths: Ordered secret-file candidates, highest precedence
    ///     first. Defaults to `~/.secrets/mosaicterm-dev.env` then
    ///     `~/.secrets/mosaic.env`, resolved from the environment's `HOME`.
    ///   - readFile: Reads a file's UTF-8 contents, or `nil` if unreadable.
    ///     Defaults to a `FileManager`-free `String(contentsOfFile:)` read.
    init(
        environment: [String: String],
        secretFilePaths: [String]? = nil,
        readFile: @escaping (String) -> String? = { path in
            try? String(contentsOfFile: path, encoding: .utf8)
        }
    ) {
        self.environment = environment
        self.secretFilePaths = secretFilePaths ?? Self.defaultSecretFilePaths(environment: environment)
        self.readFile = readFile
    }

    /// The default ordered secret-file candidates, resolved against `HOME`.
    /// `mosaicterm-dev.env` (mosaic-terminal-specific Stack creds) is preferred over
    /// the broader `mosaic.env`.
    private static func defaultSecretFilePaths(environment: [String: String]) -> [String] {
        guard let home = environment["HOME"], !home.isEmpty else { return [] }
        let base = home as NSString
        return [
            base.appendingPathComponent(".secrets/mosaicterm-dev.env"),
            base.appendingPathComponent(".secrets/mosaic.env"),
        ]
    }

    /// The credential-key pair an account uses in env vars and secret files.
    ///
    /// Kept nested under the file-organization carve-out for small, closely-bound
    /// helpers: a private two-case enum with two computed key strings, used only
    /// inside this resolver.
    private enum Account {
        case dogfood
        case uitest

        var emailKey: String {
            switch self {
            case .dogfood: return "MOSAIC_DOGFOOD_STACK_EMAIL"
            case .uitest: return "MOSAIC_UITEST_STACK_EMAIL"
            }
        }

        var passwordKey: String {
            switch self {
            case .dogfood: return "MOSAIC_DOGFOOD_STACK_PASSWORD"
            case .uitest: return "MOSAIC_UITEST_STACK_PASSWORD"
            }
        }
    }

    /// Resolve the highest-precedence credential pair, or `nil` when none is
    /// available. See the type doc for the full precedence order.
    func resolve() -> ResolvedCredentials? {
        // Dogfood account wins over the agent (uitest) account everywhere, so
        // resolve ALL dogfood sources before ANY uitest source.
        for account in [Account.dogfood, .uitest] {
            if let fromEnv = credentials(in: environment, for: account) {
                return fromEnv
            }
            for path in secretFilePaths {
                guard let contents = readFile(path) else { continue }
                let parsed = Self.parseEnvFile(contents)
                if let fromFile = credentials(in: parsed, for: account) {
                    return fromFile
                }
            }
        }
        return nil
    }

    /// Read a non-empty email/password pair for `account` out of a key/value map.
    private func credentials(
        in map: [String: String],
        for account: Account
    ) -> ResolvedCredentials? {
        guard let email = map[account.emailKey], !email.isEmpty,
              let password = map[account.passwordKey], !password.isEmpty
        else {
            return nil
        }
        return ResolvedCredentials(email: email, password: password)
    }

    /// Parse a `KEY=value` `.env` file into a dictionary, skipping comments and
    /// blank lines and stripping a single layer of surrounding quotes. Mirrors
    /// the tiny parser already used by `AuthEnvironment.devOverride`.
    static func parseEnvFile(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2 {
                if value.hasPrefix("\""), value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                } else if value.hasPrefix("'"), value.hasSuffix("'") {
                    value = String(value.dropFirst().dropLast())
                }
            }
            result[key] = value
        }
        return result
    }
}
#endif
