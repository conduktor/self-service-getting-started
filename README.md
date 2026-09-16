# Conduktor Self-service quick start

A worked example of Conduktor Self-service you can run on a laptop. The full tutorial is
below; a narrated version lives at
[docs.conduktor.io](https://docs.conduktor.io/guide/tutorials/get-started-with-self-service).

## Why Self-service

As Kafka adoption grows, central teams hit a tradeoff: They can review every resource request properly and you become the bottleneck, or skim and allow misconfiugrations to reach production.

Access requests are even harder because the central team has to approve them without knowing whether the data is sensitive or who should see it. Approvals go through anyway, periodic reviews slip, and "who can read this topic?" turns into a multi-day search through ACLs, tickets and spreadsheets when an auditor or an incident asks. Teams that want isolation ask for their own cluster, so cluster count grows faster than the workload does.

With Conduktor Self-Service, responsibility is federated. The platform team declares **each application's owner**, **what resources it owns**, and **what rules its resources have to follow**. Application teams **create, change, share, or delete their own resources** inside those boundaries. Conduktor Self-Service validates every change at apply time against the rules, with custom error messages to tell them what to fix. Ops protects the infrastructure while the developers with business context make decisions about their data.

Moreover, having a proper ownership database turns out to be handy elsewhere in Console:

- [Stream lineage](/guide/conduktor-concepts/stream-lineage) resolves raw service account principals into named applications, so a graph of `sa-7f3a` and `svc-prod-2` becomes a graph of teams, with a view that hides everything Self-service doesn't manage.
- [Chargeback](/guide/conduktor-concepts/chargeback) rolls infrastructure cost up by application and by application instance, because it can trace usage back through the service account to the application that produced it.
- [Alerts](/guide/monitor-brokers-apps/alerts) belong to an application instance, so the team that owns a topic sees and manages the alerts on it.
- The Topic Catalog shows each topic's owner, schema, and documentation, allowing teams to maintain proper data products other teams can discover and use.

## Repository structure

```
platform/                    # Platform team resources
  clusters/                  #   KafkaCluster definitions
  groups/                    #   Console Groups, mapped from your IdP
  policies/                  #   ResourcePolicy guardrails
  applications/              #   Applications and ApplicationInstances
    website-analytics/
  exceptions/                #   Agreed policy exceptions, applied with an AdminToken
    website-analytics/<instance>/
applications/                # Application team resources
  website-analytics/
    dev/                     #   topics, subjects, connectors, groups, permissions
    prod/
```

`platform/` is managed exclusively by the platform team. `applications/<app>/<instance>/`
belongs to the application team — in a real repo, enforced with CODEOWNERS.

## What's in here

| Resource | Where | What it does |
|---|---|---|
| `KafkaCluster` | `platform/clusters/` | The Kafka endpoint applications bind to |
| `Group` | `platform/groups/` | Console Groups that own applications |
| `Application` | `platform/applications/website-analytics/application.yml` | The unit of ownership |
| `ApplicationInstance` | `platform/applications/website-analytics/{dev,prod}.yml` | Binds the application to a cluster, sets its resource boundary and its policies |
| `ResourcePolicy` | `platform/policies/` | Seven CEL guardrails on topics, subjects, connectors and application groups |
| `Topic`, `Subject` | `applications/website-analytics/<instance>/` | The resources the team manages day to day |
| `ApplicationGroup` | `applications/website-analytics/<instance>/` | Console UI permissions for team members |
| `ApplicationInstancePermission` | `applications/website-analytics/<instance>/` | Cross-team access grants |

### The policies

| Policy | Target | Description |
|---|---|---|
| `topic-naming` | Topic | Enforces `<app>.<descriptive-name>` naming |
| `topic-labels` | Topic | Requires `instance`, `business-unit`, `confidentiality`, `team` labels |
| `topic-rules-dev` | Topic | Dev rules (RF = 3, partitions 1-3) |
| `topic-rules-prod` | Topic | Strict prod rules (RF = 3, partitions <= 12, retention >= 1h, ISR >= 2) |
| `subject-rules` | Subject | Requires `-key` or `-value` suffix, explicit compatibility |
| `connector-rules` | Connector | Restricts plugin classes, `tasks.max` <= 8 |
| `appgroup-restrictions` | ApplicationGroup | No direct members, read-only prod topic access |

Policies do nothing on their own. They apply because something references them. The first
six are named by `spec.policyRef` on each ApplicationInstance; the dev and prod instances
are identical except for which topic policy they reference, and that one line is the whole
dev-versus-prod story.

`appgroup-restrictions` is referenced from `application.yml` instead. An ApplicationInstance's
`spec.policyRef` accepts only `Topic`, `Connector` and `Subject` policies — an
`ApplicationGroup` policy has to attach at the Application level, where it covers every
instance.

---

# Tutorial

## Prerequisites

Docker, and a Conduktor license. Self-service is a licensed feature: without a license
Console runs on the Free plan and rejects every Self-service API call with a 403.
[Get a license](https://www.conduktor.io/contact/demo/) if you don't have one.

## 1. Start the stack

```bash
export CDK_LICENSE=<your-license-key>
./start.sh
```

This brings up Console, a three-broker Kafka cluster, Schema Registry, Conduktor Gateway and
the Conduktor CLI, and returns once Console is ready at
[http://localhost:8080](http://localhost:8080). Log in as `admin@conduktor.io` /
`adminP4ss!` to watch resources appear as you create them.

## 2. Mint an admin token

`conduktor token create admin` logs in with `CDK_USER`/`CDK_PASSWORD` to create your first
token, so there's no key to copy out of the UI. Pass the credentials to this one command
rather than storing them anywhere:

```bash
ADMIN_TOKEN=$(docker compose exec -T \
  -e CDK_USER=admin@conduktor.io \
  -e CDK_PASSWORD='adminP4ss!' \
  conduktor-ctl conduktor token create admin quickstart)
```

`-T` matters here: without it Docker allocates a TTY and control characters end up inside
the token.

> Every command below passes its token with `-e CDK_API_KEY=...`. Don't set `CDK_USER` on
> the container alongside `CDK_API_KEY` — under `CDK_AUTH_MODE=external` the CLI refuses to
> run when both are present.

## 3. Apply the platform team's resources

Setting up the cluster, the groups, the guardrails and the application boundaries is the
platform team's job. Order matters — each step references the one before it.

```bash
# The Kafka cluster is a managed resource, not something configured by hand in the UI
docker compose exec -e CDK_API_KEY=$ADMIN_TOKEN conduktor-ctl \
  conduktor apply -f platform/clusters/

# website-analytics-owners will own the Application, so it has to exist first
docker compose exec -e CDK_API_KEY=$ADMIN_TOKEN conduktor-ctl \
  conduktor apply -f platform/groups/

# The seven guardrails
docker compose exec -e CDK_API_KEY=$ADMIN_TOKEN conduktor-ctl \
  conduktor apply -f platform/policies/

# The Application and its dev and prod instances
docker compose exec -e CDK_API_KEY=$ADMIN_TOKEN conduktor-ctl \
  conduktor apply -f platform/applications/website-analytics/
```

Open `platform/applications/website-analytics/prod.yml` and look at what an
ApplicationInstance declares:

```yaml
spec:
  cluster: "kafka-local"
  serviceAccount: "sa-website-analytics-prod"
  policyRef:                  # <-- the guardrails
    - topic-naming
    - topic-labels
    - topic-rules-prod
    - subject-rules
    - connector-rules
  resources:                  # <-- the boundary
    - type: TOPIC
      patternType: PREFIXED
      name: "website-analytics.prod."
```

`resources` is the boundary: this application instance can do what it likes to anything
matching `website-analytics.prod.`, and nothing at all outside it. `policyRef` is the
guardrail: every resource it applies is validated against those policies first.

Policies and applications are now visible in Console under **Resource Policies** and the
**Applications Catalog**. Delegation is complete — everything from here is the application
team's work.

## 4. Apply the application team's resources

```bash
docker compose exec -e CDK_API_KEY=$ADMIN_TOKEN conduktor-ctl \
  conduktor apply -f applications/website-analytics/dev/

docker compose exec -e CDK_API_KEY=$ADMIN_TOKEN conduktor-ctl \
  conduktor apply -f applications/website-analytics/prod/
```

Because these topics belong to an Application Instance, Console links them to their owner in
the Topic Catalog. That's how another team discovers who owns a topic — and requests access
as part of a pull request, rather than by asking around. It can take up to 30 seconds for
new topics to appear, depending on when the indexer last polled.

Note what the team did **not** have to do: no ticket, no central approval, no waiting.

## 5. Try something out of bounds

Everything so far used an admin token, which bypasses policy validation entirely — platform
administrators are exempt by design. To see what the application team experiences, mint a
token scoped to their application instance:

```bash
APP_TOKEN=$(docker compose exec -T -e CDK_API_KEY=$ADMIN_TOKEN conduktor-ctl \
  conduktor token create application-instance -i=website-analytics-prod prod-key)
```

The team wants a topic for a replay job, with 24 partitions. Create
`applications/website-analytics/prod/replay.yml`:

```yaml
apiVersion: kafka/v2
kind: Topic
metadata:
  cluster: "kafka-local"
  name: website-analytics.prod.replay
  labels:
    instance: prod
    business-unit: marketing
    confidentiality: internal
    team: website-analytics
spec:
  replicationFactor: 3
  partitions: 24
  configs:
    cleanup.policy: delete
    retention.ms: "604800000"
    min.insync.replicas: "2"
```

Everything about that topic is fine except the partition count, which `topic-rules-prod`
caps at 12. Apply it as the application team:

```bash
docker compose exec -e CDK_API_KEY=$APP_TOKEN conduktor-ctl \
  conduktor apply -f applications/website-analytics/prod/replay.yml
```

```
Could not apply resource Topic/website-analytics.prod.replay: Policies check failed:
- topic-rules-prod: Production topics need less than or equal to 12 partitions. If you need an exception, plead your case to the platform team.
```

The rejection carries the `errorMessage` the platform team wrote, so the developer knows
both what broke and what to do next. Failures are grouped by policy; a resource that breaks
several rules reports all of them at once.

In a real repo this happens on the pull request, not on your laptop — CI runs
`conduktor apply --dry-run` and the violation shows up as a failed check before anyone
reviews the change.

Try a few variations to get a feel for the guardrails:

- Rename the topic to `payments.replay` — `website-analytics-prod` doesn't own that prefix,
  so the boundary rejects it before any policy runs.
- Drop the `confidentiality` label — `topic-labels` rejects it.
- Apply the same topic against the **dev** instance with 24 partitions — `topic-rules-dev`
  caps dev at 3.

## 6. Grant a policy exception

The team genuinely does need 24 partitions, and the platform team agrees. Policies are
strict rather than absolute — the escape hatch is a deliberate, auditable exception.

The resource doesn't change; its *ownership* does. It moves out of the team's folder and
into `platform/exceptions/`, where only the platform team can write. That file is already in
the repo as `platform/exceptions/website-analytics/prod/high-partition-topic.yml`, with a
label recording the ticket that authorized it.

```bash
rm applications/website-analytics/prod/replay.yml

docker compose exec -e CDK_API_KEY=$ADMIN_TOKEN conduktor-ctl \
  conduktor apply -f platform/exceptions/website-analytics/prod/
```

This time it succeeds. Nothing was configured to allow it — an AdminToken simply bypasses
`ResourcePolicy` validation, which is exactly why the exception has to live in a
platform-owned directory. In a GitOps repo that directory is CODEOWNED by the platform team,
so granting an exception means a reviewed pull request with the reason recorded in the diff,
not a quietly loosened policy that every other team inherits.

## 7. Tear down

```bash
./stop.sh
```

---

## A note on dev and prod

The stack runs one Kafka cluster, so `website-analytics-dev` and `website-analytics-prod`
are two application instances on that single cluster, separated by topic prefix
(`website-analytics.dev.` and `website-analytics.prod.`). In production these would
normally be instances on genuinely separate clusters. Everything else — ownership,
boundaries, policies, permissions — works exactly the same way.

The stack also runs Conduktor Gateway, registered in `platform/clusters/gateway.yml`. The
quick start doesn't use it; it's there if you want to experiment with
[interceptors](https://docs.conduktor.io/guide/reference/gateway-reference) afterwards.

## Taking this to production

This repo is deliberately a quick start: no CI/CD, no state management, no secret
handling. For a real rollout start from
[conduktor/self-service-template](https://github.com/conduktor/self-service-template),
which uses the same `platform/` and `applications/` layout and adds GitHub Actions
workflows scoped by token type, CODEOWNERS-based review, per-instance state isolation and
OIDC-federated credentials.

## Learn more

- [Self-service concepts](https://docs.conduktor.io/guide/conduktor-concepts/self-service)
- [Self-service resource reference](https://docs.conduktor.io/guide/reference/self-service-reference)
- [Conduktor CLI](https://docs.conduktor.io/guide/conduktor-in-production/automate/cli-automation)
