import { useEffect, useRef, useState, type FormEvent } from 'react';
import type { NavState } from '../types';
import {
  BackIcon,
  CloseIcon,
  ForwardIcon,
  MaximizeIcon,
  MinimizeIcon,
  ReloadIcon,
  RestoreIcon,
  StopIcon,
} from './icons';

// macOS draws its own traffic lights; elsewhere Firn draws the window buttons.
const OWN_WINDOW_BUTTONS = window.firn.platform !== 'darwin';

const EMPTY: NavState = {
  url: '',
  title: '',
  canGoBack: false,
  canGoForward: false,
  isLoading: false,
};

// A quieter version of the URL for when the address bar isn't being edited.
function prettyUrl(url: string): string {
  return url.replace(/^https?:\/\/(www\.)?/i, '').replace(/\/$/, '');
}

export function App() {
  const [nav, setNav] = useState<NavState>(EMPTY);
  const [draft, setDraft] = useState('');
  const [editing, setEditing] = useState(false);
  const [maximized, setMaximized] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const offState = window.firn.onNavState(setNav);
    const offFocus = window.firn.onFocusAddress(() => {
      inputRef.current?.focus();
      inputRef.current?.select();
    });
    const offMax = window.firn.onMaximizedChange(setMaximized);
    window.firn.ready();
    return () => {
      offState();
      offFocus();
      offMax();
    };
  }, []);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (!draft.trim()) return;
    window.firn.navigate(draft);
    inputRef.current?.blur();
  };

  return (
    <>
      <header className="toolbar">
        <nav className="nav-buttons">
          <button
            className="icon-button"
            title="Back"
            disabled={!nav.canGoBack}
            onClick={() => window.firn.command('back')}
          >
            <BackIcon />
          </button>
          <button
            className="icon-button"
            title="Forward"
            disabled={!nav.canGoForward}
            onClick={() => window.firn.command('forward')}
          >
            <ForwardIcon />
          </button>
          <button
            className="icon-button"
            title={nav.isLoading ? 'Stop' : 'Reload'}
            onClick={() =>
              window.firn.command(nav.isLoading ? 'stop' : 'reload')
            }
          >
            {nav.isLoading ? <StopIcon /> : <ReloadIcon />}
          </button>
        </nav>

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
          <span className="loading-track">
            <span
              className={`loading-line ${nav.isLoading ? 'is-loading' : ''}`}
            />
          </span>
        </form>

        {OWN_WINDOW_BUTTONS && (
          <div className="window-buttons">
            <button
              className="icon-button"
              title="Minimize"
              onClick={() => window.firn.windowCommand('minimize')}
            >
              <MinimizeIcon />
            </button>
            <button
              className="icon-button"
              title={maximized ? 'Restore' : 'Maximize'}
              onClick={() => window.firn.windowCommand('toggle-maximize')}
            >
              {maximized ? <RestoreIcon /> : <MaximizeIcon />}
            </button>
            <button
              className="icon-button close-button"
              title="Close"
              onClick={() => window.firn.windowCommand('close')}
            >
              <CloseIcon />
            </button>
          </div>
        )}
      </header>
      {/* Sits right behind the web page so the page looks lifted off the frame. */}
      <div className="page-shadow" />
    </>
  );
}
