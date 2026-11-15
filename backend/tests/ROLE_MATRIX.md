# Role × action acceptance matrix

Run from `backend/` with the usual PostgreSQL/Redis testcontainers setup:

```sh
uv run pytest tests/test_role_action_matrix.py
```

`role_action_matrix.py` transcribes all 18 rows and six columns of the
specification's `tab-roles` table independently of production permissions.
The completeness test has its own row/column inventory. Test IDs identify
the row, actor and probe. Former employees use the alumni column; employee
moderators and administrators use the employee column in user scenarios.
Until #73 adds account status transitions, fixtures seed the future account
types directly after signing in and completing a real profile.

Each probe either calls an existing API or has a feature issue and a pytest
skip. Compound rows keep outstanding operations visible even when another
operation already has API coverage. Scope restrictions have own/other scope
probes; existing chats, reading, search, decisions and audiences have probes
for both sides of their exceptions. Unimplemented scope probes stay skipped
until their feature supplies the endpoint and fixture. Existing scope
primitives are separately exercised by `test_roles.py`.

Visibility probes assert feed membership and direct access (404 for hidden
resources), because a feed returns 200 even when it correctly hides an item.
Mutations require exact successful statuses or 403 Problem Details. Known
permission defects have issue-linked strict xfails: they execute requests,
and an unexpected pass fails until the marker is removed. No permissions
are implemented or mocked by this suite.

Dormitory visibility probes cover both student and community audiences
and assert the audience and scope of the created listing. Issue #99 skips
refer to administrative reference-data/domain operations, not the existing
public lookup GETs. An OpenAPI guard rejects these skips once a matching
administrative read or write endpoint is registered.

When implementing a linked feature, move its probe from `PENDING` to `LIVE`,
add the API assertion and remove the skip. Role assignment (#210) now has
the live `administrate/assign_role` probe: the administrator assigns a
moderator and gets 201, every other column gets 403. Preserve both sides of
each restriction. Remove entries from `KNOWN_FAILURES` when fixing the
corresponding regression.

The pytest terminal summary counts distinct canonical cells separately from
alias cells. It lists checked and marked columns per row and their issue
numbers. A partially implemented cell appears in both counts; this does not
claim full coverage of that cell. Filtered runs summarize only executed or
skipped probes, so use the full command above for acceptance evidence.
