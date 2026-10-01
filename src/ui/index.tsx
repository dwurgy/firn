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

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Root />
  </StrictMode>,
);
