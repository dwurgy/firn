import { useEffect, useRef } from 'react';

// Follows the pointer for the length of a drag, from the press to the
// release, wherever it goes. (Listening on the window rather than on the
// thing pressed: a drag outlives redraws that can make the pressed element
// lose hold of the pointer, e.g. when the page makes room for a tab
// dragged over it.) Call the returned function on the press.
export function useFollowPointer(
  move: (e: PointerEvent) => void,
  end: (commit: boolean) => void,
) {
  const latest = useRef({ move, end });
  latest.current = { move, end };
  const stop = useRef<(() => void) | null>(null);
  useEffect(() => () => stop.current?.(), []);
  return () => {
    stop.current?.();
    const onMove = (e: PointerEvent) => latest.current.move(e);
    const onUp = () => {
      cleanup();
      latest.current.end(true);
    };
    const onCancel = () => {
      cleanup();
      latest.current.end(false);
    };
    const cleanup = () => {
      removeEventListener('pointermove', onMove);
      removeEventListener('pointerup', onUp);
      removeEventListener('pointercancel', onCancel);
      stop.current = null;
    };
    addEventListener('pointermove', onMove);
    addEventListener('pointerup', onUp);
    addEventListener('pointercancel', onCancel);
    stop.current = cleanup;
  };
}
