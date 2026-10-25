import Foundation
import Testing
@testable import FirnCore

struct PasswordImportTests {
    private let work = UUID()
    private let personal = UUID()

    private func read(_ text: String) throws -> PasswordImportFile { try PasswordImportFile(Data(text.utf8)) }
    private func site(_ name: String) -> PasswordSite { PasswordSite(URL(string: "https://\(name)/")!)! }
    private func pairs(_ file: PasswordImportFile) -> [String] {
        file.logins.map { "\($0.site.name) \($0.username) \($0.password)" }
    }

    // MARK: - Each app's export

    @Test func chromeArcEdgeAndBrave() throws {
        let file = try read("""
            name,url,username,password,note
            example.com,https://example.com/login,ana@example.com,s3cret,
            accounts.google.com,https://accounts.google.com/signin/v2,ana@gmail.com,"pa,ss",work mail

            """)
        #expect(pairs(file) == ["example.com ana@example.com s3cret", "accounts.google.com ana@gmail.com pa,ss"])
    }

    @Test func safariAndThePasswordsApp() throws {
        let file = try read("""
            Title,URL,Username,Password,Notes,OTPAuth
            example.com (ana),https://example.com/,ana,hunter2,"a note
            on two lines",
            """)
        #expect(pairs(file) == ["example.com ana hunter2"])
    }

    @Test func firefox() throws {
        let file = try read("""
            "url","username","password","httpRealm","formActionOrigin","guid","timeCreated","timeLastUsed","timePasswordChanged"
            "https://example.com:8443","ana","x""y","","https://example.com:8443","{1}","1","2","3"
            "chrome://FirefoxAccounts","ana","sync","Firefox Accounts credentials","","{2}","1","2","3"
            """)
        #expect(pairs(file) == ["example.com:8443 ana x\"y"])
        #expect(file.noWebsite == 1)
    }

    @Test func onePassword() throws {
        let file = try read("""
            Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes
            Example,https://example.com,ana,pw1,,false,false,,
            """)
        #expect(pairs(file) == ["example.com ana pw1"])
    }

    @Test func bitwardenOnlyItsLoginsAndTheFirstAddress() throws {
        let file = try read("""
            folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
            ,,login,Example,,,0,"https://example.com,https://other.example",ana,pw1,
            ,,note,A secure note,secret stuff,,0,,,,
            ,,login,Shop,,,0,https://shop.example,bo,pw2,
            """)
        #expect(pairs(file) == ["example.com ana pw1", "shop.example bo pw2"])
        #expect(file.noWebsite == 0)
    }

    @Test func columnNamesAnyCaseAndOrder() throws {
        let file = try read("PASSWORD, Username ,URL\npw,ana,https://example.com\n")
        #expect(pairs(file) == ["example.com ana pw"])
    }

    @Test func aFileFirnDoesntKnowIsNeverGuessedAt() {
        #expect(throws: PasswordImportError.notRecognized) { try read("site,login,secret\nhttps://example.com,ana,pw\n") }
        #expect(throws: PasswordImportError.notRecognized) { try read("") }
        #expect(throws: PasswordImportError.notRecognized) { try read("url,username\nhttps://example.com,ana\n") }
    }

    // MARK: - Reading CSV

    @Test func aByteOrderMarkCRLFAndCR() throws {
        let file = try read("\u{FEFF}url,username,password\r\nhttps://a.example,ana,pw\r\rhttps://b.example,bo,pw\r")
        #expect(pairs(file) == ["a.example ana pw", "b.example bo pw"])
    }

    @Test func quotedFieldsKeepCommasLineBreaksAndQuotes() throws {
        let rows = try CSV.rows("a,\"b,c\",\"d\r\ne\",\"f\"\"g\",\"\"\n", limit: 10)
        #expect(rows == [["a", "b,c", "d\r\ne", "f\"g", ""]])
    }

    @Test func spacesAndUnicodeInPasswordsStayExactly() throws {
        let file = try read("url,username,password\nhttps://example.com, ana ,  pä ss🙂 \n")
        #expect(file.logins.first?.username == " ana ")
        #expect(file.logins.first?.password == "  pä ss🙂 ")
    }

    @Test func aDamagedFileIsntReadAtAll() {
        #expect(throws: PasswordImportError.damaged) { try read("url,username,password\nhttps://example.com,ana,\"pw\n") }
        #expect(throws: PasswordImportError.damaged) { try read("url,username,password\nhttps://example.com,ana,\"pw\"x\n") }
        #expect(throws: PasswordImportError.damaged) { try read("url,username,password\nhttps://example.com,ana,p\"w\n") }
    }

