import { useEffect, useState } from 'react';
import type { Download } from '../types';
import {
  CloseIcon,
  DownloadIcon,
  FileIcon,
  FolderIcon,
  RetryIcon,
} from './icons';

// Finished downloads stay on the shelf this long, then quietly leave (the
// files stay in the Downloads folder).
const RECENT_MS = 30 * 60 * 1000;
const MAX_SHOWN = 3;

// The downloads shelf at the bottom of the sidebar: files downloading now
// and the last few finished ones. Click a finished one to open it.
export function DownloadsShelf({ downloads }: { downloads: Download[] }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 30 * 1000);
    return () => clearInterval(timer);
  }, []);
  const shown = downloads
    .filter(
      (d) =>
        d.state === 'progress' || now - (d.endedAt ?? d.startedAt) < RECENT_MS,
    )
    .slice(0, MAX_SHOWN);
  if (!shown.length) return null;
  return (
    <section className="downloads" aria-label="Downloads">
      {shown.map((d) => (
        <DownloadRow key={d.id} download={d} />
      ))}
    </section>
  );
}

function DownloadRow({ download: d }: { download: Download }) {
  const canOpen = d.state === 'done' && !d.missing;
  const canRetry = d.state === 'failed' || d.state === 'cancelled';
  const share = d.total > 0 ? Math.min(1, d.received / d.total) : 0;
  return (
    <div
      className={`download is-${d.state} ${canOpen || canRetry ? 'is-clickable' : ''}`}
      title={
        canOpen
          ? `Open ${d.name}`
          : canRetry
            ? 'Try again'
            : d.state === 'progress'
              ? `Downloading ${d.name}`
              : d.name
      }
      onClick={() => {
        if (canOpen) window.firn.openDownload(d.id);
        else if (canRetry) window.firn.retryDownload(d.id);
      }}
    >
      <span className="download-icon">
        {d.state === 'progress' ? (
          <ProgressRing share={share} known={d.total > 0} />
        ) : canRetry ? (
          <RetryIcon />
        ) : (
          <FileIcon />
        )}
      </span>
      <span className="download-text">
        <span className="download-name">{d.name}</span>
        <span className="download-detail">{detail(d)}</span>
      </span>
      <span className="download-actions">
        {d.state !== 'progress' && (
          <button
            className="icon-button"
            title="Show in folder"
            onClick={(e) => {
              e.stopPropagation();
              window.firn.showDownload(d.id);
            }}
          >
            <FolderIcon />
          </button>
        )}
        <button
          className="icon-button"
          title={
            d.state === 'progress' ? 'Cancel download' : 'Remove from list'
          }
          onClick={(e) => {
            e.stopPropagation();
            if (d.state === 'progress') window.firn.cancelDownload(d.id);
            else window.firn.removeDownload(d.id);
          }}
        >
          <CloseIcon />
        </button>
      </span>
    </div>
  );
}

// A thin ring that fills as the file arrives (it spins gently while the
// size is unknown), around a small arrow.
function ProgressRing({ share, known }: { share: number; known: boolean }) {
  const r = 7;
  const length = 2 * Math.PI * r;
  return (
    <span className={`download-ring ${known ? '' : 'is-unknown'}`}>
      <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden>
        <circle className="ring-track" cx="9" cy="9" r={r} />
        <circle
          className="ring-fill"
          cx="9"
          cy="9"
          r={r}
          strokeDasharray={length}
          strokeDashoffset={known ? length * (1 - share) : length * 0.75}
        />
      </svg>
      <DownloadIcon />
    </span>
  );
}

function detail(d: Download) {
  switch (d.state) {
    case 'progress':
      return d.total > 0
        ? `${size(d.received)} of ${size(d.total)}`
        : size(d.received);
    case 'done':
      return d.missing
        ? 'Moved or deleted'
        : `Done · ${size(d.total || d.received)}`;
    case 'failed':
      return 'Didn’t finish · Try again';
    case 'cancelled':
      return 'Cancelled · Try again';
  }
}

function size(bytes: number) {
  if (bytes < 1000) return `${bytes} B`;
  if (bytes < 1000 * 1000) return `${Math.round(bytes / 1000)} KB`;
  if (bytes < 1000 * 1000 * 1000) return `${(bytes / 1e6).toFixed(1)} MB`;
  return `${(bytes / 1e9).toFixed(1)} GB`;
}
