/* Trusted, packaged factory expression. No URLs, credentials or native VFS. */
(() => {
    'use strict';
    const DATABASE = 'vssjx-offline-v1';
    const STORE = 'saves';
    const SLOT = 'offline://save-v1';
    const KEY = 'save-v1';
    const MAX_BYTES = 1048576;
    const errorCode = (error, fallback) => {
        if (error?.name === 'QuotaExceededError') return 'QUOTA_EXCEEDED';
        if (['SecurityError', 'NotAllowedError'].includes(error?.name)) return 'STORAGE_DENIED';
        return fallback;
    };
    return Object.freeze({
        // Dependency injection is for bounded browser fault tests, not page config.
        create(env = globalThis, timeoutMs = 15000) {
            let database = null, state = 'uninitialized', pending = null, disposed = false;
            let retention = 'unknown';
            const encoder = new TextEncoder();
            const timeout = Number.isInteger(timeoutMs) && timeoutMs >= 10 && timeoutMs <= 60000 ? timeoutMs : 15000;
            const defer = fn => Promise.resolve().then(fn);
            const fail = code => ({ok: false, code});
            function finish(operation, result) {
                if (pending !== operation) return;
                env.clearTimeout(operation.timer);
                pending = null;
                const callback = operation.callback;
                operation.callback = null;
                defer(() => callback(JSON.stringify({id: operation.id, ...result})));
            }
            function closeDatabase() {
                if (database) database.close();
                database = null;
            }
            function updateRetention() {
                try {
                    const storage = env.navigator?.storage;
                    if (typeof storage?.persisted === 'function') {
                        Promise.resolve(storage.persisted()).then(value => {
                            if (!disposed) retention = value === true ? 'persistent' : 'best_effort';
                        }).catch(() => {});
                    }
                } catch (_) { /* Unknown retention never turns into a guarantee. */ }
            }
            function begin(id, kind, callback) {
                if (pending) {
                    defer(() => callback(JSON.stringify({id, ...fail('STORAGE_BUSY')})));
                    return null;
                }
                const operation = {id, kind, callback, timer: null, transaction: null};
                pending = operation;
                operation.timer = env.setTimeout(() => {
                    if (pending !== operation) return;
                    try { operation.transaction?.abort(); } catch (_) {}
                    state = 'failed';
                    closeDatabase();
                    finish(operation, {...fail('STORAGE_TIMEOUT'), uncertain: kind === 'write'});
                }, timeout);
                return operation;
            }
            function initialize(operation) {
                if (state === 'ready') return finish(operation, {ok: true, value: {state, retention}});
                state = 'initializing';
                closeDatabase();
                let request;
                try {
                    if (env.isSecureContext !== true) {
                        state = 'failed';
                        return finish(operation, fail('STORAGE_DENIED'));
                    }
                    if (!env.indexedDB) {
                        state = 'failed';
                        return finish(operation, fail('STORAGE_UNSUPPORTED'));
                    }
                    request = env.indexedDB.open(DATABASE, 1);
                } catch (error) {
                    state = 'failed';
                    return finish(operation, fail(errorCode(error, 'STORAGE_OPEN_FAILED')));
                }
                request.onupgradeneeded = () => {
                    if (pending !== operation) {
                        try { request.transaction.abort(); } catch (_) {}
                        return;
                    }
                    if (!request.result.objectStoreNames.contains(STORE)) request.result.createObjectStore(STORE);
                };
                request.onblocked = () => {
                    if (pending !== operation) return;
                    state = 'failed';
                    finish(operation, fail('STORAGE_BLOCKED'));
                };
                request.onerror = () => {
                    if (pending !== operation) return;
                    state = 'failed';
                    finish(operation, fail(errorCode(request.error, 'STORAGE_OPEN_FAILED')));
                };
                request.onsuccess = () => {
                    const opened = request.result;
                    if (pending !== operation || disposed) return opened.close();
                    database = opened;
                    database.onversionchange = () => {
                        opened.close();
                        if (database === opened) { database = null; state = 'closed'; }
                    };
                    state = 'ready';
                    updateRetention();
                    finish(operation, {ok: true, value: {state, retention}});
                };
            }
            function transact(operation, text, maximumBytes) {
                const writing = operation.kind === 'write';
                let transaction, request, value, present = false, failure = null;
                try {
                    // Strict durability is requested where implemented; old engines
                    // may only accept the two-argument transaction signature.
                    if (writing) {
                        try { transaction = database.transaction(STORE, 'readwrite', {durability: 'strict'}); }
                        catch (error) {
                            if (error?.name !== 'TypeError') throw error;
                            transaction = database.transaction(STORE, 'readwrite');
                        }
                    } else transaction = database.transaction(STORE, 'readonly');
                    operation.transaction = transaction;
                    const store = transaction.objectStore(STORE);
                    // A cursor distinguishes a missing key from a corrupt record
                    // explicitly containing undefined (get() conflates the two).
                    request = writing ? store.put(text, KEY) : store.openCursor(KEY);
                } catch (error) {
                    try { transaction?.abort(); } catch (_) {}
                    return finish(operation, fail(errorCode(error, writing ? 'SYNC_FAILED' : 'READ_FAILED')));
                }
                // Request success alone is NEVER a write receipt: a later abort
                // (quota/error/page termination) can still roll the transaction back.
                request.onsuccess = () => {
                    if (!writing) {
                        present = request.result !== null;
                        value = present ? request.result.value : undefined;
                    }
                };
                request.onerror = () => { failure = errorCode(request.error, writing ? 'SYNC_FAILED' : 'READ_FAILED'); };
                transaction.onabort = () => finish(operation, fail(failure || errorCode(transaction.error, writing ? 'SYNC_FAILED' : 'READ_FAILED')));
                transaction.onerror = () => { failure = failure || errorCode(transaction.error, writing ? 'SYNC_FAILED' : 'READ_FAILED'); };
                transaction.oncomplete = () => {
                    if (pending !== operation) return;
                    if (writing) {
                        return finish(operation, {ok: true, value: {written: true, durability: 'browser_sync', retention,
                            bytes: encoder.encode(text).byteLength, transaction_durability: transaction.durability || 'default'}});
                    }
                    if (!present) return finish(operation, operation.kind === 'probe' ? {ok: true, value: false} : fail('NOT_FOUND'));
                    if (typeof value !== 'string') return finish(operation, fail('INVALID_STORED_DATA'));
                    if (value.length > maximumBytes || encoder.encode(value).byteLength > maximumBytes) return finish(operation, fail('TOO_LARGE'));
                    finish(operation, {ok: true, value: operation.kind === 'probe' ? true : value});
                };
            }
            return Object.freeze({
                submit(id, kind, path, text, maximumBytes, callback) {
                    const operation = begin(id, kind, callback);
                    if (!operation) return;
                    if (disposed) return finish(operation, fail('STORAGE_CLOSED'));
                    if (kind === 'initialize') return initialize(operation);
                    if (state !== 'ready' || !database) return finish(operation, fail('STORAGE_NOT_READY'));
                    if (path !== SLOT) return finish(operation, fail('INVALID_PATH'));
                    if (!['probe', 'read', 'write'].includes(kind)) return finish(operation, fail('INVALID_OPERATION'));
                    if (!Number.isInteger(maximumBytes) || maximumBytes < 1 || maximumBytes > MAX_BYTES) return finish(operation, fail('INVALID_LIMIT'));
                    if (kind === 'write' && (typeof text !== 'string' || text.length > MAX_BYTES || encoder.encode(text).byteLength > MAX_BYTES)) return finish(operation, fail('TOO_LARGE'));
                    transact(operation, text, maximumBytes);
                },
                status_json() { return JSON.stringify({state, retention, busy: pending !== null, durability: 'indexeddb_transaction'}); },
                dispose() {
                    if (disposed) return;
                    disposed = true;
                    state = 'closed';
                    if (pending) {
                        const operation = pending;
                        try { operation.transaction?.abort(); } catch (_) {}
                        env.clearTimeout(operation.timer);
                        operation.callback = null;
                        pending = null;
                    }
                    closeDatabase();
                },
            });
        },
    });
})()
