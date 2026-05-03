# Gitea Webhook Event Audit

This audit fixes the source of truth for the Gitea webhook backend work in
confusio.  It was checked against Gitea upstream `main` at
`134e86c78c4c9f356c5853be5149778c8e61160f` on 2026-05-02.

Primary sources:

- Gitea
  [`modules/webhook/type.go`](https://github.com/go-gitea/gitea/blob/134e86c78c4c9f356c5853be5149778c8e61160f/modules/webhook/type.go)
  for selectable webhook event types and wire event names.
- Gitea
  [`modules/structs/hook.go`](https://github.com/go-gitea/gitea/blob/134e86c78c4c9f356c5853be5149778c8e61160f/modules/structs/hook.go)
  for payload action constants and payload shapes.
- Gitea
  [`services/webhook/notifier.go`](https://github.com/go-gitea/gitea/blob/134e86c78c4c9f356c5853be5149778c8e61160f/services/webhook/notifier.go)
  for the code paths that actually enqueue webhook deliveries.
- Gitea
  [webhook docs](https://docs.gitea.com/1.26/usage/repository/webhooks)
  for `X-Gitea-Event` and `X-Gitea-Signature` delivery headers.

## Wire Events

Gitea stores several fine-grained trigger toggles, but `HookEventType.Event()`
collapses related toggles to the value sent in `X-Gitea-Event`.  Confusio should
register receivers for these native wire events:

| Wire event | Native trigger types | Actions or variants |
| --- | --- | --- |
| `create` | `create` | Branch or tag creation, no top-level action |
| `delete` | `delete` | Branch or tag deletion, no top-level action |
| `fork` | `fork` | Repository fork, no top-level action |
| `push` | `push` | Branch/tag push payload, no top-level action |
| `issues` | `issues`, `issue_assign`, `issue_label`, `issue_milestone` | `opened`, `closed`, `reopened`, `edited`, `deleted`, `assigned`, `unassigned`, `label_updated`, `label_cleared`, `milestoned`, `demilestoned` |
| `issue_comment` | `issue_comment`, `pull_request_comment` | `created`, `edited`, `deleted`; payload marks PR comments with `is_pull` and may include `pull_request` |
| `pull_request` | `pull_request`, `pull_request_assign`, `pull_request_label`, `pull_request_milestone`, `pull_request_sync`, `pull_request_review_request` | `opened`, `closed`, `reopened`, `edited`, `deleted`, `assigned`, `unassigned`, `label_updated`, `label_cleared`, `milestoned`, `demilestoned`, `synchronized`, `review_requested`, `review_request_removed` |
| `pull_request_approved` | `pull_request_review_approved` | Review payload with action `reviewed` and review type `pull_request_review_approved` |
| `pull_request_rejected` | `pull_request_review_rejected` | Review payload with action `reviewed` and review type `pull_request_review_rejected` |
| `pull_request_comment` | `pull_request_review_comment` | Review payload with action `reviewed` and review type `pull_request_review_comment` |
| `wiki` | `wiki` | `created`, `edited`, `deleted` |
| `repository` | `repository` | `created`, `deleted` |
| `release` | `release` | `published`, `updated`, `deleted` |
| `package` | `package` | `created`, `deleted` |
| `status` | `status` | Commit status state: `pending`, `success`, `error`, or `failure` |
| `workflow_run` | `workflow_run` | Gitea Actions run status converted to the payload action |
| `workflow_job` | `workflow_job` | Gitea Actions job status converted to the payload action |

`pull_request_review` and `schedule` exist as internal constants, but they are
not returned by `AllEvents()` and are not separate native wire events in the
current upstream source.  Review activity is delivered as the three
`pull_request_*` wire events listed above.

## Confusio Mapping Notes

- Gitea issue and pull-request label actions use `label_updated` and
  `label_cleared`; the GitHub-shaped output should map them to `labeled` and
  `unlabeled`.
- Gitea issue and pull-request milestone changes use `milestoned` and
  `demilestoned`; the compatibility matrix should only mark GitHub milestone
  rows as supported when the emitted shape is intentionally mapped.
- Gitea release updates use action `updated`; GitHub's nearest release action is
  `edited`.
- Gitea wiki deliveries use wire event `wiki`; GitHub's equivalent webhook
  family is `gollum`.
- Gitea pull request review events are not delivered under
  `pull_request_review`; they arrive as `pull_request_approved`,
  `pull_request_rejected`, or `pull_request_comment`.
- Repository webhook deliveries only expose `created` and `deleted` natively in
  current upstream.  Rows such as repository rename/public/private transitions
  should remain unsupported for Gitea unless a real source is added.

## Non-Native Events

The current upstream Gitea source does not expose native repository webhooks for
GitHub-only families such as `discussion`, `discussion_comment`, `deploy_key`,
`label`, `member`, `merge_group`, `milestone`, `ping`,
`security_and_analysis`, `star`, or `watch`.  If confusio accepts any of these
for Gitea-family aliases, the compatibility matrix should distinguish that from
native Gitea coverage.
