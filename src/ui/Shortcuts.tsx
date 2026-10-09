import { shortcutsToShow } from '../shortcuts';
import { CloseIcon } from './icons';

// Keyboard shortcuts (Settings, or the command bar): every shortcut, in
// plain words, grouped, with its keys as small key caps (Ctrl on Windows,
// ⌘ on a Mac). Only to read: shortcuts can't be changed. The list is the
// one Firn's keys are matched against (src/shortcuts.ts), so it's always
// what the keys really do.

export function ShortcutsPanel() {
  const groups = shortcutsToShow(window.firn.platform);
  const close = () => window.firn.closeOverlay();
  return (
    <div
      className="backdrop is-sheet"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) close();
      }}
      onKeyDown={(e) => {
        if (e.key === 'Escape') close();
      }}
    >
      <div
        className="panel sheet shortcuts-sheet"
        role="dialog"
        aria-label="Keyboard shortcuts"
        tabIndex={-1}
      >
        <header className="sheet-header">
          <h2>Keyboard shortcuts</h2>
          <button className="icon-button" title="Close (Esc)" onClick={close}>
            <CloseIcon />
          </button>
        </header>
        <div className="sheet-body shortcuts-body">
          {groups.map(({ group, shortcuts }) => (
            <section key={group} className="shortcuts-group">
              <h3>{group}</h3>
              {shortcuts.map((s) => (
                <div
                  key={s.id}
                  className="shortcut-row"
                  data-testid={`shortcut-${s.id}`}
                >
                  <span className="shortcut-label">{s.label}</span>
                  <span className="shortcut-keys">
                    {s.keys.map((caps, i) => (
                      <span key={i} className="shortcut-combo">
                        {i > 0 && <span className="shortcut-or">or</span>}
                        {caps.map((cap, j) => (
                          <kbd key={j} className="key-cap">
                            {cap}
                          </kbd>
                        ))}
                      </span>
                    ))}
                  </span>
                </div>
              ))}
            </section>
          ))}
        </div>
        <footer className="sheet-footer">
          <span />
          {/* Takes the keyboard, so Enter (or Esc) closes it. */}
          <button className="sheet-button" onClick={close} autoFocus>
            Done
          </button>
        </footer>
      </div>
    </div>
  );
}
