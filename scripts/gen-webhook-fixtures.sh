#!/usr/bin/env bash
# Generate webhook fixture files.
#
# Two generation modes:
#
# 1. Cross-backend aliases: test/fixtures/webhooks/gitea/ is the canonical
#    template source (hand-maintained, committed).  Alias backends share the
#    same payload format because they are API-compatible with Gitea.  Their
#    fixture directories are produced by piping each template through jq.
#
#    Generated directories (relative to test_dir):
#      fixtures/webhooks/forgejo/
#
# 2. Within-backend variants: some fixture files are derived from a sibling
#    file in the same backend directory via a small jq transformation.  The
#    source file is hand-maintained and committed; the derived file is
#    gitignored.
#
#    Table format: backend|src_file|dst_file|jq-filter
#    The filter is applied to <backend>/<src_file> → <backend>/<dst_file>.
#
# Usage:
#   scripts/gen-webhook-fixtures.sh [test_dir]
#
#   test_dir  path to the test/ directory (default: test)

set -euo pipefail

TEST_DIR="${1:-test}"
FIXTURES="$TEST_DIR/fixtures/webhooks"

if [ ! -d "$FIXTURES/gitea" ]; then
  echo "ERROR: template directory not found: $FIXTURES/gitea" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Within-backend variants
#
# Run this BEFORE the cross-backend alias step so that all generated gitea/
# files exist when forgejo is derived from gitea.
#
# Table format: backend|src_file|dst_file|jq-filter
# The filter is applied to <backend>/<src_file> → <backend>/<dst_file>.
# ---------------------------------------------------------------------------
while IFS='|' read -r backend src dst filter; do
  srcpath="$FIXTURES/$backend/$src"
  dstpath="$FIXTURES/$backend/$dst"
  if [ ! -f "$srcpath" ]; then
    echo "WARNING: source not found, skipping: $srcpath" >&2
    continue
  fi
  jq "$filter" "$srcpath" > "$dstpath"
  echo "gen-webhook-fixtures: $backend/$dst (from $src)"
