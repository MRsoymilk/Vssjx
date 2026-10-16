// Browser test instrumentation only. No fault flags/hooks exist in production.
(() => {
    globalThis.__vssjxFixtureFault = 'none';
    const originalPut = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function (...args) {
        const owned = this.name === 'saves' && this.transaction.db.name === 'vssjx-offline-v1';
        if (owned && globalThis.__vssjxFixtureFault === 'quota') {
            throw new DOMException('do-not-log-sensitive', 'QuotaExceededError');
        }
        const request = originalPut.apply(this, args);
        if (owned && globalThis.__vssjxFixtureFault === 'abort') {
            const transaction = this.transaction;
            request.addEventListener('success', () => transaction.abort());
        }
        return request;
    };
    const completion = Object.getOwnPropertyDescriptor(IDBTransaction.prototype, 'oncomplete');
    Object.defineProperty(IDBTransaction.prototype, 'oncomplete', {
        configurable: completion.configurable, enumerable: completion.enumerable,
        get: completion.get,
        set(handler) {
            const drop = this.db.name === 'vssjx-offline-v1' && this.mode === 'readwrite'
                && globalThis.__vssjxFixtureFault === 'suppress-completion';
            completion.set.call(this, drop ? null : handler);
        },
    });
})();
