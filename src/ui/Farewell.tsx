import { CloseIcon } from './icons';

// The goodbye card: Firn's last version on Electron (src/farewell.ts). The
// same calm sheet as What's new, with David's words for this computer.
// Linux gets the Windows words: neither gets the new app.
const WORDS =
  window.firn.platform === 'darwin'
    ? {
        title: 'Firn is becoming a Mac app.',
        body: [
          "I've rebuilt Firn from the ground up, just for the Mac, and it's almost ready. This version won't get updates anymore, including security fixes.",
          "The new Firn is a fresh start, so nothing carries over. Your passwords, spaces, and Basecamp stay here. Keep this version until you've moved what you need.",
        ],
        link: "See what's next",
        close: 'Later',
      }
    : {
        title: 'This is the last Firn for Windows.',
        body: [
          "I'm rebuilding Firn as a native Mac app, and I can't build two browsers well on my own. So this is the final version for Windows.",
          "Firn keeps working, but it won't get updates anymore, including security fixes. Over the next few months, please move to a browser that's still updated.",
          'Thank you for trying Firn this early. It meant more than you know.',
        ],
        link: 'Read why',
        close: 'Close',
      };

export function FarewellPanel() {
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
        className="panel sheet farewell-sheet"
        role="dialog"
        aria-label={WORDS.title}
        tabIndex={-1}
        data-testid="farewell"
      >
        <header className="sheet-header">
          <h2>{WORDS.title}</h2>
          <button className="icon-button" title="Close (Esc)" onClick={close}>
            <CloseIcon />
          </button>
        </header>
        <div className="sheet-body whats-new-body">
          {WORDS.body.map((line, i) => (
            <p key={i}>{line}</p>
          ))}
          <p className="farewell-sign">— David</p>
        </div>
        <footer className="sheet-footer farewell-footer">
          {/* Takes the keyboard, so Enter (or Esc) only closes it. */}
          <button className="sheet-button is-quiet" onClick={close} autoFocus>
            {WORDS.close}
          </button>
          <button
            className="sheet-button is-ink"
            onClick={() => window.firn.openFarewellLink()}
            data-testid="farewell-link"
          >
            {WORDS.link}
          </button>
        </footer>
      </div>
    </div>
  );
}
