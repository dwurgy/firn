import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import { Floating } from './Floating';
import { Peek } from './Peek';
import { TopBar } from './TopBar';
import './styles.css';

// The same UI code runs in several layers; `?view=` says which one this is.
const view = new URLSearchParams(location.search).get('view') ?? 'main';
document.documentElement.dataset.platform = window.firn.platform;
document.documentElement.dataset.view = view;

const LAYERS: Record<string, () => React.JSX.Element | null> = {
  floating: Floating,
  topbar: TopBar,
  peek: Peek,
};
const Root = LAYERS[view] ?? App;

// Light or dark, as the main process says (the system's setting, or the
// choice in settings); until it does, the system's.
document.documentElement.dataset.theme = matchMedia(
  '(prefers-color-scheme: dark)',
).matches
  ? 'dark'
  : 'light';
window.firn.onFrameState(({ glass, focused, dark }) => {
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  // Frosted glass behind the main window, solid while it's out of focus.
  if (view === 'main') {
    document.documentElement.classList.toggle('is-glass', glass);
    document.documentElement.classList.toggle('is-inactive', !focused);
  }
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Root />
  </StrictMode>,
);
