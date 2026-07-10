import { CollaborationSessionObject } from "./session";
import { CollaborationSessionIndexObject } from "./session-index";
import { CollaborationInboxObject } from "./inbox";
import { TeamSessionsObject } from "./team-sessions";
import { collaborationFetch } from "./handler";

export {
  CollaborationSessionIndexObject,
  CollaborationSessionObject,
  CollaborationInboxObject,
  TeamSessionsObject,
};

export interface Env {
  COLLABORATION_SESSIONS: DurableObjectNamespace<CollaborationSessionObject>;
  COLLABORATION_SESSION_INDEX: DurableObjectNamespace<CollaborationSessionIndexObject>;
  COLLABORATION_INBOX: DurableObjectNamespace<CollaborationInboxObject>;
  TEAM_SESSIONS: DurableObjectNamespace<TeamSessionsObject>;
  TEAM_SESSION_TRANSCRIPTS: R2Bucket;
  COLLABORATION_ADMIN_TOKEN?: string;
  MOSAIC_COLLAB_GRANT_SECRET?: string;
  COLLABORATION_REQUIRE_GRANT?: string;
  MOSAIC_NATIVE_AUTH_SECRET?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return collaborationFetch(request, env);
  },
} satisfies ExportedHandler<Env>;
