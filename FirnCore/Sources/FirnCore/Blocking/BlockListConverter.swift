import Foundation

/// Turns an Adblock Plus–style filter list (EasyList, EasyPrivacy) into the
/// JSON rules WebKit's content blocker reads. It covers what those lists mostly
/// use: blocking requests and hiding ad boxes. A rule WebKit can't say exactly
/// is skipped, so Firn blocks a little less rather than breaking pages.
///
/// The lists ship inside Firn, but they're still treated as untrusted text:
/// anything odd is skipped, never guessed at.
public enum BlockListConverter {
    public struct Output: Sendable {
        public let json: String
        public let ruleCount: Int
        /// Lines that were rules but couldn't be converted (comments don't count).
        public let skipped: Int
    }

    /// WebKit refuses a list with more rules than this.
    public static let maxRules = 150_000

    /// Selectors hidden together in one rule. Smaller groups keep one bad
    /// selector (WebKit drops the whole group) from costing much.
    static let selectorsPerRule = 50

    public static func convert(_ list: String) -> Output {
        var parser = Parser()
        for raw in list.split(whereSeparator: \.isNewline) {
            parser.add(raw.trimmingCharacters(in: .whitespaces))
        }
        let rules = parser.rules()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(rules)) ?? Data("[]".utf8)
        return Output(json: String(decoding: data, as: UTF8.self), ruleCount: rules.count, skipped: parser.skipped)
    }

    // MARK: - WebKit's rule format

    struct Rule: Encodable, Equatable {
        var trigger: Trigger
        var action: Action
    }

    struct Trigger: Encodable, Equatable {
        var urlFilter: String
        var caseSensitive: Bool?
        var resourceType: [String]?
        var loadType: [String]?
        var loadContext: [String]?
        var ifDomain: [String]?
        var unlessDomain: [String]?
        var ifTopURL: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case caseSensitive = "url-filter-is-case-sensitive"
            case resourceType = "resource-type"
            case loadType = "load-type"
            case loadContext = "load-context"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
            case ifTopURL = "if-top-url"
        }
    }

    struct Action: Encodable, Equatable {
        var type: String
        var selector: String?

        static let block = Action(type: "block")
        static let allow = Action(type: "ignore-previous-rules")
        static func hide(_ selector: String) -> Action { Action(type: "css-display-none", selector: selector) }
    }

    // MARK: - Reading the list

    struct Parser {
        var skipped = 0

        // Hiding ad boxes ("##" rules).
        var genericSelectors: [String] = []
        var genericSeen: Set<String> = []
        /// Selectors hidden everywhere except some sites ("~site.com##…").
        var genericUnless: [String: Set<String>] = [:]
        /// Selectors hidden only on some sites, keyed by the sites.
        var specific: [[String]: [String]] = [:]
        var specificOrder: [[String]] = []
        /// "#@#" exceptions: sites where a selector isn't hidden; empty means nowhere.
        var hideExceptions: [String: Set<String>] = [:]

        // Requests.
        var blocks: [Rule] = []
        var allows: [Rule] = []
        var cosmeticAllows: [Rule] = []
        var pageAllows: [Rule] = []

        mutating func add(_ line: String) {
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { return }
            if let cosmetic = Self.splitCosmetic(line) {
                addCosmetic(sites: cosmetic.sites, marker: cosmetic.marker, selector: cosmetic.selector)
            } else if !addNetwork(line) {
                skipped += 1
            }
        }

        /// "sites##selector", "sites#@#selector", or another "#…#" kind.
        static func splitCosmetic(_ line: String) -> (sites: Substring, marker: Substring, selector: Substring)? {
            guard let hash = line.firstIndex(of: "#") else { return nil }
            let sites = line[..<hash]
            // A site list never holds these; a request rule with a "#" in its path might.
            if sites.contains(where: { "/|@$\"!^".contains($0) }) { return nil }
            let rest = line[line.index(after: hash)...]
            guard let close = rest.firstIndex(of: "#") else { return nil }
            let marker = rest[..<close]
            guard marker.count <= 2 else { return nil }
            return (sites, marker, rest[rest.index(after: close)...])
        }

        mutating func addCosmetic(sites: Substring, marker: Substring, selector raw: Substring) {
            let selector = raw.trimmingCharacters(in: .whitespaces)
            guard marker.isEmpty || marker == "@", Self.isPlainSelector(selector),
                  let domains = Self.domains(sites, separator: ",")
            else {
                skipped += 1
                return
            }
            if marker == "@" {
                guard domains.excluded.isEmpty else { skipped += 1; return }
                if domains.included.isEmpty {
                    hideExceptions[selector] = []
                } else if hideExceptions[selector] != [] {
                    hideExceptions[selector, default: []].formUnion(domains.included)
                }
                return
            }
            switch (domains.included.isEmpty, domains.excluded.isEmpty) {
            case (true, true):
                if genericSeen.insert(selector).inserted { genericSelectors.append(selector) }
            case (true, false):
                genericUnless[selector, default: []].formUnion(domains.excluded)
            case (false, true):
                let key = domains.included.sorted()
                if specific[key] == nil { specificOrder.append(key) }
                specific[key, default: []].append(selector)
            case (false, false):
                // "site.com,~sub.site.com##…" can't be said in one WebKit rule.
                skipped += 1
            }
        }

        /// Plain CSS only: no list-specific extras like ":-abp-has" or ":has-text".
        static func isPlainSelector(_ selector: String) -> Bool {
            guard !selector.isEmpty, selector.allSatisfy(\.isASCII) else { return false }
            let extras = [":-abp-", ":has-text(", ":contains(", ":xpath(", ":upward(", ":remove(", ":style(",
                          ":matches-css", ":min-text-length(", ":watch-attr(", ":matches-path(", ":others(",
                          ":if(", ":if-not(", ":nth-ancestor(", ":matches-attr(", ":matches-prop("]
            if selector.hasPrefix("+js(") || selector.hasPrefix("^") { return false }
            // "body {padding-top:0}" restyles rather than hides; WebKit would drop the whole group.
            if selector.contains("{") || selector.contains("}") { return false }
            // CSS doesn't allow ":has()" inside ":has()"; a second one may be nested, so skip it.
            if selector.components(separatedBy: ":has(").count > 2 { return false }
            return !extras.contains { selector.contains($0) }
        }

        /// "a.com,~b.com" (or "|"-separated): lowercase hosts, or nil if any is odd.
        static func domains(_ text: Substring, separator: Character) -> (included: [String], excluded: [String])? {
            var included: [String] = []
            var excluded: [String] = []
            for part in text.split(separator: separator) {
                var domain = part.trimmingCharacters(in: .whitespaces).lowercased()
                let isExcluded = domain.hasPrefix("~")
                if isExcluded { domain.removeFirst() }
                guard !domain.isEmpty, !domain.hasPrefix("."), !domain.hasSuffix("."),
                      domain.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
                else { return nil }
                if isExcluded { excluded.append(domain) } else { included.append(domain) }
            }
            return (included, excluded)
        }

        /// WebKit's "*site.com" matches the site and every subdomain, as the lists mean.
        static func webKitDomains(_ domains: some Sequence<String>) -> [String] {
            domains.map { "*" + $0 }.sorted()
        }

        // MARK: Request rules

        static let resourceTypes: [String: String] = [
            "script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font",
            "media": "media", "xmlhttprequest": "fetch", "ping": "ping", "websocket": "websocket",
            "object": "other", "other": "other", "popup": "popup", "subdocument": "subdocument",
        ]

        /// False when the rule can't be converted.
        mutating func addNetwork(_ line: String) -> Bool {
            var text = Substring(line)
            let isException = text.hasPrefix("@@")
            if isException { text = text.dropFirst(2) }

            var optionText: Substring = ""
            if let dollar = text.lastIndex(of: "$") {
                optionText = text[text.index(after: dollar)...]
                text = text[..<dollar]
            }
            // "/…/" is a regular expression; WebKit's are too limited to trust a translation.
            if text.count > 1 && text.hasPrefix("/") && text.hasSuffix("/") { return false }

            var trigger = Trigger(urlFilter: "")
            var included: Set<String> = []
            var excluded: Set<String> = []
            var wholePage = false
            var hidingOnly = false

            for option in optionText.split(separator: ",") {
                var name = option.lowercased()
                let negated = name.hasPrefix("~")
                if negated { name.removeFirst() }
                switch name {
                case "third-party", "3p":
                    trigger.loadType = [negated ? "first-party" : "third-party"]
                case "first-party", "1p":
                    trigger.loadType = [negated ? "third-party" : "first-party"]
                case "match-case":
                    trigger.caseSensitive = true
                case "important", "all":
                    break
                case "document" where isException && !negated:
                    wholePage = true
                case "elemhide", "generichide", "ehide", "ghide":
                    guard isException, !negated else { return false }
                    hidingOnly = true
                case _ where name.hasPrefix("domain="):
                    guard let domains = Self.domains(Substring(name.dropFirst(7)), separator: "|") else { return false }
                    switch (domains.included.isEmpty, domains.excluded.isEmpty) {
                    case (false, true): trigger.ifDomain = Self.webKitDomains(domains.included)
                    case (true, false): trigger.unlessDomain = Self.webKitDomains(domains.excluded)
                    default: return false
                    }
                default:
                    guard let type = Self.resourceTypes[name] else { return false }
                    if negated { excluded.insert(type) } else { included.insert(type) }
                }
            }

            guard let filter = Self.urlFilter(text) else { return false }
            trigger.urlFilter = filter

            if wholePage || hidingOnly {
                // Allow everything on matching pages (or just their hiding rules).
                guard trigger.ifDomain == nil, trigger.unlessDomain == nil else { return false }
                if wholePage {
                    pageAllows.append(Rule(trigger: Trigger(urlFilter: ".*", ifTopURL: [filter]), action: .allow))
                } else {
                    cosmeticAllows.append(Rule(trigger: trigger, action: .allow))
                }
                return true
            }

            var types = included
            if !excluded.isEmpty {
                types = (types.isEmpty ? Set(Self.resourceTypes.values) : types).subtracting(excluded)
                if types.isEmpty { return false }
            }
            let action: Action = isException ? .allow : .block
            for typed in Self.split(trigger, types: types) {
                if isException { allows.append(Rule(trigger: typed, action: action)) }
                else { blocks.append(Rule(trigger: typed, action: action)) }
            }
            return true
        }

        /// A frame is WebKit's "document" type seen from a child frame; that
        /// context would wrongly narrow the other types, so frames get their own rule.
        static func split(_ trigger: Trigger, types: Set<String>) -> [Trigger] {
            if types.isEmpty { return [trigger] }
            var result: [Trigger] = []
            let others = types.subtracting(["subdocument"]).sorted()
            if !others.isEmpty {
                var plain = trigger
                plain.resourceType = others
                result.append(plain)
            }
            if types.contains("subdocument") {
                var frames = trigger
                frames.resourceType = ["document"]
                frames.loadContext = ["child-frame"]
                result.append(frames)
            }
            return result
        }

        /// The list's address pattern as WebKit's (smaller) regular expression,
        /// or nil when it can't be said exactly.
        static func urlFilter(_ pattern: Substring) -> String? {
            guard pattern.allSatisfy(\.isASCII) else { return nil }
            var rest = pattern
            var out = ""
            var inHost = false
            if rest.hasPrefix("||") {
                out = "^[^:]+://+([^:/]+\\.)?"
                rest = rest.dropFirst(2)
                inHost = true
            } else if rest.hasPrefix("|") {
                out = "^"
                rest = rest.dropFirst()
            }
            let anchoredEnd = rest.hasSuffix("|")
            if anchoredEnd { rest = rest.dropLast() }
            if out.isEmpty { while rest.hasPrefix("*") { rest = rest.dropFirst() } }
            if !anchoredEnd { while rest.hasSuffix("*") { rest = rest.dropLast() } }

            // Anything but a letter, digit, or "_-.%", as the lists define it.
            let separator = "[^a-zA-Z0-9_.%-]"
            for index in rest.indices {
                let character = rest[index]
                let isLast = rest.index(after: index) == rest.endIndex
                switch character {
                case "*":
                    out += ".*"
                    inHost = false
                case "^":
                    if inHost {
                        // WebKit always sees a path, so a host ends at "/" or ":".
                        out += "[/:]"
                        inHost = false
                    } else if isLast && !anchoredEnd {
                        out += "(\(separator).*)?$"
                    } else {
                        out += separator
                    }
                case "|":
                    return nil
                case "/", "?", "=", "&", ":":
                    inHost = false
                    out += character == "?" ? "\\?" : String(character)
                case ".", "+", "$", "{", "}", "(", ")", "[", "]", "\\":
                    out += "\\" + String(character)
                default:
                    out.append(character)
                }
            }
            if anchoredEnd { out += "$" }
            return out.isEmpty || out == "^" ? ".*" : out
        }

        // MARK: Putting it together

        /// Hiding first, then exceptions to hiding, then blocks, then allows:
        /// WebKit's "ignore-previous-rules" only cancels rules above it.
        func rules() -> [Rule] {
            var hiding: [Rule] = []
            var grouped: [String] = []
            var unlessGroups: [[String]: [String]] = [:]
            var unlessOrder: [[String]] = []

            for selector in genericSelectors {
                guard let exceptions = hideExceptions[selector] else {
                    grouped.append(selector)
                    continue
                }
                if exceptions.isEmpty { continue }
                hiding.append(Rule(trigger: Trigger(urlFilter: ".*", unlessDomain: Self.webKitDomains(exceptions)),
                                   action: .hide(selector)))
            }
            for (selector, unless) in genericUnless.sorted(by: { $0.key < $1.key }) where !genericSeen.contains(selector) {
                if let exceptions = hideExceptions[selector] {
                    if exceptions.isEmpty { continue }
                    hiding.append(Rule(trigger: Trigger(urlFilter: ".*", unlessDomain: Self.webKitDomains(unless.union(exceptions))),
                                       action: .hide(selector)))
                } else {
                    let key = unless.sorted()
                    if unlessGroups[key] == nil { unlessOrder.append(key) }
                    unlessGroups[key, default: []].append(selector)
                }
            }

            for chunk in Self.chunks(grouped) {
                hiding.append(Rule(trigger: Trigger(urlFilter: ".*"), action: .hide(chunk)))
            }
            for key in unlessOrder {
                for chunk in Self.chunks(unlessGroups[key] ?? []) {
                    hiding.append(Rule(trigger: Trigger(urlFilter: ".*", unlessDomain: Self.webKitDomains(key)), action: .hide(chunk)))
                }
            }
            for key in specificOrder {
                var plain: [String] = []
                for selector in specific[key] ?? [] {
                    guard let exceptions = hideExceptions[selector] else {
                        plain.append(selector)
                        continue
                    }
                    if exceptions.isEmpty { continue }
                    let sites = key.filter { !exceptions.contains($0) }
                    if sites.isEmpty { continue }
                    hiding.append(Rule(trigger: Trigger(urlFilter: ".*", ifDomain: Self.webKitDomains(sites)), action: .hide(selector)))
                }
                for chunk in Self.chunks(plain) {
                    hiding.append(Rule(trigger: Trigger(urlFilter: ".*", ifDomain: Self.webKitDomains(key)), action: .hide(chunk)))
                }
            }
            return hiding + cosmeticAllows + blocks + allows + pageAllows
        }

        static func chunks(_ selectors: [String]) -> [String] {
            stride(from: 0, to: selectors.count, by: selectorsPerRule).map {
                selectors[$0..<min($0 + selectorsPerRule, selectors.count)].joined(separator: ", ")
            }
        }
    }
}
