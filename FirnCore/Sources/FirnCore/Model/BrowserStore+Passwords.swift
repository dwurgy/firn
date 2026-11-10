import Foundation
import Observation

extension BrowserStore {
    // MARK: - Saving passwords

    /// A page on screen says someone just signed in. Offers to save it,
    /// unless that login is already saved in the tab's data store, its site
    /// is on a "Never" list there, or the Keychain can't be read.
    func offerToSave(_ login: SubmittedLogin, from tab: Tab) {
        guard let passwords, onScreenTabIDs.contains(tab.id),
              let space = spaces.first(where: { $0.id == tab.spaceID }),
              !neverSavesPasswords(on: login.site, in: space.dataStoreID),
              let needsUpdate = (try? passwords.needsUpdate(for: login, in: space.dataStoreID)) ?? nil
        else { return }
        passwordOffer = PasswordOffer(tabID: tab.id, spaceID: space.id, dataStoreID: space.dataStoreID, login: login, isUpdate: needsUpdate)
    }

    /// Saves the password offered, in the data store it was used in.
    /// Returns false if the Keychain said no; the offer then stays, so the
    /// prompt can say so and Save can be tried again.
    @discardableResult
    public func savePasswordOffer() -> Bool {
        guard let offer = passwordOffer, let passwords else { return false }
        do {
            try passwords.save(username: offer.login.username, password: offer.login.password,
                               for: offer.login.site, in: offer.dataStoreID)
            passwordOffer = nil
            return true
        } catch {
            return false
        }
    }

    /// "Not now": nothing is saved, and Firn asks again next time.
    public func dismissPasswordOffer() {
        passwordOffer = nil
    }

    /// "Never for this site": in the offering tab's space, Firn stops asking
    /// to save passwords for the site.
    public func neverSavePasswordsForOffer() {
        guard let offer = passwordOffer else { return }
        passwordOffer = nil
        guard let index = spaces.firstIndex(where: { $0.id == offer.spaceID }) else { return }
        var space = spaces[index]
        guard !space.neverSavePasswordSites.contains(offer.login.site.name) else { return }
        space.neverSavePasswordSites = Array((space.neverSavePasswordSites + [offer.login.site.name]).suffix(Space.neverSaveLimit))
        space.lastChangedAt = now()
        spaces[index] = space
    }

    /// The sites no space using this data store saves passwords for
    /// (`PasswordSite.name`), by name.
    public func neverSavePasswordSites(in dataStoreID: UUID) -> [String] {
        Set(spaces.filter { $0.dataStoreID == dataStoreID }.flatMap(\.neverSavePasswordSites)).sorted()
    }

    /// Settings › Passwords' Remove: Firn offers to save passwords on the
    /// site again, in every space using this data store (they share passwords).
    public func allowSavingPasswords(on siteName: String, in dataStoreID: UUID) {
        for index in spaces.indices
        where spaces[index].dataStoreID == dataStoreID && spaces[index].neverSavePasswordSites.contains(siteName) {
            spaces[index].neverSavePasswordSites.removeAll { $0 == siteName }
            spaces[index].lastChangedAt = now()
        }
    }

    /// Whether any space using this data store said "Never" for the site.
    func neverSavesPasswords(on site: PasswordSite, in dataStoreID: UUID) -> Bool {
        spaces.contains { $0.dataStoreID == dataStoreID && $0.neverSavePasswordSites.contains(site.name) }
    }

    // MARK: - Filling passwords

    /// A sign-in field was clicked on a tab on screen: offers the site's
    /// saved logins in the tab's data store under it, if there are any.
    /// Only usernames are held; the password is read again when one is picked.
    func offerToFill(_ site: PasswordSite, at field: CGRect, from tab: Tab) {
        guard let passwords, onScreenTabIDs.contains(tab.id),
              let space = spaces.first(where: { $0.id == tab.spaceID }),
              let logins = try? passwords.logins(for: site, in: space.dataStoreID), !logins.isEmpty
        else {
            fillOffer = nil
            return
        }
        fillOffer = FillOffer(tabID: tab.id, site: site, dataStoreID: space.dataStoreID,
                              usernames: logins.map(\.username), field: field)
    }

    /// Fills the field offered with the saved login for `username`, read
    /// fresh from the Keychain. Returns whether the page took it.
    @discardableResult
    public func fill(username: String) async -> Bool {
        guard let offer = fillOffer, let passwords else { return false }
        fillOffer = nil
        guard let tab = tabs.first(where: { $0.id == offer.tabID }), onScreenTabIDs.contains(tab.id),
              let page = tab.page,
              let login = (try? passwords.logins(for: offer.site, in: offer.dataStoreID))?
                  .first(where: { $0.username == username })
        else { return false }
        return await page.fill(username: login.username, password: login.password, on: offer.site)
    }

    /// Closes the list of saved logins; nothing is filled.
    public func dismissFillOffer() {
        fillOffer = nil
    }
}
