import type { ReactNode } from 'react';
import changelog from '../../CHANGELOG.md?raw';
import { CloseIcon } from './icons';

// What's new: the release notes, in the same calm sheet as Settings. Shown
// once, the first time Firn opens after an update (src/main.ts), and any
// time from the Firn menu or the command bar.
//
// The words are CHANGELOG.md's, the same notes as each GitHub release,
// built into Firn: nothing is fetched to show them. Each version's section
// there reads:
//
//   ## Firn 0.1.1
//
//   **One-line headline.**
//
//   A sentence or two about the biggest change.
//
//   ### New
//   - **Something** does this.
//
// (### New / Better / Fixed are optional, and so are plain paragraphs.)

interface Block {
  kind: 'paragraph' | 'heading' | 'list';
  lines: string[];
}

export interface Release {
  version: string;
  headline: string;
  blocks: Block[];
}

export function parseChangelog(text: string): Release[] {
  const releases: Release[] = [];
  let release: Release | null = null;
  let block: Block | null = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    const version = /^##\s+Firn\s+(\d+\.\d+\.\d+)/i.exec(line);
    if (version) {
      release = { version: version[1], headline: '', blocks: [] };
      releases.push(release);
      block = null;
      continue;
    }
    if (!release) continue;
    if (!line) {
      block = null;
      continue;
    }
    const heading = /^###\s+(.*)$/.exec(line);
    if (heading) {
      release.blocks.push({ kind: 'heading', lines: [heading[1]] });
      block = null;
      continue;
    }
    // The headline: a line in bold on its own, before anything else.
    const bold = /^\*\*(.+)\*\*$/.exec(line);
    if (bold && !release.headline && !release.blocks.length) {
      release.headline = bold[1];
      continue;
    }
    const item = /^[-*]\s+(.*)$/.exec(line);
    if (item) {
      if (block?.kind !== 'list') {
        block = { kind: 'list', lines: [] };
        release.blocks.push(block);
      }
      block.lines.push(item[1]);
      continue;
    }
    if (block?.kind !== 'paragraph') {
      block = { kind: 'paragraph', lines: [] };
      release.blocks.push(block);
    }
    block.lines.push(line);
  }
  return releases;
}

// a < b, for versions like 0.1.10.
const older = (a: string, b: string) => {
  const x = a.split('.').map(Number);
  const y = b.split('.').map(Number);
  for (let i = 0; i < 3; i++)
    if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) < (y[i] ?? 0);
  return false;
};

// The versions to show, newest first: after `since` up to this version, or
// just this one (since '', or a since that isn't older).
export function releasesToShow(
  releases: Release[],
  version: string,
  since: string,
) {
  const upTo = releases.filter((r) => !older(version, r.version));
  const newer =
    since && older(since, version)
      ? upTo.filter((r) => older(since, r.version))
      : [];
  if (newer.length) return newer;
  const current = releases.find((r) => r.version === version);
  return current ? [current] : upTo.slice(0, 1);
}

// **bold** in plain text, without reading it as HTML.
function inline(text: string): ReactNode[] {
  return text
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .split(/(\*\*[^*]+\*\*)/)
    .filter(Boolean)
    .map((part, i) =>
      part.startsWith('**') && part.endsWith('**') ? (
        <strong key={i}>{part.slice(2, -2)}</strong>
      ) : (
        part
      ),
    );
}

export function WhatsNewPanel({
  version,
  since,
}: {
  version: string;
  since: string;
}) {
  const releases = releasesToShow(parseChangelog(changelog), version, since);
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
        className="panel sheet whats-new-sheet"
        role="dialog"
        aria-label="What's new in Firn"
        tabIndex={-1}
      >
        <header className="sheet-header">
          <h2>What's new in Firn</h2>
          <button className="icon-button" title="Close (Esc)" onClick={close}>
            <CloseIcon />
          </button>
        </header>
        <div className="sheet-body whats-new-body">
          {releases.map((release) => (
            <section key={release.version} className="whats-new-release">
              <p className="whats-new-version">Firn {release.version}</p>
              {release.headline && (
                <p className="whats-new-headline">{release.headline}</p>
              )}
              {release.blocks.map((block, i) =>
                block.kind === 'heading' ? (
                  <h3 key={i}>{block.lines[0]}</h3>
                ) : block.kind === 'list' ? (
                  <ul key={i}>
                    {block.lines.map((line, j) => (
                      <li key={j}>{inline(line)}</li>
                    ))}
                  </ul>
                ) : (
                  <p key={i}>{inline(block.lines.join(' '))}</p>
                ),
              )}
            </section>
          ))}
        </div>
        <footer className="sheet-footer">
          <span>Firn {version}</span>
          {/* Takes the keyboard, so Enter (or Esc) closes it. */}
          <button className="sheet-button" onClick={close} autoFocus>
            Got it
          </button>
        </footer>
      </div>
    </div>
  );
}
