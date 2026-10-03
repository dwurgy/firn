import { useEffect, useRef, useState, type FormEvent } from 'react';
import type { NavState } from '../types';
import { SiteIcon } from './icons';

// A quieter version of the URL for when the address bar isn't being edited.
function prettyUrl(url: string): string {
  return url.replace(/^https?:\/\/(www\.)?/i, '').replace(/\/$/, '');
}

export function AddressBar({ nav }: { nav: NavState }) {
  const [draft, setDraft] = useState('');
  const [editing, setEditing] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(
    () =>
      window.firn.onFocusAddress((url) => {
        inputRef.current?.focus();
        // Set after focusing, so it wins over the focus handler's value.
        setDraft(url);
        requestAnimationFrame(() => inputRef.current?.select());
      }),
    [],
  );

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (!draft.trim()) return;
    window.firn.navigate(draft);
    inputRef.current?.blur();
  };

  return (
    <form className="address" onSubmit={submit}>
      <input
        ref={inputRef}
        className="address-input"
        spellCheck={false}
        placeholder="Search or enter address"
        value={editing ? draft : prettyUrl(nav.url)}
        onChange={(e) => setDraft(e.target.value)}
        onFocus={(e) => {
          setDraft(nav.url);
          setEditing(true);
          const input = e.currentTarget;
          requestAnimationFrame(() => input.select());
        }}
        onBlur={() => setEditing(false)}
        onKeyDown={(e) => {
          if (e.key === 'Escape') e.currentTarget.blur();
        }}
      />
      {nav.sitePermissions && !editing && (
        <button
          type="button"
          className="site-button"
          title="What this site may use"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => window.firn.showSitePermissions()}
        >
          <SiteIcon />
        </button>
      )}
      {nav.zoom !== 1 && !editing && (
        <button
          type="button"
          className="zoom-badge"
          title="Zoom for this site. Click to reset to 100%"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => window.firn.zoom(0)}
        >
          {Math.round(nav.zoom * 100)}%
        </button>
      )}
      <span className="loading-track">
        <span className={`loading-line ${nav.isLoading ? 'is-loading' : ''}`} />
      </span>
    </form>
  );
}
