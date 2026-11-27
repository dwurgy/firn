// Firn's page translation, reading and writing the page (PageText.swift).
// Runs only in Firn's own content world, so the page can't see it, call it,
// or change it. Everything it reads is the page's (hostile) text; everything
// it writes goes in as plain text (text nodes, textContent, document.title),
// never as HTML.
//
// A *unit* is one stretch of a block to translate whole: plain text and
// simple inline elements (a link, bold), cut at anything else (a br, a
// picture, a nested block). Each inline element is a numbered piece; the
// translation says where each piece goes, and the element itself (the
// page's own node, with its address and listeners) moves there.
if (!globalThis.firnPageText) {
    const INLINE = new Set(['A', 'ABBR', 'B', 'BDI', 'BDO', 'CITE', 'DATA', 'DEL', 'DFN', 'EM', 'FONT', 'I',
        'INS', 'LABEL', 'MARK', 'Q', 'S', 'SMALL', 'SPAN', 'STRONG', 'SUB', 'SUP', 'TIME', 'U', 'VAR',
        'CODE', 'KBD', 'SAMP', 'TT']);
    // Never translated, and never looked inside.
    const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'PRE', 'TEXTAREA', 'INPUT', 'SELECT',
        'OPTION', 'OPTGROUP', 'SVG', 'MATH', 'IFRAME', 'FRAME', 'OBJECT', 'EMBED', 'CANVAS', 'VIDEO',
        'AUDIO', 'HEAD', 'TITLE', 'META', 'LINK']);
    // Inline, but kept exactly as they are (moved with the sentence).
    const KEEP = new Set(['CODE', 'KBD', 'SAMP', 'TT']);
    const MAX_UNITS = 4000, MAX_RUNS = 100, MAX_RUN = 4000, MAX_TOTAL = 400000, MAX_DEPTH = 250;
    const LETTER = /\p{L}/u;

    const state = { units: [], title: null, titleWritten: null, written: new Set() };
    // Each translated block's own lang, as it was, to put back.
    let langs = new Map();

    const isKept = (el) => {
        if (KEEP.has(el.tagName)) return true;
        if (el.classList && el.classList.contains('notranslate')) return true;
        const t = el.getAttribute && el.getAttribute('translate');
        return t !== null && t.toLowerCase() === 'no';
    };
    const isSkipped = (el) => {
        if (SKIP.has(el.tagName.toUpperCase())) return true;
        if (el.isContentEditable) return true;
        if (el.classList && el.classList.contains('notranslate')) return true;
        const t = el.getAttribute('translate');
        return t !== null && t.toLowerCase() === 'no';
    };
    // An inline element holding only text: its words translate.
    const isSimple = (el) => {
        for (const n of el.childNodes) {
            if (n.nodeType !== Node.TEXT_NODE) return false;
        }
        return true;
    };
    // An inline element holding only inline elements and text (bold in a
    // link): it travels whole, untranslated.
    const isInlineOnly = (el, depth) => {
        if (depth > 20) return false;
        for (const n of el.children) {
            if (!INLINE.has(n.tagName) || SKIP.has(n.tagName) || !isInlineOnly(n, depth + 1)) return false;
        }
        return true;
    };

    let total = 0;
    let full = false;

    function finish(block, nodes) {
        if (full || nodes.length === 0) return;
        const runs = [];
        const pieces = [];
        let letters = false;
        let size = 0;
        for (const n of nodes) {
            let run;
            if (n.nodeType === Node.TEXT_NODE) {
                run = { k: -1, t: n.data, fixed: false };
            } else {
                const fixed = isKept(n) || !isSimple(n);
                run = { k: pieces.length, t: n.textContent, fixed: fixed };
                pieces.push({ el: n, fixed: fixed, text: fixed ? null : Array.from(n.childNodes) });
            }
            if (run.t.length > MAX_RUN) return;
            if (!run.fixed && LETTER.test(run.t)) letters = true;
            size += run.t.length;
            runs.push(run);
        }
        if (!letters || runs.length > MAX_RUNS) return;
        if (state.units.length >= MAX_UNITS || total + size > MAX_TOTAL) { full = true; return; }
        total += size;
        const parent = nodes[0].parentNode;
        const top = block.getBoundingClientRect ? block.getBoundingClientRect().top + window.scrollY : 0;
        state.units.push({
            id: state.units.length, block: block, parent: parent, nodes: nodes,
            after: nodes[nodes.length - 1].nextSibling, pieces: pieces, current: null,
            out: { id: state.units.length, top: isFinite(top) ? top : 0, runs: runs }
        });
    }

    function visit(el, depth) {
        if (full || depth > MAX_DEPTH) return;
        let nodes = [];
        for (const n of Array.from(el.childNodes)) {
            if (n.nodeType === Node.TEXT_NODE) {
                nodes.push(n);
            } else if (n.nodeType !== Node.ELEMENT_NODE) {
                finish(el, nodes); nodes = [];
            } else if (INLINE.has(n.tagName) && !n.isContentEditable
                && (isKept(n) || isSimple(n) || isInlineOnly(n, 0))) {
                nodes.push(n);
            } else if (isSkipped(n)) {
                finish(el, nodes); nodes = [];
            } else {
                finish(el, nodes); nodes = [];
                visit(n, depth + 1);
            }
        }
        finish(el, nodes);
    }

    function restore() {
        let count = 0;
        for (const id of state.written) {
            const u = state.units[id];
            if (!u.current) continue;
            for (const n of u.current) if (n.parentNode === u.parent) u.parent.removeChild(n);
            for (const n of u.nodes) u.parent.insertBefore(n, u.after && u.after.parentNode === u.parent ? u.after : null);
            for (const p of u.pieces) {
                if (p.fixed) continue;
                while (p.el.firstChild) p.el.removeChild(p.el.firstChild);
                for (const n of p.text) p.el.appendChild(n);
            }
            u.current = null;
            count += 1;
        }
        state.written.clear();
        for (const [b, old] of langs) {
            if (old === null) b.removeAttribute('lang'); else b.setAttribute('lang', old);
        }
        langs = new Map();
        if (state.titleWritten !== null && document.title === state.titleWritten) document.title = state.title;
        state.titleWritten = null;
        return count;
    }

    // Checks a translation's runs against its unit: every piece exactly
    // once, plain runs strings, nothing oversized.
    function checked(u, runs) {
        if (!Array.isArray(runs) || runs.length === 0 || runs.length > MAX_RUNS * 2) return null;
        const seen = new Set();
        const out = [];
        for (const r of runs) {
            if (!r || typeof r.t !== 'string' || typeof r.k !== 'number' || r.t.length > MAX_RUN * 3) return null;
            if (r.k === -1) { out.push(r); continue; }
            if (!Number.isInteger(r.k) || r.k < 0 || r.k >= u.pieces.length || seen.has(r.k)) return null;
            seen.add(r.k);
            out.push(r);
        }
        return seen.size === u.pieces.length ? out : null;
    }

    function write(input) {
        if (!input || !Array.isArray(input.units)) return 0;
        const lang = typeof input.lang === 'string' && /^[A-Za-z0-9-]{1,35}$/.test(input.lang) ? input.lang : null;
        let count = 0;
        for (const t of input.units) {
            const u = t && Number.isInteger(t.id) ? state.units[t.id] : null;
            if (!u || u.current) continue;
            const runs = checked(u, t.runs);
            if (!runs) continue;
            // The page may have moved things since they were read.
            if (!u.nodes.every((n) => n.parentNode === u.parent)) continue;
            if (u.after && u.after.parentNode !== u.parent) continue;
            const made = [];
            for (const r of runs) {
                if (r.k === -1) { made.push(document.createTextNode(r.t)); continue; }
                const p = u.pieces[r.k];
                if (!p.fixed) p.el.textContent = r.t;
                made.push(p.el);
            }
            for (const n of u.nodes) if (n.nodeType === Node.TEXT_NODE) u.parent.removeChild(n);
            for (const n of made) u.parent.insertBefore(n, u.after);
            u.current = made;
            state.written.add(u.id);
            if (lang && !langs.has(u.block) && u.block !== document.body) {
                langs.set(u.block, u.block.getAttribute('lang'));
                u.block.setAttribute('lang', lang);
            }
            count += 1;
        }
        if (typeof input.title === 'string' && input.title.length > 0 && input.title.length <= 1000) {
            if (state.title === null) state.title = document.title;
            document.title = input.title;
            state.titleWritten = document.title;
        }
        return count;
    }

    function read() {
        restore();
        state.units = []; state.title = document.title; state.titleWritten = null;
        total = 0; full = false;
        if (document.body) visit(document.body, 0);
        let sample = '';
        for (const u of state.units) {
            if (sample.length > 2000) break;
            for (const r of u.out.runs) if (!r.fixed) sample += r.t;
            sample += '\n';
        }
        return {
            lang: String(document.documentElement.getAttribute('lang') || ''),
            title: String(document.title || ''),
            sample: sample.slice(0, 3000),
            units: state.units.map((u) => u.out)
        };
    }

    globalThis.firnPageText = { read: read, write: write, restore: restore };
}
