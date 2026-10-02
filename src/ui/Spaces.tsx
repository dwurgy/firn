import { useEffect, useRef, useState } from 'react';
import type { Space, SpacesState } from '../types';
import { PlusIcon } from './icons';

// The active space's name above its tabs. Double-click it (or pick
// "Rename space" from the space's right-click menu) to rename it.
export function SpaceHeader({
  space,
  renaming,
  onRename,
  onDoneRenaming,
}: {
  space: Space | undefined;
  renaming: boolean;
  onRename: () => void;
  onDoneRenaming: () => void;
}) {
  if (!space) return null;
  return (
    <div
      className="space-header"
      onContextMenu={(e) => {
        e.preventDefault();
        window.firn.showSpaceMenu(space.id);
      }}
    >
      <span className="space-header-icon">{space.icon}</span>
      {renaming ? (
        <SpaceNameInput space={space} onDone={onDoneRenaming} />
      ) : (
        <span
          className="space-header-name"
          title="Double-click to rename"
          onDoubleClick={onRename}
        >
          {space.name}
        </span>
      )}
    </div>
  );
}

function SpaceNameInput({
  space,
  onDone,
}: {
  space: Space;
  onDone: () => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [name, setName] = useState(space.name);
  const done = useRef(false);

  useEffect(() => {
    input.current?.focus();
    input.current?.select();
  }, []);

  const finish = (save: boolean) => {
    if (done.current) return;
    done.current = true;
    if (save && name.trim() && name.trim() !== space.name)
      window.firn.updateSpace(space.id, { name });
    onDone();
  };

  return (
    <input
      ref={input}
      className="space-header-input"
      value={name}
      maxLength={40}
      spellCheck={false}
      onChange={(e) => setName(e.target.value)}
      onBlur={() => finish(true)}
      onKeyDown={(e) => {
        if (e.key === 'Enter') finish(true);
        if (e.key === 'Escape') finish(false);
      }}
    />
  );
}

// The row of space icons at the bottom of the sidebar: click to switch,
// right-click for rename / icon / delete, + for a new space.
export function SpaceSwitcher({ spaces, activeSpaceId }: SpacesState) {
  return (
    <nav className="space-switcher" aria-label="Spaces">
      {spaces.map((space, i) => (
        <button
          key={space.id}
          className={`space-dot ${space.id === activeSpaceId ? 'is-active' : ''}`}
          title={i < 9 ? `${space.name}  (Ctrl+Shift+${i + 1})` : space.name}
          onClick={() => window.firn.switchSpace(space.id)}
          onContextMenu={(e) => {
            e.preventDefault();
            window.firn.showSpaceMenu(space.id);
          }}
        >
          {space.icon}
        </button>
      ))}
      <button
        className="space-dot space-add"
        title="New space"
        onClick={() => window.firn.newSpace()}
      >
        <PlusIcon />
      </button>
    </nav>
  );
}
