// Shapes shared between the main process, the preload bridge and the UI.

export interface NavState {
  url: string;
  title: string;
  canGoBack: boolean;
  canGoForward: boolean;
  isLoading: boolean;
}

export type NavCommand = 'back' | 'forward' | 'reload' | 'stop';

// The narrow API the preload script exposes to Firn's UI as `window.firn`.
export interface FirnBridge {
  platform: string;
  navigate(input: string): void;
  command(command: NavCommand): void;
  ready(): void;
  onNavState(listener: (state: NavState) => void): () => void;
  onFocusAddress(listener: () => void): () => void;
}
