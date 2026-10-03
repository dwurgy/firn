// Turns whatever was typed in the address bar into a URL to load.

const SEARCH_URL = 'https://duckduckgo.com/?q=';

const ALLOWED_SCHEMES = /^(https?|file|about|view-source):/i;

// Whether typed text will run a search or open an address.
export function isSearch(url: string): boolean {
  return url.startsWith(SEARCH_URL);
}

// A web search for `text`.
export function searchUrl(text: string): string {
  return SEARCH_URL + encodeURIComponent(text.trim());
}

export function toNavigableUrl(input: string): string | null {
  const text = input.trim();
  if (!text) return null;

  // Already a full URL, e.g. "https://example.com".
  if (ALLOWED_SCHEMES.test(text)) return text;

  // Looks like an address, e.g. "example.com/page" or "localhost:3000".
  const looksLikeHost =
    !/\s/.test(text) &&
    (/^[^/]+\.[a-z]{2,}(?::\d+)?(\/.*)?$/i.test(text) ||
      /^localhost(:\d+)?(\/.*)?$/i.test(text) ||
      /^\d{1,3}(\.\d{1,3}){3}(:\d+)?(\/.*)?$/.test(text));
  if (looksLikeHost) {
    const local = /^(localhost|127\.|\d{1,3}(\.\d{1,3}){3})/i.test(text);
    return `${local ? 'http' : 'https'}://${text}`;
  }

  // Anything else is a search.
  return SEARCH_URL + encodeURIComponent(text);
}
