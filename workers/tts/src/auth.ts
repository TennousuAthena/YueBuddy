export interface AuthResult {
  allow: boolean;
  /** Caller identity for future logging. MVP is always "anonymous". */
  subject: string;
}

/**
 * Authentication entry point. MVP intentionally allows anonymous access
 * (per plan: leave the hook, enforce later). When login is added, verify
 * Firebase Auth / Supabase JWT / App Token here and return { allow: false }
 * with the caller handling the 401 — no changes needed in the route flow.
 *
 * Reserved: clients may already send `Authorization: Bearer <token>`;
 * it is parsed (and currently ignored) so the header contract is stable.
 */
export async function authenticate(request: Request): Promise<AuthResult> {
  const header = request.headers.get("Authorization");
  void header;
  return { allow: true, subject: "anonymous" };
}
