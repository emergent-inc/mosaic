import { CollaborationSessionObject } from "./session";
import { CollaborationSessionIndexObject } from "./session-index";
import { CollaborationInboxObject } from "./inbox";
import { collaborationFetch } from "./handler";

export {
  CollaborationSessionIndexObject,
  CollaborationSessionObject,
  CollaborationInboxObject,
};

export interface Env {
  COLLABORATION_SESSIONS: DurableObjectNamespace<CollaborationSessionObject>;
  COLLABORATION_SESSION_INDEX: DurableObjectNamespace<CollaborationSessionIndexObject>;
  COLLABORATION_INBOX: DurableObjectNamespace<CollaborationInboxObject>;
  COLLABORATION_ADMIN_TOKEN?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return collaborationFetch(request, env);
  },
} satisfies ExportedHandler<Env>;
