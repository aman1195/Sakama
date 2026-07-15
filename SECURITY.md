# Security Policy

Sakama handles **health data** — among the most sensitive categories of personal information. Treat every
defect in this area as high severity.

## Reporting

Report vulnerabilities privately to the maintainers. Do **not** open a public issue. Expect an
acknowledgement within 48 hours.

## Security model

| Control | Rule |
|---|---|
| **Data isolation** | Row Level Security on **every** user table (`auth.uid() = user_id`). This is the primary boundary. |
| **API keys** | **No provider key ever ships in the client** (OWASP M1). All LLM calls route through a Supabase Edge Function → managed AI gateway (ADR 0011). |
| **BYOK keys** | Envelope-encrypted at rest (KMS/Vault). Never returned to the device. Redacted from every log and trace. |
| **Meal photos** | Supabase Storage, per-user path, protected by storage RLS. |
| **Transport** | TLS everywhere. Keys travel in bodies/headers, never in URLs. |
| **Analytics** | No health data (weight, conditions, food logs) in analytics or crash events. |
| **Secrets** | Never committed. `.env` gitignored; compile-time obfuscation for client config. |
| **Rate limiting** | Hard per-user budgets and RPM caps enforced in the Edge Function (against `ai_usage`) + managed gateway. |

## Privacy commitments (product-level, non-negotiable)
No ads. No data selling. Users can export and delete their data. Self-hostable backend by design.
