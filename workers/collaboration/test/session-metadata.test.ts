import { expect, test } from "bun:test";
import {
  createSessionMetadata,
  deleteSessionMetadata,
  readSessionMetadata,
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

test("deleted session metadata frees the code for a later session", async () => {
  const storage = new FakeMetadataStorage();

  await createSessionMetadata(storage, "ABCDE");
  await deleteSessionMetadata(storage);
  const recreated = await createSessionMetadata(storage, "ABCDE");

  expect(await readSessionMetadata(storage)).toEqual(recreated);
  expect(recreated.sessionCode).toBe("ABCDE");
});
