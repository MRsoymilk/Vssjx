/* Packaged factory: live editing only. Never uses storage, networking or HTML interpolation. */
(() => {
    'use strict';
    return Object.freeze({create(callback) {
        const canvas = document.getElementById('canvas');
        const fields = new Map();
        let disposed = false, focusing = 0;
        const codepoints = (value, offset) => Array.from(value.slice(0, offset)).length;
        const utf16 = (value, offset) => Array.from(value).slice(0, offset).join('').length;
        const send = (...args) => {if (!disposed) callback(...args);};
        function commit(state) {
            if (disposed || fields.get(state.id) !== state || state.composing || !state.meta.editable) return;
            const input = state.input;
            send('input', state.id, input.value, codepoints(input.value, input.selectionStart || 0),
                codepoints(input.value, input.selectionEnd || 0));
        }
        function place(state) {
            const box = canvas.getBoundingClientRect(), meta = state.meta;
            const input = state.input;
            input.style.left = `${box.left + meta.x * box.width}px`;
            input.style.top = `${box.top + meta.y * box.height}px`;
            input.style.width = `${Math.max(1, meta.w * box.width)}px`;
            input.style.height = `${Math.max(1, meta.h * box.height)}px`;
            input.style.fontSize = `${Math.max(16, meta.font * box.width)}px`;
            // Inactive fields remain Godot-rendered, so DOM never covers another game panel.
            const active = meta.focused && meta.editable;
            input.style.opacity = active ? '1' : '0';
            input.style.pointerEvents = active ? 'auto' : 'none';
            input.tabIndex = meta.editable ? 0 : -1;
            input.setAttribute('aria-hidden', meta.editable ? 'false' : 'true');
        }
        function reposition() {
            if (disposed) return;
            const height = window.visualViewport?.height || window.innerHeight;
            document.documentElement.style.setProperty('--game-visible-height', `${height}px`);
            fields.forEach(place);
        }
        function create(meta) {
            const input = document.createElement('input');
            const state = {id: meta.id, meta, input, composing: false, compositionKey: false};
            input.dataset.vssjxInput = meta.id;
            input.dataset.fieldName = meta.name;
            input.autocomplete = 'off';
            input.autocapitalize = 'none';
            input.setAttribute('autocorrect', 'off');
            input.spellcheck = false;
            input.enterKeyHint = meta.name === 'ChatInput' ? 'send' : (meta.secret ? 'go' : 'done');
            Object.assign(input.style, {position: 'fixed', zIndex: '100', boxSizing: 'border-box',
                background: 'transparent', border: 'none', borderRadius: '0', padding: '0 5px', margin: '0',
                outline: 'none', fontFamily: 'sans-serif', lineHeight: 'normal', minWidth: '0', minHeight: '0'});
            input.addEventListener('focus', () => {
                if (!focusing && fields.get(state.id) === state) send('focus', state.id);
            });
            input.addEventListener('blur', () => {
                // Godot briefly focuses its canvas when disabling its own IME timer.
                queueMicrotask(() => {
                    if (!disposed && fields.get(state.id) === state && document.activeElement !== input) send('blur', state.id);
                });
            });
            input.addEventListener('compositionstart', event => {state.composing = true; event.stopPropagation();});
            input.addEventListener('compositionupdate', event => event.stopPropagation());
            input.addEventListener('compositionend', event => {
                event.stopPropagation();
                state.composing = false;
                commit(state);
            });
            input.addEventListener('input', event => {
                event.stopPropagation();
                if (!event.isComposing) commit(state);
            });
            input.addEventListener('select', () => commit(state));
            input.addEventListener('keyup', event => {
                event.stopPropagation();
                if (!state.composing) state.compositionKey = false;
                commit(state);
            });
            input.addEventListener('keydown', event => {
                event.stopPropagation(); // Text and WASD must never drive the world together.
                if (state.composing || event.isComposing || event.keyCode === 229) {
                    state.compositionKey = true;
                    return; // The IME must receive its own candidate-confirming Enter.
                }
                if (event.key === 'Enter') {
                    if (state.compositionKey) return;
                    event.preventDefault();
                    commit(state);
                    send('submit', state.id);
                } else if (event.key === 'Escape') {
                    event.preventDefault();
                    send('escape', state.id);
                }
            });
            document.body.appendChild(input);
            fields.set(meta.id, state);
            return state;
        }
        function focus(id, selectAll) {
            const state = fields.get(id);
            if (!state?.meta.editable) return;
            focusing++;
            try {
                state.input.focus({preventScroll: true});
                if (selectAll) state.input.select();
            } finally {focusing--;}
        }
        function touchFocus() {
            // iOS requires focus within the actual trusted touch-ending event.
            for (const state of fields.values()) {
                if (state.meta.focused && state.meta.editable) {send('focus', state.id); break;}
            }
        }
        function internalBlur(event) {
            // Canvas -> native field is still game focus. Otherwise Godot treats the
            // keyboard handoff as leaving the game and immediately releases LineEdit.
            if (event.target === canvas && event.relatedTarget?.dataset.vssjxInput) event.stopImmediatePropagation();
        }
        window.addEventListener('blur', internalBlur, true);
        window.addEventListener('resize', reposition);
        window.visualViewport?.addEventListener('resize', reposition);
        window.visualViewport?.addEventListener('scroll', reposition);
        canvas.addEventListener('touchend', touchFocus);
        canvas.addEventListener('mouseup', touchFocus);
        reposition();
        return Object.freeze({
            update(json, value) {
                if (disposed) return;
                const meta = JSON.parse(json);
                const state = fields.get(meta.id) || create(meta);
                const input = state.input;
                state.meta = meta;
                const type = meta.secret ? 'password' : 'text';
                if (input.type !== type) input.type = type;
                input.readOnly = !meta.editable;
                input.placeholder = meta.placeholder;
                input.setAttribute('aria-label', meta.label);
                input.style.color = '#' + meta.color;
                input.style.caretColor = '#' + meta.color;
                if (!state.composing && input.value !== value) {
                    input.value = value;
                    input.setSelectionRange(utf16(value, meta.start), utf16(value, meta.end));
                }
                place(state);
            },
            focus,
            blur(id) {const state = fields.get(id); if (state && document.activeElement === state.input) state.input.blur();},
            composing(id) {return fields.get(id)?.composing === true;},
            remove(id) {
                const state = fields.get(id);
                if (!state) return;
                fields.delete(id);
                state.input.value = '';
                state.input.remove();
            },
            dispose() {
                disposed = true;
                fields.forEach(state => {state.input.value = ''; state.input.remove();});
                fields.clear();
                window.removeEventListener('resize', reposition);
                window.removeEventListener('blur', internalBlur, true);
                window.visualViewport?.removeEventListener('resize', reposition);
                window.visualViewport?.removeEventListener('scroll', reposition);
                canvas.removeEventListener('touchend', touchFocus);
                canvas.removeEventListener('mouseup', touchFocus);
                callback = null;
            },
        });
    }});
})()
