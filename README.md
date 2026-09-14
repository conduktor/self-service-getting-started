# Conduktor Self-service quick start

A worked example of Conduktor Self-service you can run on a laptop. It accompanies the
[Self-service quick start](https://docs.conduktor.io/guide/tutorials/get-started-with-self-service)
guide on docs.conduktor.io.

The idea behind Self-service: the **platform team** defines boundaries — which application
owns which resources, and what rules those resources have to follow. **Application teams**
then manage their own topics, schemas and permissions inside those boundaries, without
filing a ticket. Guardrails replace gatekeeping.

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

Policies do nothing on their own. They apply because `spec.policyRef` on each
ApplicationInstance names them. The dev and prod instances are identical except for which
topic policy they reference — that one line is the whole dev-versus-prod story.

## Running it

Docker is required. So is a Conduktor license: Self-service is a licensed feature, and
without one Console runs on the Free plan and rejects every Self-service API call.
[Get a license](https://www.conduktor.io/contact/demo/) if you don't have one.

```bash
export CDK_LICENSE=<your-license-key>
./start.sh
```

Console comes up at [http://localhost:8080](http://localhost:8080). Log in as
`admin@conduktor.io` / `adminP4ss!`.

Then follow the [quick start guide](https://docs.conduktor.io/guide/tutorials/get-started-with-self-service),
which walks through applying the platform resources, applying the application team's
resources, and watching a policy reject a topic that breaks the rules.

Tear down with `./stop.sh`.

### A note on dev and prod

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
which adds GitHub Actions workflows scoped by token type, CODEOWNERS-based review,
per-instance state isolation and OIDC-federated credentials.

## Learn more

- [Self-service concepts](https://docs.conduktor.io/guide/conduktor-concepts/self-service)
- [Self-service resource reference](https://docs.conduktor.io/guide/reference/self-service-reference)
- [Conduktor CLI](https://docs.conduktor.io/guide/conduktor-in-production/automate/cli-automation)
