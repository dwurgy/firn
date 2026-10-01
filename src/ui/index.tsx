import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import { Floating } from './Floating';
import './styles.css';

// The same UI code runs in two layers; `?view=` says which one this is.
const view = new URLSearchParams(location.search).get('view') ?? 'main';
document.documentElement.dataset.platform = window.firn.platform;
document.documentElement.dataset.view = view;

const Root = view === 'floating' ? Floating : App;

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Root />
  </StrictMode>,
);
