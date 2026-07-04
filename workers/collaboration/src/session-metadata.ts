export interface SessionMetadata {
  sessionID: string;
  sessionCode: string;
}

export interface SessionMetadataStorage {
  get<T>(key: string): Promise<T | undefined>;
  put<T>(key: string, value: T): Promise<void>;
  delete(key: string): Promise<boolean>;
  transaction?<T>(closure: (txn: SessionMetadataTransaction) => Promise<T>): Promise<T>;
}

export interface SessionMetadataTransaction {
  get<T>(key: string): Promise<T | undefined>;
  put<T>(key: string, value: T): Promise<void>;
}

export interface SessionMetadataCreateResult {
  metadata: SessionMetadata;
  created: boolean;
}

const METADATA_KEY = "metadata";

export async function createSessionMetadata(
  storage: SessionMetadataStorage,
  sessionCode: string
): Promise<SessionMetadata> {
  return (await createSessionMetadataIfAbsent(storage, sessionCode)).metadata;
}

export async function createSessionMetadataIfAbsent(
  storage: SessionMetadataStorage,
  sessionCode: string
): Promise<SessionMetadataCreateResult> {
  const claim = async (txn: SessionMetadataTransaction): Promise<SessionMetadataCreateResult> => {
    const existing = await txn.get<SessionMetadata>(METADATA_KEY) ?? null;
    if (existing) return { metadata: existing, created: false };

    const metadata = {
      sessionID: sessionCode,
      sessionCode,
    };
    await txn.put(METADATA_KEY, metadata);
    return { metadata, created: true };
  };

  return storage.transaction ? storage.transaction(claim) : claim(storage);
}

export async function readSessionMetadata(storage: SessionMetadataStorage): Promise<SessionMetadata | null> {
  return await storage.get<SessionMetadata>(METADATA_KEY) ?? null;
}

export async function deleteSessionMetadata(storage: SessionMetadataStorage): Promise<void> {
  await storage.delete(METADATA_KEY);
}
