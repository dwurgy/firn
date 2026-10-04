// What the welcome (shown the first time Firn opens) offers, shared by the
// window code and the UI.

// Everyday sites to start Basecamp with: the calm essentials (mail,
// calendar, files, notes, messages, video and music), no shopping or
// social feeds. The welcome shows each with its own icon, fetched from the
// site itself when the welcome opens (the first of `icons` that works;
// a public image, so nothing about the person is sent). If none can be
// fetched, Firn's own letter tile shows instead.
export const BASECAMP_SUGGESTIONS = [
  {
    name: 'Gmail',
    url: 'https://mail.google.com/',
    icons: [
      'https://ssl.gstatic.com/ui/v1/icons/mail/rfr/gmail.ico',
      'https://mail.google.com/favicon.ico',
    ],
  },
  {
    name: 'Outlook',
    url: 'https://outlook.live.com/mail/',
    icons: [
      'https://res.cdn.office.net/assets/mail/pwa/v1/pngs/apple-touch-icon.png',
      'https://outlook.live.com/favicon.ico',
    ],
  },
  {
    name: 'Calendar',
    url: 'https://calendar.google.com/',
    icons: [
      'https://ssl.gstatic.com/calendar/images/dynamiclogo_2020q4/calendar_31_2x.png',
      'https://calendar.google.com/googlecalendar/images/favicons_2020q4/calendar_31.ico',
    ],
  },
  {
    name: 'Drive',
    url: 'https://drive.google.com/',
    icons: [
      'https://ssl.gstatic.com/images/branding/product/2x/drive_2020q4_48dp.png',
      'https://drive.google.com/favicon.ico',
    ],
  },
  {
    name: 'Notion',
    url: 'https://www.notion.so/',
    icons: [
      'https://www.notion.so/images/favicon.ico',
      'https://www.notion.so/favicon.ico',
    ],
  },
  {
    name: 'WhatsApp',
    url: 'https://web.whatsapp.com/',
    icons: [
      'https://web.whatsapp.com/favicon.ico',
      'https://www.whatsapp.com/favicon.ico',
    ],
  },
  {
    name: 'YouTube',
    url: 'https://www.youtube.com/',
    icons: [
      'https://www.gstatic.com/youtube/img/branding/favicon/favicon_144x144.png',
      'https://www.youtube.com/favicon.ico',
    ],
  },
  {
    name: 'Spotify',
    url: 'https://open.spotify.com/',
    icons: [
      'https://open.spotify.com/favicon.ico',
      'https://www.spotify.com/favicon.ico',
    ],
  },
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