done <<'VARIANTS'
gitea|create.json|delete.json|.ref = "old-branch"
gitbucket|create.json|delete.json|.ref = "stale-branch"
gitlab|create.json|delete.json|.before = "95790bf891e76fee5db5ef17d2523a6f6e048239" | .after = "0000000000000000000000000000000000000000" | .ref = "refs/heads/stale-branch" | .checkout_sha = null
pagure|create.json|delete.json|.msg.branch = "refs/heads/stale-branch" | .msg.start_commit = "95790bf891e76fee5db5ef17d2523a6f6e048239" | .msg.end_commit = "0000000000000000000000000000000000000000"
azuredevops|create.json|delete.json|.resource.refUpdates[0].name = "refs/heads/stale-branch" | .resource.refUpdates[0].oldObjectId = "95790bf891e76fee5db5ef17d2523a6f6e048239" | .resource.refUpdates[0].newObjectId = "0000000000000000000000000000000000000000" | .resource.pushId = 3 | .createdDate = "2024-01-15T12:00:00Z"
bitbucket_datacenter|create.json|delete.json|.changes[0].ref.id = "refs/heads/stale-branch" | .changes[0].ref.displayId = "stale-branch" | .changes[0].refId = "refs/heads/stale-branch" | .changes[0].fromHash = "95790bf891e76fee5db5ef17d2523a6f6e048239" | .changes[0].toHash = "0000000000000000000000000000000000000000" | .changes[0].type = "DELETE"
gitea|issues-opened.json|issues-closed.json|.action = "closed" | .issue.state = "closed" | .issue.updated = "2024-01-15T10:02:00Z" | .issue.closed = "2024-01-15T10:02:00Z" | .sender.login = "octocat"
gitea|issues-opened.json|issues-reopened.json|.action = "reopened" | .issue.updated = "2024-01-15T10:03:00Z" | .sender.login = "octocat"
gitea|issues-opened.json|issues-assigned.json|.action = "assigned" | .issue.body = null | .issue.assignees = [{"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}] | .issue.updated = "2024-01-15T10:03:00Z" | .assignee = {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
gitea|issues-opened.json|issues-edited.json|.action = "edited" | .issue.title = "Bug report (edited)" | .issue.body = "Updated description" | .issue.updated = "2024-01-15T10:01:00Z" | .changes = {"title": {"from": "Bug report"}, "body": {"from": "Something is broken"}}
gitea|issues-opened.json|issues-labeled.json|.action = "labeled" | .issue.body = null | .issue.labels = [{"id": 5, "name": "bug", "color": "#d73a4a", "url": ""}] | .issue.updated = "2024-01-15T10:01:00Z" | .label = {"id": 5, "name": "bug", "color": "#d73a4a", "url": ""}
gitea|issues-opened.json|issues-unlabeled.json|.action = "unlabeled" | .issue.body = null | .issue.updated = "2024-01-15T10:02:00Z" | .label = {"id": 5, "name": "bug", "color": "#d73a4a", "url": ""}
gitea|issues-opened.json|issues-unassigned.json|.action = "unassigned" | .issue.body = null | .issue.updated = "2024-01-15T10:04:00Z" | .assignee = {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
gitea|milestone-created.json|milestone-closed.json|.action = "closed" | .milestone.state = "closed" | .milestone.closed_issues = 5 | .milestone.updated_at = "2024-06-01T10:00:00Z" | .milestone.closed_at = "2024-06-01T10:00:00Z" | .sender.login = "octocat"
gitea|milestone-created.json|milestone-deleted.json|.action = "deleted" | .milestone.description = null | .milestone.due_on = null
gitea|milestone-created.json|milestone-edited.json|.action = "edited" | .milestone.title = "v2.1" | .milestone.description = "Version 2.1 release" | .milestone.due_on = "2024-07-01T00:00:00Z" | .milestone.updated_at = "2024-01-16T10:00:00Z" | .changes = {"title": {"from": "v2.0"}}
gitea|milestone-created.json|milestone-reopened.json|.action = "reopened" | .milestone.open_issues = 2 | .milestone.closed_issues = 3 | .milestone.due_on = "2024-09-01T00:00:00Z" | .milestone.updated_at = "2024-07-01T10:00:00Z" | .sender.login = "octocat"
gitea|label-created.json|label-deleted.json|.action = "deleted"
gitea|label-created.json|label-edited.json|.action = "edited" | .label.color = "#0075ca" | .changes = {"color": {"from": "#a2eeef"}}
gitea|issue_comment-created.json|issue_comment-deleted.json|.action = "deleted"
gitea|issue_comment-created.json|issue_comment-edited.json|.action = "edited" | .comment.body = "Confirmed, I can reproduce this. (edited)" | .comment.updated = "2024-01-15T11:05:00Z" | .changes = {"body": {"from": "Confirmed, I can reproduce this."}}
gitea|pull_request_review_comment-created.json|pull_request_review_comment-deleted.json|.action = "deleted" | .pull_request.updated = "2024-01-15T11:20:00Z"
gitea|pull_request_review_comment-created.json|pull_request_review_comment-edited.json|.action = "edited" | .comment.body = "Please simplify this. (edited)" | .comment.updated_at = "2024-01-15T11:10:00Z" | .changes = {"body": {"from": "Please simplify this."}} | .pull_request.updated = "2024-01-15T11:10:00Z"
gitea|workflow_run-requested.json|workflow_run-in_progress.json|.action = "in_progress" | .workflow_run.status = "in_progress" | .workflow_run.updated_at = "2024-01-15T11:01:00Z"
gitea|release-published.json|release-edited.json|.action = "edited" | .release.name = "Release 1.0.0 (updated)" | .release.body = "Updated notes"
gitea|release-published.json|release-deleted.json|.action = "deleted"
gitea|deploy_key-created.json|deploy_key-deleted.json|.action = "deleted"
gitea|member-added.json|member-removed.json|.action = "deleted"
gitea|gollum-created.json|gollum-edited.json|.pages[0].action = "edited"
gitea|repository-created.json|repository-deleted.json|.action = "deleted"
gitea|repository-created.json|repository-renamed.json|.action = "renamed" | .repository.name = "hello-universe" | .repository.full_name = "octocat/hello-universe" | .changes = {"name": {"from": "hello-world"}}
gitea|release-published.json|release-prereleased.json|.action = "prereleased" | .release.id = 2 | .release.tag_name = "v2.0.0-rc.1" | .release.name = "Release 2.0.0 RC 1" | .release.body = "Release candidate" | .release.prerelease = true | .release.html_url = "http://localhost/octocat/hello-world/releases/tag/v2.0.0-rc.1" | .release.tarball_url = "http://localhost/octocat/hello-world/archive/v2.0.0-rc.1.tar.gz" | .release.zipball_url = "http://localhost/octocat/hello-world/archive/v2.0.0-rc.1.zip" | .release.created_at = "2024-02-01T10:00:00Z" | .release.published_at = "2024-02-01T10:00:00Z"
gitbucket|issues-opened.json|issues-closed.json|.action = "closed" | .issue.state = "closed" | .issue.updated_at = "2024-01-15T11:00:00Z" | .issue.closed_at = "2024-01-15T11:00:00Z" | .sender.id = 2 | .sender.login = "bob"
gitbucket|issues-opened.json|issues-edited.json|.action = "edited" | .issue.title = "Bug report (updated)" | .issue.body = "Something is broken \u2014 updated description" | .issue.updated_at = "2024-01-15T10:30:00Z"
gitbucket|issues-opened.json|issues-reopened.json|.action = "reopened" | .issue.updated_at = "2024-01-15T12:00:00Z" | .sender.id = 2 | .sender.login = "bob"
gitbucket|issues-opened.json|issues-assigned.json|.action = "assigned" | .issue.assignees = [{"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}] | .issue.updated_at = "2024-01-15T10:10:00Z" | .assignee = {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
gitbucket|issues-opened.json|issues-labeled.json|.action = "labeled" | .issue.labels = [{"id": 5, "name": "bug", "color": "d73a4a"}] | .issue.updated_at = "2024-01-15T10:05:00Z" | .label = {"id": 5, "name": "bug", "color": "d73a4a"} | .sender.id = 2 | .sender.login = "bob"
gitbucket|issues-opened.json|issues-unlabeled.json|.action = "unlabeled" | .issue.updated_at = "2024-01-15T10:07:00Z" | .label = {"id": 5, "name": "bug", "color": "d73a4a"} | .sender.id = 2 | .sender.login = "bob"
gitbucket|milestone-created.json|milestone-closed.json|.action = "closed" | .milestone.state = "closed" | .milestone.closed_issues = 5 | .milestone.updated_at = "2024-02-28T12:00:00Z" | .milestone.closed_at = "2024-02-28T12:00:00Z" | .sender.id = 2 | .sender.login = "bob"
gitbucket|milestone-created.json|milestone-edited.json|.action = "edited" | .milestone.title = "v1.0 Final" | .milestone.description = "First stable release (updated)" | .milestone.open_issues = 2 | .milestone.closed_issues = 3 | .milestone.due_on = "2024-03-15T00:00:00Z" | .milestone.updated_at = "2024-01-20T09:00:00Z"
gitbucket|label-created.json|label-deleted.json|.action = "deleted" | .label.color = "0075ca"
gitbucket|label-created.json|label-edited.json|.action = "edited" | .label.color = "0075ca" | .changes = {"color": {"from": "a2eeef"}, "name": {"from": "enhancement"}}
gitbucket|issue_comment-created.json|issue_comment-deleted.json|.action = "deleted" | .issue.updated_at = "2024-01-15T10:25:00Z"
gitbucket|issue_comment-created.json|issue_comment-edited.json|.action = "edited" | .issue.updated_at = "2024-01-15T10:20:00Z" | .comment.body = "I can reproduce this too. (edited)" | .comment.updated_at = "2024-01-15T10:20:00Z"
gitbucket|pull_request_review-submitted.json|pull_request_review-dismissed.json|.action = "dismissed" | .review.state = "DISMISSED" | .review.body = "Review dismissed." | .pull_request.updated_at = "2024-01-15T14:00:00Z" | .sender.id = 1 | .sender.login = "alice"
gitbucket|deploy_key-created.json|deploy_key-deleted.json|.action = "deleted"
gitbucket|gollum-created.json|gollum-edited.json|.pages[0].action = "edited"
gitbucket|release-published.json|release-edited.json|.action = "edited" | .release.name = "Release 1.0.0 (edited)" | .release.body = "First release (edited)" | .changes = {}
gitbucket|release-published.json|release-deleted.json|.action = "deleted"
gitbucket|repository-created.json|repository-deleted.json|.action = "deleted"
gitbucket|code_scanning_alert-created.json|code_scanning_alert-fixed.json|.action = "fixed" | .alert.state = "fixed" | .alert.updated_at = "2024-01-16T08:00:00Z"
gitbucket|dependabot_alert-created.json|dependabot_alert-dismissed.json|.action = "dismissed" | .alert.state = "dismissed" | .alert.dismissed_at = "2024-01-16T10:00:00Z" | .alert.dismissed_reason = "tolerable_risk" | .alert.dismissed_comment = "Risk accepted." | .alert.updated_at = "2024-01-16T10:00:00Z" | .sender.id = 2 | .sender.login = "bob"
gitbucket|secret_scanning_alert-created.json|secret_scanning_alert-resolved.json|.action = "resolved" | .alert.state = "resolved" | .alert.resolution = "false_positive" | .alert.resolved_by = {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""} | .alert.resolved_at = "2024-01-16T09:00:00Z" | .alert.updated_at = "2024-01-16T09:00:00Z" | .sender.id = 2 | .sender.login = "bob"
gitbucket|security_advisory-published.json|security_advisory-withdrawn.json|.action = "withdrawn" | .security_advisory.withdrawn_at = "2024-01-16T12:00:00Z" | .security_advisory.updated_at = "2024-01-16T12:00:00Z"
gitbucket|repository_advisory-published.json|repository_advisory-reported.json|.action = "reported" | .repository_advisory.state = "reported" | .repository_advisory.updated_at = "2024-01-16T11:00:00Z"
gitbucket|repository_vulnerability_alert-create.json|repository_vulnerability_alert-dismiss.json|.action = "dismiss" | .alert.dismisser = {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""} | .alert.dismiss_reason = "tolerable_risk" | .alert.dismissed_at = "2024-01-16T10:00:00Z" | .sender.id = 2 | .sender.login = "bob"
gitbucket|member-added.json|member-removed.json|.action = "removed" | .sender.id = 2 | .sender.login = "bob"
gitlab|issues-opened.json|issues-closed.json|.object_attributes.state = "closed" | .object_attributes.action = "close" | .object_attributes.updated_at = "2024-01-15T10:01:00Z" | .object_attributes.closed_at = "2024-01-15T10:01:00Z"
gitlab|issues-opened.json|issues-edited.json|.object_attributes.title = "Found a bug (updated)" | .object_attributes.description = "Something broke, with more details." | .object_attributes.action = "update" | .object_attributes.updated_at = "2024-01-15T10:03:00Z"
gitlab|issues-opened.json|issues-reopened.json|.object_attributes.action = "reopen" | .object_attributes.updated_at = "2024-01-15T10:02:00Z"
gitlab|label-created.json|label-edited.json|.object_attributes.title = "bug (renamed)" | .object_attributes.action = "update" | .object_attributes.updated_at = "2024-01-15T12:01:00Z"
gitlab|milestone-created.json|milestone-closed.json|.object_attributes.state = "closed" | .object_attributes.action = "close" | .object_attributes.updated_at = "2024-01-15T13:01:00Z" | .object_attributes.closed_at = "2024-01-15T13:01:00Z"
gitlab|milestone-created.json|milestone-opened.json|.object_attributes.action = "reopen" | .object_attributes.updated_at = "2024-01-15T13:02:00Z"
gitlab|milestone-created.json|milestone-edited.json|.object_attributes.title = "v1.0 (updated)" | .object_attributes.description = "First major release" | .object_attributes.action = "update" | .object_attributes.due_date = "2024-04-01" | .object_attributes.updated_at = "2024-01-15T13:03:00Z"
gitlab|issue_comment-created.json|issue_comment-deleted.json|.object_attributes.note = "This comment was deleted." | .object_attributes.action = "destroy" | .object_attributes.updated_at = "2024-01-15T11:02:00Z"
gitlab|issue_comment-created.json|issue_comment-edited.json|.object_attributes.note = "This is an edited comment." | .object_attributes.action = "update" | .object_attributes.updated_at = "2024-01-15T11:01:00Z"
gitlab|pull_request_review-submitted.json|pull_request_review-dismissed.json|.object_attributes.action = "unapproved" | .object_attributes.updated_at = "2024-01-15T15:01:00Z"
gitlab|workflow_run-requested.json|workflow_run-in_progress.json|.object_attributes.status = "running" | .object_attributes.started_at = "2024-01-15T16:01:00Z"
gitlab|workflow_run-requested.json|workflow_run-completed.json|.object_attributes.status = "success" | .object_attributes.started_at = "2024-01-15T16:01:00Z" | .object_attributes.finished_at = "2024-01-15T16:05:00Z"
gitlab|workflow_job-queued.json|workflow_job-in_progress.json|.build_status = "running" | .build_started_at = "2024-01-15T16:01:30Z"
gitlab|workflow_job-queued.json|workflow_job-completed.json|.build_status = "success" | .build_started_at = "2024-01-15T16:01:30Z" | .build_finished_at = "2024-01-15T16:03:00Z"
gitlab|release-published.json|release-edited.json|.action = "update" | .description = "First release (updated)"
gitlab|release-published.json|release-deleted.json|.action = "delete"
bitbucket|issues-opened.json|issues-closed.json|.issue.state = "resolved" | .issue.updated_on = "2024-01-15T12:00:00+00:00" | .changes = {"status": {"old": "open", "new": "resolved"}}
bitbucket|issues-opened.json|issues-edited.json|.issue.title = "Found a bug (updated)" | .issue.updated_on = "2024-01-15T11:00:00+00:00" | .changes = {}
bitbucket|issues-opened.json|issues-reopened.json|.issue.updated_on = "2024-01-15T13:00:00+00:00" | .changes = {"status": {"old": "resolved", "new": "open"}}
bitbucket|status-created-success.json|status-updated-pending.json|.commit_status.description = "Build in progress." | .commit_status.state = "INPROGRESS" | .commit_status.url = "https://ci.example.com/build/43" | .commit_status.updated_on = "2024-01-15T10:10:00+00:00"
bitbucket_datacenter|status-created-success.json|status-updated-pending.json|.buildStatus.state = "INPROGRESS" | .buildStatus.url = "https://ci.example.com/build/43" | .buildStatus.description = "Build in progress." | .buildStatus.updatedDate = 1705313400000
gerrit|comment-added-approved.json|comment-added-changes_requested.json|.change.updated = "2024-01-15T11:30:00Z" | .comment = "This needs more work. -2" | .approvals[0].value = "-2"
harness|pipeline_execution_started.json|pipeline_execution_success.json|.eventType = "pipeline_execution_success" | .endTs = 1705313400000
harness|stage_execution_started.json|stage_execution_success.json|.eventType = "stage_execution_success" | .endTs = 1705313300000
gitlab|deployment_status-created-success.json|deployment_status-created-failed.json|.status = "failed" | .status_changed_at = "2024-01-15T16:06:00Z"
azuredevops|repository-created.json|repository-deleted.json|.eventType = "git.repository.deleted"
azuredevops|repository-created.json|repository-renamed.json|.eventType = "git.repository.renamed" | .resource.name = "hello-universe"
gitlab|wiki_page-created.json|wiki_page-edited.json|.object_attributes.action = "update"
gitlab|repository-created.json|repository-deleted.json|.event_name = "project_destroy"
gitlab|repository-created.json|repository-renamed.json|.event_name = "project_rename" | .name = "hello-universe" | .path = "hello-universe" | .path_with_namespace = "octocat/hello-universe" | .old_path_with_namespace = "octocat/hello-world"
gitlab|repository-created.json|repository-transferred.json|.event_name = "project_transfer" | .path_with_namespace = "newowner/hello-world" | .old_path_with_namespace = "octocat/hello-world"
gitlab|repository-created.json|repository-publicized.json|.event_name = "project_update" | .project_visibility = "public"
gitlab|repository-created.json|repository-privatized.json|.event_name = "project_update" | .project_visibility = "private"
gitlab|member-added.json|member-removed.json|.action = "removed"
VARIANTS

# ---------------------------------------------------------------------------
# 2. Cross-backend aliases: derive forgejo/ from gitea/
#
# Must run AFTER step 1 so that all generated gitea/ files exist and get
# copied into forgejo/ as well.
# ---------------------------------------------------------------------------
for backend in forgejo; do
  out_dir="$FIXTURES/$backend"
  mkdir -p "$out_dir"
  for src in "$FIXTURES/gitea"/*.json; do
    name=$(basename "$src")
    jq '.' "$src" > "$out_dir/$name"
  done
  count=$(ls "$out_dir"/*.json | wc -l | tr -d ' ')
  echo "gen-webhook-fixtures: $backend ($count files)"
done
