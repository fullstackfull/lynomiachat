import { openDB } from 'idb';
import { DATA_VERSION, INBOX_CACHE_INVALIDATION_VERSION } from './version';

export class DataManager {
  constructor(accountId) {
    this.modelsToSync = ['inbox', 'label', 'team', 'canned_response'];
    this.accountId = accountId;
    this.db = null;
  }

  async initDb() {
    if (this.db) return this.db;
    const dbName = `cw-store-${this.accountId}`;
    this.db = await openDB(`cw-store-${this.accountId}`, DATA_VERSION, {
      upgrade(db, oldVersion, _newVersion, transaction) {
        const shouldInvalidateInboxCache =
          oldVersion > 0 && oldVersion < INBOX_CACHE_INVALIDATION_VERSION;

        if (shouldInvalidateInboxCache) {
          transaction.objectStore('inbox').clear();
          transaction.objectStore('cache-keys').delete('inbox');
        }

        // Existing databases already carry the stores added in earlier versions,
        // and createObjectStore throws on a name that is already taken.
        const createStore = (name, options) => {
          if (db.objectStoreNames.contains(name)) return;
          db.createObjectStore(name, options);
        };

        createStore('cache-keys');
        createStore('inbox', { keyPath: 'id' });
        createStore('label', { keyPath: 'id' });
        createStore('team', { keyPath: 'id' });
        createStore('canned_response', { keyPath: 'id' });
      },
    });

    // Store the database name in LocalStorage
    const dbNames = JSON.parse(localStorage.getItem('cw-idb-names') || '[]');
    if (!dbNames.includes(dbName)) {
      dbNames.push(dbName);
      localStorage.setItem('cw-idb-names', JSON.stringify(dbNames));
    }

    return this.db;
  }

  validateModel(name) {
    if (!name) throw new Error('Model name is not defined');
    if (!this.modelsToSync.includes(name)) {
      throw new Error(`Model ${name} is not defined`);
    }
    return true;
  }

  async replace({ modelName, data }) {
    this.validateModel(modelName);

    await this.db.clear(modelName);
    return this.push({ modelName, data });
  }

  // Writes upsert: two fetches of the same model can race (the sidebar and a page both refetch an invalidated cache),
  // and `add` would throw "Key already exists in the object store" on the second one and abort its transaction, leaving
  // the store empty. `put` keeps the last write and the collection intact.
  async push({ modelName, data }) {
    this.validateModel(modelName);

    if (Array.isArray(data)) {
      const tx = this.db.transaction(modelName, 'readwrite');
      data.forEach(item => {
        tx.store.put(item);
      });
      await tx.done;
    } else {
      await this.db.put(modelName, data);
    }
  }

  async get({ modelName }) {
    this.validateModel(modelName);
    return this.db.getAll(modelName);
  }

  async setCacheKeys(cacheKeys) {
    Object.keys(cacheKeys).forEach(async modelName => {
      this.db.put('cache-keys', cacheKeys[modelName], modelName);
    });
  }

  async getCacheKey(modelName) {
    this.validateModel(modelName);

    return this.db.get('cache-keys', modelName);
  }
}
