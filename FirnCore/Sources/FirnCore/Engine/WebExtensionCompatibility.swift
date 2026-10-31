/// Limited extension-only compatibility surfaces for missing WebKit APIs.
/// Install in the extension controller's web view configuration at document start,
/// in the page content world and only in the main frame.
enum WebExtensionCompatibility {
    static let source = #"""
    (() => {
        if (location.protocol !== 'webkit-extension:') return;
        const namespaces = [globalThis.browser, globalThis.chrome].filter(
            api => api && api.runtime && api.runtime.id
        );
        if (!namespaces.length) return;

        const event = () => {
            const listeners = new Set();
            return Object.freeze({
                addListener(listener) {
                    if (typeof listener === 'function') listeners.add(listener);
                },
                removeListener(listener) { listeners.delete(listener); },
                hasListener(listener) { return listeners.has(listener); },
                hasListeners() { return listeners.size > 0; }
            });
        };
        const result = (value, callback) => {
            if (typeof callback === 'function') {
                queueMicrotask(() => callback(value));
                return;
            }
            return Promise.resolve(value);
        };
        const denied = Object.freeze({
            onClicked: event(),
            onButtonClicked: event(),
            onClosed: event(),
            onShown: event(),
            getPermissionLevel(callback) { return result('denied', callback); },
            getAll(callback) { return result({}, callback); },
            update(id, options, callback) { return result(false, callback); },
            clear(id, callback) { return result(false, callback); },
            create(...args) {
                const error = new Error('Notifications are unsupported: permission denied by Firn.');
                // A callback success value without runtime.lastError would claim a
                // notification was created. Throw instead for callback callers.
                if (args.some(arg => typeof arg === 'function')) throw error;
                return Promise.reject(error);
            }
        });
        const navigationTarget = (tabs, permissions) => {
            const listeners = new Set();
            const created = async tab => {
                if (!tab || !Number.isSafeInteger(tab.id) || tab.id < 0 ||
                    !Number.isSafeInteger(tab.openerTabId) || tab.openerTabId < 0 ||
                    typeof tab.url !== 'string') return;
                try {
                    if (!(await permissions.contains({permissions: ['webNavigation']}))) return;
                } catch { return; }
                // tabs.onCreated supplies tab IDs and the tab URL. It does not
                // supply frame, process, or full webNavigation lifecycle data.
                const details = { tabId: tab.id, sourceTabId: tab.openerTabId,
                                  url: tab.url, timeStamp: Date.now() };
                for (const listener of [...listeners]) listener(details);
            };
            return Object.freeze({
                addListener(listener, filter) {
                    if (filter !== undefined) {
                        throw new TypeError('onCreatedNavigationTarget filters are unsupported');
                    }
                    if (typeof listener !== 'function') throw new TypeError('Listener must be a function');
                    if (listeners.has(listener)) return;
                    if (!listeners.size) tabs.onCreated.addListener(created);
                    listeners.add(listener);
                },
                removeListener(listener) {
                    if (!listeners.delete(listener)) return;
                    if (!listeners.size) tabs.onCreated.removeListener(created);
                },
                hasListener(listener) { return listeners.has(listener); },
                hasListeners() { return listeners.size > 0; }
            });
        };
        for (const api of namespaces) {
            if (api.notifications == null) api.notifications = denied;
            const nativeCreated = api.tabs?.onCreated;
            let declaredNavigation = false;
            try { declaredNavigation = api.runtime.getManifest().permissions?.includes('webNavigation') === true; }
            catch { /* No declared permission means no synthesized navigation API. */ }
            if (nativeCreated && typeof nativeCreated.addListener === 'function' &&
                typeof nativeCreated.removeListener === 'function' &&
                declaredNavigation && typeof api.permissions?.contains === 'function' &&
                api.webNavigation?.onCreatedNavigationTarget == null) {
                const navigation = api.webNavigation ?? {};
                Object.defineProperty(navigation, 'onCreatedNavigationTarget', {
                    value: navigationTarget(api.tabs, api.permissions), configurable: true
                });
                // Retain the augmented native wrapper in a getter closure. A value
                // override alone does not survive WebKit namespace rematerialization.
                // Returning the native object also preserves method receivers.
                Object.defineProperty(api, 'webNavigation', {
                    get: () => navigation, configurable: true
                });
            }
        }
    })();
    """#
}
