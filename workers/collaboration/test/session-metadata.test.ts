import { expect, test } from "bun:test";
import {
  createSessionMetadata,
  createSessionMetadataIfAbsent,
  deleteSessionMetadata,
  readSessionMetadata,
  type SessionMetadataTransaction,
  type SessionMetadataStorage,
} from "../src/session-metadata";

class FakeMetadataStorage implements SessionMetadataStorage {
  values = new Map<string, unknown>();

  async get<T>(key: string): Promise<T | undefined> {
    return this.values.get(key) as T | undefined;
  }

  async put<T>(key: string, value: T): Promise<void> {
    this.values.set(key, value);
  }

  async delete(key: string): Promise<boolean> {
    return this.values.delete(key);
  }
}

class TransactionalMetadataStorage extends FakeMetadataStorage {
  transactionCount = 0;

  async transaction<T>(closure: (txn: SessionMetadataTransaction) => Promise<T>): Promise<T> {
    this.transactionCount += 1;
    return closure({
      get: this.get.bind(this),
      put: this.put.bind(this),
    });
  }
}

test("created session metadata is available to a later join instance", async () => {
  const storage = new FakeMetadataStorage();

  const created = await createSessionMetadata(storage, "ABCDE");
  const loadedByFreshInstance = await readSessionMetadata(storage);

  expect(loadedByFreshInstance).toEqual(created);
  expect(loadedByFreshInstance?.sessionCode).toBe("ABCDE");
});

test("creating an existing session reuses its metadata", async () => {
  const storage = new FakeMetadataStorage();

  const first = await createSessionMetadata(storage, "ABCDE");
  const second = await createSessionMetadata(storage, "ABCDE");

  expect(second).toEqual(first);
});

test("metadata claim reports only the first create as new", async () => {
  const storage = new FakeMetadataStorage();

  const first = await createSessionMetadataIfAbsent(storage, "5ZNHGF9P");
  const duplicate = await createSessionMetadataIfAbsent(storage, "5ZNHGF9P");

  expect(first).toEqual({
    metadata: {
      sessionID: "5ZNHGF9P",
      sessionCode: "5ZNHGF9P",
    },
    created: true,
  });
  expect(duplicate).toEqual({
    metadata: first.metadata,
    created: false,
  });
});

test("metadata claim uses storage transaction when available", async () => {
  const storage = new TransactionalMetadataStorage();

  const first = await createSessionMetadataIfAbsent(storage, "1Z0OIF9P");
  const duplicate = await createSessionMetadataIfAbsent(storage, "1Z0OIF9P");

  expect(storage.transactionCount).toBe(2);
  expect(first.created).toBe(true);
  expect(duplicate.created).toBe(false);
  expect(duplicate.metadata).toEqual(first.metadata);
});

test("metadata claim does not overwrite an existing session code", async () => {
  const storage = new TransactionalMetadataStorage();

  const first = await createSessionMetadataIfAbsent(storage, "FIRST001");
  const duplicate = await createSessionMetadataIfAbsent(storage, "SECOND02");

  expect(first.created).toBe(true);
  expect(duplicate).toEqual({
    metadata: first.metadata,
    created: false,
  });
  expect(await readSessionMetadata(storage)).toEqual(first.metadata);
});

test("deleted session metadata frees the code for a later session", async () => {
  const storage = new FakeMetadataStorage();

  await createSessionMetadata(storage, "ABCDE");
  await deleteSessionMetadata(storage);
  const recreated = await createSessionMetadata(storage, "ABCDE");

  expect(await readSessionMetadata(storage)).toEqual(recreated);
  expect(recreated.sessionCode).toBe("ABCDE");
});
