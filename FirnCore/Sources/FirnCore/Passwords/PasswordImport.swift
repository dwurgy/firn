import Foundation

/// One login read from another app's password export: the exact site, the
/// username, and the password. In memory only, until imported.
public struct ImportedLogin: Hashable, Sendable {
    public let site: PasswordSite
    public let username: String
    public let password: String
}

extension ImportedLogin: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "ImportedLogin(\(site.name), password hidden)" }
    public var debugDescription: String { description }
}

public enum PasswordImportError: Error, Equatable {
    /// Bigger than any real export; not read at all.
    case tooLarge
    /// More rows than any real export.
    case tooManyRows
    /// Not UTF-8 text.
    case notText
    /// Quotes that don't close, or text after a closing quote: a damaged
    /// file, so none of it is trusted.
    case damaged
    /// No url, username, and password columns Firn knows: "Firn doesn't
    /// recognize this file," never a guess at which column is which.
    case notRecognized
}

/// A password export from another browser or password manager, read and
/// checked, nothing saved yet. Chrome, Arc, Edge, and Brave (`name, url,
/// username, password, note`), Safari and the Passwords app (`Title, URL,
/// Username, Password, Notes, OTPAuth`), Firefox (`url, username,
/// password, …`), 1Password (`Title, Url, Username, Password, …`), and
/// Bitwarden (`…, login_uri, login_username, login_password, …`) are known
/// by their column names, in any case and any order.
public struct PasswordImportFile: Sendable {
    /// Far more than any real export (a few thousand logins is a few
    /// hundred kilobytes), small enough to read at once.
    static let sizeLimit = 10_000_000
    static let rowLimit = 20_000
    static let addressLimit = 2048

    /// What can come over, in the file's order, each site and username once.
    public let logins: [ImportedLogin]
    /// Skipped: http sites (never turned into https; the exact-site rule).
    public let notHttps: Int
    /// Skipped: no address, or one that isn't an https website (an app's
    /// `android://` address, say).
    public let noWebsite: Int
    /// Skipped: no password, or a username or password too long to be real.
    public let notALogin: Int
    /// Skipped: the same site and username again; the first one wins.
    public let repeated: Int

    public init(_ data: Data) throws {
        guard data.count <= Self.sizeLimit else { throw PasswordImportError.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw PasswordImportError.notText }
        if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
        let rows = try CSV.rows(text, limit: Self.rowLimit + 1)

        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else {
            throw PasswordImportError.notRecognized
        }
        func column(_ names: String...) -> Int? { header.firstIndex(where: names.contains) }
        guard let urlColumn = column("url", "login_uri"),
              let usernameColumn = column("username", "login_username"),
              let passwordColumn = column("password", "login_password")
        else { throw PasswordImportError.notRecognized }
        // Bitwarden lists secure notes, cards, and identities too; only its
        // logins are passwords. It may give one login several addresses,
        // separated by commas: the first is the one it was saved for.
        let isBitwarden = header[urlColumn] == "login_uri"
        let typeColumn = isBitwarden ? column("type") : nil

        var logins: [ImportedLogin] = []
        var seen: Set<[String]> = []
        var notHttps = 0, noWebsite = 0, notALogin = 0, repeated = 0
        for row in rows.dropFirst() {
            func field(_ index: Int) -> String { index < row.count ? row[index] : "" }
            if let typeColumn, !field(typeColumn).isEmpty, field(typeColumn).lowercased() != "login" { continue }

            var address = field(urlColumn)
            if isBitwarden, let first = address.split(separator: ",", omittingEmptySubsequences: false).first {
                address = String(first)
            }
            address = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard address.count <= Self.addressLimit, let url = URL(string: address), let site = PasswordSite(url) else {
                if address.lowercased().hasPrefix("http://") { notHttps += 1 } else { noWebsite += 1 }
                continue
            }
            let username = field(usernameColumn), password = field(passwordColumn)
            guard !password.isEmpty, password.count <= PasswordStore.passwordLimit,
                  username.count <= PasswordStore.usernameLimit
            else { notALogin += 1; continue }
            guard seen.insert([site.name, username]).inserted else { repeated += 1; continue }
            logins.append(ImportedLogin(site: site, username: username, password: password))
        }
        self.logins = logins
        self.notHttps = notHttps
        self.noWebsite = noWebsite
        self.notALogin = notALogin
        self.repeated = repeated
    }
}

/// What an import did.
public struct PasswordImportResult: Equatable, Sendable {
    /// Saved as new logins.
    public var imported = 0
    /// Already saved in Firn with the same password: nothing to do.
    public var alreadySaved = 0
    /// Already saved in Firn with another password: Firn's was kept.
    public var keptFirns = 0
    /// Not saved because the Keychain refused (counted from the first
    /// refusal on; nothing after it is tried).
    public var notSaved = 0
}

extension PasswordStore {
    /// Saves an export's logins into one data store. A login already there
    /// (same site and username) is left as it is, even if the file has
    /// another password for it. Throws, writing nothing, if the store can't
    /// be read first.
    public func importLogins(_ logins: [ImportedLogin], into dataStoreID: UUID) throws -> PasswordImportResult {
        var saved: [[String]: String] = [:]
        for login in try allLogins(in: dataStoreID) {
            saved[[login.site.name, login.username]] = login.password
        }
        var result = PasswordImportResult()
        for (index, login) in logins.enumerated() {
            if let password = saved[[login.site.name, login.username]] {
                if password == login.password { result.alreadySaved += 1 } else { result.keptFirns += 1 }
                continue
            }
            do {
                try save(username: login.username, password: login.password, for: login.site, in: dataStoreID)
                saved[[login.site.name, login.username]] = login.password
                result.imported += 1
            } catch {
                result.notSaved = logins.count - index
                break
            }
        }
        return result
    }
}

/// Comma-separated values as exporters write them (RFC 4180): fields in
/// double quotes may hold commas, line breaks, and doubled quotes; lines end
/// with CRLF, LF, or CR. Blank lines are skipped.
enum CSV {
    static func rows(_ text: String, limit: Int) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var quoted = false, closed = false

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            closed = false
        }
        func endRow() throws {
            endField()
            if row != [""] { rows.append(row) }
            row = []
            if rows.count > limit { throw PasswordImportError.tooManyRows }
        }

        var scalars = text.unicodeScalars.makeIterator()
        var next = scalars.next()
        while let c = next {
            next = scalars.next()
            if quoted {
                if c == "\"" {
                    if next == "\"" {
                        field.append(c)
                        next = scalars.next()
                    } else {
                        quoted = false
                        closed = true
                    }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case ",":
                endField()
            case "\n":
                try endRow()
            case "\r":
                if next == "\n" { next = scalars.next() }
                try endRow()
            case "\"":
                // A quote opens a field; anywhere else the file is damaged.
                guard field.isEmpty, !closed else { throw PasswordImportError.damaged }
                quoted = true
            default:
                guard !closed else { throw PasswordImportError.damaged }
                field.append(c)
            }
        }
        guard !quoted else { throw PasswordImportError.damaged }
        if !field.isEmpty || closed || !row.isEmpty { try endRow() }
        return rows
    }
}
