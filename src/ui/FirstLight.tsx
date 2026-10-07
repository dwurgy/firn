import { useEffect, useState } from 'react';

// "First light": sunrise in a snowy cabin. Cool glacier sky high, warm
// sunrise low, snow at the bottom. Used by the welcome (the whole scene)
// and the empty page (just the snow and a glow). See CLAUDE.md for the
// rules; everything here is plain gradients and one SVG, and the only
// motion is opacity and transform.

// The five snow bands (the website's snow layers), drawn in a 1280-wide
// box from y=600 down; stretched to the window's width.
const SNOW_BANDS = [
  'M0,200 L0,26.6 C106.7,26.6 106.7,42.3 213.3,42.3 C320,42.3 320,33.3 426.7,33.3 C533.3,33.3 533.3,45.3 640,45.3 C746.7,45.3 746.7,46.4 853.3,46.4 C960,46.4 960,17.8 1066.7,17.8 C1173.3,17.8 1173.3,15.1 1280,15.1 L1280,200 Z',
  'M0,200 L0,76.2 C106.7,76.2 106.7,81.2 213.3,81.2 C320,81.2 320,97.9 426.7,97.9 C533.3,97.9 533.3,76.8 640,76.8 C746.7,76.8 746.7,78.8 853.3,78.8 C960,78.8 960,82.4 1066.7,82.4 C1173.3,82.4 1173.3,63.9 1280,63.9 L1280,200 Z',
  'M0,200 L0,121.8 C106.7,121.8 106.7,126.7 213.3,126.7 C320,126.7 320,128.9 426.7,128.9 C533.3,128.9 533.3,134.9 640,134.9 C746.7,134.9 746.7,126.6 853.3,126.6 C960,126.6 960,134.1 1066.7,134.1 C1173.3,134.1 1173.3,97.5 1280,97.5 L1280,200 Z',
  'M0,200 L0,152.8 C106.7,152.8 106.7,163 213.3,163 C320,163 320,168.5 426.7,168.5 C533.3,168.5 533.3,144.5 640,144.5 C746.7,144.5 746.7,161.5 853.3,161.5 C960,161.5 960,159.3 1066.7,159.3 C1173.3,159.3 1173.3,157.8 1280,157.8 L1280,200 Z',
  'M0,200 L0,191.7 C106.7,191.7 106.7,192.3 213.3,192.3 C320,192.3 320,190.8 426.7,190.8 C533.3,190.8 533.3,170.1 640,170.1 C746.7,170.1 746.7,183.2 853.3,183.2 C960,183.2 960,178.8 1066.7,178.8 C1173.3,178.8 1173.3,181.6 1280,181.6 L1280,200 Z',
];

function SnowLayer({ tint, fresh }: { tint: string | null; fresh: boolean }) {
  return (
    <svg
      className={`fl-snow-layer${tint ? ' is-tinted' : ''}${fresh ? ' is-fresh' : ''}`}
      style={tint ? ({ '--tint': tint } as React.CSSProperties) : undefined}
      viewBox="0 0 1280 200"
      preserveAspectRatio="none"
      aria-hidden
    >
      {SNOW_BANDS.map((d) => (
        <path key={d} d={d} />
      ))}
    </svg>
  );
}

// The snow: glacier blues, or (with a tint) the space's color mixed into
// the page. A new tint cross-fades in over the old one (400ms).
export function Snow({ tint }: { tint: string | null }) {
  const [layers, setLayers] = useState([{ tint, id: 0 }]);
  useEffect(() => {
    setLayers((all) => {
      const last = all[all.length - 1];
      if (last.tint === tint) return all;
      return [...all.slice(-1), { tint, id: last.id + 1 }];
    });
  }, [tint]);
  // Once the new one has faded in, the old one goes.
  useEffect(() => {
    if (layers.length < 2) return;
    const timer = setTimeout(() => setLayers((all) => all.slice(-1)), 450);
    return () => clearTimeout(timer);
  }, [layers]);
  return (
    <div className="fl-snow" aria-hidden>
      {layers.map((layer, i) => (
        <SnowLayer key={layer.id} tint={layer.tint} fresh={i > 0} />
      ))}
    </div>
  );
}

// Four small flakes drifting in the sky, placed away from the text
// (left/top as parts of the window, size in px, turn in degrees).
const FLAKES = [
  { left: 11.7, top: 17.5, size: 30, turn: -12, delay: 0 },
  { left: 85.9, top: 13.8, size: 22, turn: 18, delay: -6 },
  { left: 81.3, top: 41.3, size: 14, turn: 0, delay: -12 },
  { left: 17.2, top: 52.5, size: 14, turn: 40, delay: -3 },
];

// The welcome's whole backdrop, back to front: sky, sun, flakes, whatever
// rises from behind the snow (children), snow, paper grain. The content
// sits on top of all of it.
export function Scene({
  tint,
  children,
}: {
  tint: string | null;
  children?: React.ReactNode;
}) {
  return (
    <div className="fl-scene" aria-hidden>
      <div className="fl-sky" />
      <div className="fl-sun" />
      {FLAKES.map((f) => (
        <span
          key={f.left}
          className="fl-flake"
          style={
            {
              left: `${f.left}%`,
              top: `${f.top}%`,
              width: f.size,
              height: f.size,
              '--turn': `${f.turn}deg`,
              animationDelay: `${f.delay}s`,
            } as React.CSSProperties
          }
        />
      ))}
      {children}
      <Snow tint={tint} />
      <div className="fl-grain" />
    </div>
  );
}
