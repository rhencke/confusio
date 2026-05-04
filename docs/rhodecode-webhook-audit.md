# RhodeCode Webhook Event Audit

This audit fixes the source of truth for the RhodeCode webhook backend work in
confusio. It was checked against RhodeCode Enterprise 5.11.4 docs on
2026-05-04.

Primary sources:

- RhodeCode
  [Webhook integration](https://docs.rhodecode.com/5.x/rce/integrations/webhook.html)
  docs for JSON POST delivery and the broad push / pull-request event surface.
- RhodeCode
  [Repository Hooks](https://docs.rhodecode.com/5.x/rce/admin/repo_admin/repo-hooks.html)
  docs for repository hook names and their trigger conditions.
- RhodeCode
  [CI Server integration](https://docs.rhodecode.com/5.x/rce/integrations/ci.html)
  docs for pull-request creation and update webhook usage by CI systems.

## Native Events

RhodeCode's webhook integration documentation describes POSTing repository push
and pull request events as JSON. Repository lifecycle events come from the
lower-level repository hook names. Confusio should register receivers for these
native sources:

| GitHub event | RhodeCode native source | Actions or variants |
| --- | --- | --- |
| `push` | `PUSH_HOOK`, `POST_PUSH` | Branch or tag update payload, no top-level GitHub action |
| `create` | `PUSH_HOOK`, `POST_PUSH` | Ref update whose old revision is all zeroes |
| `delete` | `PUSH_HOOK`, `POST_PUSH` | Ref update whose new revision is all zeroes |
| `pull_request` | Webhook pull-request event, `CREATE_PULLREQUEST_HOOK`, `CLOSE_PULLREQUEST_HOOK` | Open, update/synchronize, close/merge/reopen when those statuses are present |
| `repository` | `CREATE_REPO_HOOK`, `DELETE_REPO_HOOK` | `created`, `deleted` |

## Mapping Notes

- RhodeCode has no GitHub-style issues, labels, milestones, stars, releases,
  packages, discussions, checks, Actions, deployments, or code scanning webhook
  families in the documented native integration surface.
- Push, create, and delete are all ref-event variants. The payload shape decides
  whether confusio emits GitHub's `push`, `create`, or `delete` family.
- Repository webhook coverage is lifecycle-only. GitHub actions such as
  `renamed`, `publicized`, `privatized`, `archived`, `unarchived`,
  `transferred`, and `edited` should remain unsupported unless a real RhodeCode
  source is identified.
- Pull request webhooks should be treated as lifecycle/synchronization events.
  RhodeCode code review does not expose a separate reviewer-vote,
  review-submission, or review-comment webhook family in the documented native
  integration surface.

## Non-Native Events

All other GitHub webhook families in the catalog should remain `n` for
RhodeCode until a real native source is found and covered by fixtures. In
particular, do not map CI integration calls to GitHub Actions or Checks events:
RhodeCode can call external CI systems, but the documented webhook integration
does not emit CI run/job/status result events back to confusio.
