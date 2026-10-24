// What the welcome (shown the first time Firn opens) offers, shared by the
// window code and the UI.

// Everyday sites to start Basecamp with: the calm essentials (mail,
// calendar, files, an assistant, shopping, video and music), no social
// feeds. The welcome shows each with its own icon (see welcomeIcon
// in src/main.ts): the first of `prefer` that works, else the one Basecamp
// would pick from the site's page, else the first of `icons` that works,
// else Firn's own letter tile.
export const BASECAMP_SUGGESTIONS: {
  name: string;
  url: string;
  prefer?: string[];
  icons: string[];
}[] = [
  {
    name: 'Gmail',
    url: 'https://mail.google.com/',
    // Google's 2026 icons (newer than what its signed-out pages list).
    prefer: [
      'https://www.gstatic.com/images/branding/productlogos/gmail_2026/v2/web-64dp/logo_gmail_2026_color_2x_web_64dp.png',
      'https://ssl.gstatic.com/images/branding/productlogos/gmail_2026/v2/ico/gmail_2026_256dp.ico',
    ],
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
    // Google's 2026 icons (newer than what its signed-out pages list).
    prefer: [
      'https://www.gstatic.com/images/branding/productlogos/calendar_2026/v2/web-64dp/logo_calendar_2026_color_2x_web_64dp.png',
      'https://ssl.gstatic.com/images/branding/productlogos/calendar_2026/v2/ico/calendar_2026_256dp.ico',
    ],
    icons: [
      'https://ssl.gstatic.com/calendar/images/dynamiclogo_2020q4/calendar_31_2x.png',
      'https://calendar.google.com/googlecalendar/images/favicons_2020q4/calendar_31.ico',
    ],
  },
  {
    name: 'Drive',
    url: 'https://drive.google.com/',
    // Google's 2026 icons (newer than what its signed-out pages list).
    prefer: [
      'https://www.gstatic.com/images/branding/productlogos/drive_2026/v2/web-64dp/logo_drive_2026_color_2x_web_64dp.png',
      'https://ssl.gstatic.com/images/branding/productlogos/drive_2026/v2/ico/drive_2026_256dp.ico',
    ],
    icons: [
      'https://ssl.gstatic.com/images/branding/product/2x/drive_2020q4_48dp.png',
      'https://drive.google.com/favicon.ico',
    ],
  },
  {
    name: 'Claude',
    url: 'https://claude.ai/',
    icons: [
      'https://claude.ai/apple-touch-icon.png',
      'https://claude.ai/favicon.ico',
    ],
  },
  {
    name: 'Amazon',
    url: 'https://www.amazon.com/',
    icons: ['https://www.amazon.com/favicon.ico'],
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
  { name: 'Glacier', hex: '#7f9cb0' },
  { name: 'Sand', hex: '#c9a27e' },
  { name: 'Sage', hex: '#8fae8b' },
  { name: 'Heather', hex: '#b88a9e' },
  { name: 'Ochre', hex: '#c4a95b' },
  { name: 'Dusk', hex: '#8e8fb8' },
  { name: 'Clay', hex: '#b07f6a' },
  { name: 'Lagoon', hex: '#6fa3a0' },
];
