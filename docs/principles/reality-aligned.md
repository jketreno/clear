# [R] Reality-Aligned — Your Domain Model Must Match Business Reality

> If your understanding of how the system should work doesn't match reality, AI generates mountains of plausible-but-wrong code. Precise models → correct implementations. Fuzzy models → convincing mistakes.

---

## The Problem

Many systems don't have a single source of truth. They have:

- A database schema (what's stored)
- An API spec (what's served)
- A frontend model (what's displayed)
- An external system (Stripe, Salesforce, Auth0) that actually decides state
- Someone's head (what the team thinks the rules are)

When these conflict, AI picks one — often the wrong one. Generated code that disagrees with reality isn't caught by tests (because the tests were written against the same wrong assumption).

The solution: **declare one source of truth per domain concept, and derive everything from it**.

---

## The Three-Question Diagnostic

For any domain concept, answer:
1. **Where is it defined?** (where the schema / type lives)
2. **Where is it validated?** (where inputs are checked)
3. **Where is it enforced?** (where the rule actually has teeth)

If those three answers point to different places → you have drift.

**Example — Subscription:**
- Defined: local database schema
- Validated: backend API handler
- Enforced: Stripe

If Stripe says the subscription is cancelled but your local DB says it's active, what's true? Stripe is — because Stripe controls what you can actually charge. Your local DB is wrong. Anyone who reads the local DB is getting wrong information.

---

## Declaring Sources of Truth

In `clear/autonomy.yml`, add a `sources_of_truth` section:

```yaml
sources_of_truth:
  - concept: "Subscription"
    source_of_truth: "Stripe"
    defined_in: "stripe.subscriptions"
    note: |
      If local DB and Stripe disagree, Stripe is correct.
      Sync jobs run hourly. Webhooks handle real-time updates.

  - concept: "User"
    source_of_truth: "database schema"
    defined_in: "schema.prisma (or schema.sql)"
    note: |
      The Prisma schema is the canonical User definition.
      API response types are derived from it.

  - concept: "Permissions"
    source_of_truth: "protobuf definitions"
    defined_in: "proto/auth/permissions.proto"
    note: |
      The permission flags in the proto are authoritative.
      All other representations derive from proto generation.

  - concept: "Product catalog"
    source_of_truth: "Stripe"
    defined_in: "stripe.products, stripe.prices"
    note: |
      Product names, descriptions, and prices are managed in Stripe.
      Local cache is read-only and must sync before display.
```

AI tools are configured to read this section before generating code for any declared concept. They derive from the source, not from existing code.

---

## Writing Reality Tests

Reality tests verify that your local implementation actually matches the external source of truth. They catch drift before it becomes institutionalized.

**Key properties of reality tests:**
- Run in staging or nightly CI — not on every PR
- Fetch from the real external system (mocked locally = no value)
- Guard with `if (NODE_ENV !== 'staging') throw` to prevent production data access
- Compare normalized representations (timestamps, sorted arrays, etc.)

See `templates/skills/reality-test.md` for complete examples for Stripe and database schemas.

**Where to put them:**
```
tests/
  reality/              ← Reality tests live here
    stripe-subscriptions.reality.test.ts
    db-schema.reality.test.ts
    permissions.reality.test.ts
```

**How to run them:**
```bash
# In package.json
"test:reality": "jest tests/reality/ --testPathPattern='reality'"

# In nightly CI (not verify-ci.sh daily check)
npm run test:reality
```

---

## Reality Test Examples

### Stripe subscription alignment

```typescript
test('local subscription status matches Stripe', async () => {
  const stripeSub = await stripe.subscriptions.retrieve(testSubId);
  const local = await getSubscription(testSubId);
  
  expect(local?.status).toBe(stripeSub.status);
  expect(local?.cancelAtPeriodEnd).toBe(stripeSub.cancel_at_period_end);
  // Don't compare timestamps directly — minor sync lag is expected
});
```

### Database schema alignment

```sql
-- tests/reality/schema.reality.test.sql
-- Run with: psql $DATABASE_URL -f tests/reality/schema.reality.test.sql
-- Fails if expected columns are missing

DO $$
BEGIN
  ASSERT (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'email'
  ) = 1, 'users.email column must exist';
  
  ASSERT (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_name = 'subscriptions' AND column_name = 'stripe_id'
  ) = 1, 'subscriptions.stripe_id column must exist';
END $$;
```

### External API contract alignment

```typescript
test('API response matches declared OpenAPI schema', async () => {
  const response = await apiClient.get('/users/me');
  const schema = loadOpenApiSchema('openapi.yml', '/users/me', 'get', '200');
  
  // Validate the actual response against the spec
  const result = validateAgainstJsonSchema(response.data, schema);
  expect(result.valid).toBe(true);
  expect(result.errors).toHaveLength(0);
});
```

---

## Using AI to Detect Existing Drift

Ask your AI to run the three-question diagnostic on a domain concept:

```
Run the CLEAR reality-alignment diagnostic on our Subscription model:
1. Find where Subscription is defined in our codebase
2. Find where subscription data is validated
3. Find where subscription state is actually enforced (Stripe? local DB? middleware?)

List any discrepancies you find between these three places.
Report locations where Subscription fields exist in one place but not another.
```

The AI will surface mismatches you might not have noticed.

---

## When Systems Conflict

Add explicit conflict-resolution rules to `clear/autonomy.yml`:

```yaml
sources_of_truth:
  - concept: "User email"
    source_of_truth: "Auth0"
    defined_in: "auth0.users[email]"
    conflict_resolution: |
      Auth0 is the canonical email source.
      Our DB stores a cached copy for performance.
      If they differ, schedule a sync job — never update Auth0 from our DB.
```

AI tools read this and apply the correct resolution when generating sync logic, webhook handlers, or data migration code.

---

## Practical Starting Point

Pick ONE domain concept this week:

1. Name it (User, Order, Subscription, Permission, Product)
2. Answer the three questions (defined where, validated where, enforced where)
3. Declare the source of truth in `clear/autonomy.yml`
4. Write one reality test that would fail if drift occurs
5. Add that test to your nightly CI

That's it. One concept, one test, one declaration. It takes an hour and creates a permanent protection.

---

## Measuring Success

You know [R] is working when:
- New developers can find the source of truth for any domain concept in 30 seconds
- "Which one is right?" debates about mismatched data have a clear answer
- Drift between external services and local models is caught automatically, not by customers
- AI-generated code for a domain concept is consistently correct because it's derived from a declared source