    @Test func onlyUTF8Text() {
        let latin1 = "url,username,password\nhttps://example.com,ana,pä\n".data(using: .isoLatin1)!
        #expect(throws: PasswordImportError.notText) { try PasswordImportFile(latin1) }
    }

    @Test func capsOnSizeAndRows() throws {
        let big = Data(repeating: UInt8(ascii: "a"), count: PasswordImportFile.sizeLimit + 1)
        #expect(throws: PasswordImportError.tooLarge) { try PasswordImportFile(big) }

        let row = "https://example.com,ana,pw\n"
        let atLimit = "url,username,password\n" + String(repeating: row, count: PasswordImportFile.rowLimit)
        #expect(try read(atLimit).repeated == PasswordImportFile.rowLimit - 1)
        #expect(throws: PasswordImportError.tooManyRows) { try read(atLimit + row) }
    }

    // MARK: - What can't come over

    @Test func whatCantComeOverIsCounted() throws {
        let file = try read("""
            url,username,password
            http://plain.example,ana,pw
            HTTP://loud.example,ana,pw
            ,ana,pw
            android://abc@com.example.app/,ana,pw
            example.com,ana,pw
            ftp://files.example,ana,pw
            https://example.com,ana,
            https://example.com,\(String(repeating: "u", count: 513)),pw
            https://example.com,ana,\(String(repeating: "p", count: 1025))
            https://example.com,ana,first
            https://EXAMPLE.com/other,ana,second
            https://example.com,bo,third
            """)
        #expect(pairs(file) == ["example.com ana first", "example.com bo third"])
        #expect(file.notHttps == 2)
        #expect(file.noWebsite == 4)
        #expect(file.notALogin == 3)
        #expect(file.repeated == 1)
    }

    @Test func anImportedLoginNeverShowsItsPasswordWhenPrinted() throws {
        let login = try #require(try read("url,username,password\nhttps://example.com,ana,s3cret\n").logins.first)
        #expect(!"\(login)".contains("s3cret"))
        #expect(!String(reflecting: login).contains("s3cret"))
    }

    // MARK: - Importing

    @Test func importingSavesIntoOneDataStoreOnly() throws {
        let store = PasswordStore(vault: MemoryVault())
        let file = try read("url,username,password\nhttps://a.example,ana,pw1\nhttps://b.example,bo,pw2\n")
        let result = try store.importLogins(file.logins, into: work)
        #expect(result == PasswordImportResult(imported: 2))
        #expect(try store.allLogins(in: work).map(\.username) == ["ana", "bo"])
        #expect(try store.allLogins(in: personal).isEmpty)
    }

    @Test func aLoginAlreadySavedKeepsFirnsPassword() throws {
        let store = PasswordStore(vault: MemoryVault())
        try store.save(username: "ana", password: "firns", for: site("a.example"), in: work)
        try store.save(username: "bo", password: "same", for: site("b.example"), in: work)
        let file = try read("""
            url,username,password
            https://a.example,ana,fromTheFile
            https://b.example,bo,same
            https://c.example,cy,new
            """)
        let result = try store.importLogins(file.logins, into: work)
        #expect(result == PasswordImportResult(imported: 1, alreadySaved: 1, keptFirns: 1))
        #expect(try store.password(for: "ana", on: site("a.example"), in: work) == "firns")
        #expect(try store.password(for: "cy", on: site("c.example"), in: work) == "new")
    }

    @Test func anotherSpacesLoginsDontCountAsSaved() throws {
        let store = PasswordStore(vault: MemoryVault())
        try store.save(username: "ana", password: "personal", for: site("a.example"), in: personal)
        let file = try read("url,username,password\nhttps://a.example,ana,work\n")
        #expect(try store.importLogins(file.logins, into: work) == PasswordImportResult(imported: 1))
        #expect(try store.password(for: "ana", on: site("a.example"), in: personal) == "personal")
    }

    @Test func aKeychainThatRefusesSaysHowManyWerentSaved() throws {
        let store = PasswordStore(vault: RefusingVault())
        let file = try read("url,username,password\nhttps://a.example,ana,pw\nhttps://b.example,bo,pw\n")
        #expect(try store.importLogins(file.logins, into: work) == PasswordImportResult(notSaved: 2))
    }
}
