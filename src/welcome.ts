// What the welcome (shown the first time Firn opens) offers, shared by the
// window code and the UI.

// Everyday sites to start Basecamp with: the calm essentials (mail,
// calendar, files, notes, messages, video and music), no shopping or
// social feeds. The welcome shows them as Firn's
// own letter tiles, so nothing is fetched from them until they're chosen.
export const BASECAMP_SUGGESTIONS = [
  { name: 'Gmail', url: 'https://mail.google.com/' },
  { name: 'Outlook', url: 'https://outlook.live.com/mail/' },
  { name: 'Calendar', url: 'https://calendar.google.com/' },
  { name: 'Drive', url: 'https://drive.google.com/' },
  { name: 'Notion', url: 'https://www.notion.so/' },
  { name: 'WhatsApp', url: 'https://web.whatsapp.com/' },
  { name: 'YouTube', url: 'https://www.youtube.com/' },
  { name: 'Spotify', url: 'https://open.spotify.com/' },
];

// Each space's theme color: it softly tints the frame and the glass.
// Muted, natural tones so the tint stays calm.
export const SPACE_COLOR_CHOICES = [
  { name: 'Sand', hex: '#c9a27e' },
  { name: 'Glacier', hex: '#7f9cb0' },
  { name: 'Sage', hex: '#8fae8b' },
  { name: 'Heather', hex: '#b88a9e' },
  { name: 'Ochre', hex: '#c4a95b' },
  { name: 'Dusk', hex: '#8e8fb8' },
  { name: 'Clay', hex: '#b07f6a' },
  { name: 'Lagoon', hex: '#6fa3a0' },
];
