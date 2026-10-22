// Firn's goodbye: this is its last version on Electron. On a Mac, Firn is
// becoming a native app (a separate download); Windows and Linux keep this
// version, with no more updates. The card (src/ui/Farewell.tsx) shows once,
// the first time this version opens, and stays in the Firn menu.

// Where the card's button goes: the page about the move to the Mac app.
// The UI never sends an address: it asks the main process to open this one.
export const FAREWELL_URL = 'https://firnbrowser.com/mac';
