"""Acceptance oracle transcribed from specification table <tab-roles>.

Keep this independent of campus permission code. Feature owners replace a
pending probe with an HTTP assertion when implementing its linked issue.
"""

from dataclasses import dataclass
from enum import StrEnum


class Grant(StrEnum):
    YES = "+"
    NO = "--"
    COMMUNITY = "community only"
    EXISTING_CHAT = "existing chats only"
    READ = "read only"
    SCOPE = "own scope"
    SEARCH = "search only"
    STUDENT = "student rights"
    COMPLAINT = "employee: complaints only"
    CITY = "city or university"
    OTHER_DECISION = "except own decisions"


COLUMNS = ("student", "employee", "alumni", "headman", "moderator", "administrator")
# Six explicit entries per row, in the order printed in the specification.
MATRIX = {
    "publish_respond": (
        Grant.YES,
        Grant.COMMUNITY,
        Grant.NO,
        Grant.YES,
        Grant.YES,
        Grant.YES,
    ),
    "finish_review": (Grant.YES, Grant.YES, Grant.YES, Grant.YES, Grant.YES, Grant.YES),
    "complain_dispute_appeal": (
        Grant.YES,
        Grant.YES,
        Grant.YES,
        Grant.YES,
        Grant.YES,
        Grant.YES,
    ),
    "student_feed": (
        Grant.YES,
        Grant.NO,
        Grant.NO,
        Grant.YES,
        Grant.COMPLAINT,
        Grant.YES,
    ),
    "message": (
        Grant.YES,
        Grant.YES,
        Grant.EXISTING_CHAT,
        Grant.YES,
        Grant.YES,
        Grant.YES,
    ),
    "create_club": (Grant.YES, Grant.YES, Grant.NO, Grant.YES, Grant.YES, Grant.YES),
    "forum_comment_react": (
        Grant.YES,
        Grant.YES,
        Grant.READ,
        Grant.YES,
        Grant.YES,
        Grant.YES,
    ),
    "vote": (Grant.SCOPE, Grant.SCOPE, Grant.NO, Grant.SCOPE, Grant.SCOPE, Grant.SCOPE),
    "book": (Grant.SCOPE, Grant.NO, Grant.NO, Grant.SCOPE, Grant.SCOPE, Grant.SCOPE),
    "ai": (Grant.YES, Grant.YES, Grant.SEARCH, Grant.YES, Grant.STUDENT, Grant.STUDENT),
    "follow_personal_page": (
        Grant.YES,
        Grant.YES,
        Grant.NO,
        Grant.YES,
        Grant.YES,
        Grant.YES,
    ),
    "pin": (Grant.NO, Grant.NO, Grant.NO, Grant.SCOPE, Grant.NO, Grant.CITY),
    "hide": (Grant.NO, Grant.NO, Grant.NO, Grant.SCOPE, Grant.YES, Grant.YES),
    "manage_resources": (
        Grant.NO,
        Grant.NO,
        Grant.NO,
        Grant.SCOPE,
        Grant.NO,
        Grant.YES,
    ),
    "moderate": (Grant.NO, Grant.NO, Grant.NO, Grant.NO, Grant.YES, Grant.YES),
    "review_appeal": (
        Grant.NO,
        Grant.NO,
        Grant.NO,
        Grant.NO,
        Grant.OTHER_DECISION,
        Grant.YES,
    ),
    "administrate": (Grant.NO, Grant.NO, Grant.NO, Grant.NO, Grant.NO, Grant.YES),
    "audit_dashboard_export": (
        Grant.NO,
        Grant.NO,
        Grant.NO,
        Grant.NO,
        Grant.NO,
        Grant.YES,
    ),
}

# A row can span multiple features. Keep each unavailable operation visible,
# even when another operation in the same cell already has an API probe.
PENDING = {
    "finish_review": {"complete": 59},
    "complain_dispute_appeal": {"complain": 91, "dispute": 94, "appeal": 96},
    "create_club": {"create": 142},
    "forum_comment_react": {
        "read": 144,
        "topic": 144,
        "reply": 144,
        "comment": 156,
        "react": 156,
    },
    "vote": {"own_scope": 143, "other_scope": 143},
    "book": {"own_scope": 134, "other_scope": 134},
    "ai": {"search": 112, "assistant": 113, "ai_function": 146},
    "follow_personal_page": {"follow": 156, "publish": 155},
    "pin": {"own_scope": 101, "other_scope": 101, "city": 101, "university": 101},
    "hide": {"own_scope": 93, "other_scope": 93},
    "manage_resources": {"own_scope": 135, "other_scope": 135},
    "moderate": {"complaint": 91, "dispute": 94, "block": 93, "attached_chat": 92},
    "review_appeal": {"own_decision": 96, "other_decision": 96},
    "administrate": {
        "assign_role": 210,
        "reference_data": 99,
        "domains": 99,
        "ai_settings": 117,
        "place_pages": 141,
    },
    "audit_dashboard_export": {"dashboard": 139, "export": 140},
}
LIVE = {
    "publish_respond": (
        "publish_community",
        "publish_students",
        "publish_dormitory",
        "respond_community",
        "respond_students",
    ),
    "finish_review": ("continue", "review"),
    "message": ("existing_chat", "new_chat"),
    "audit_dashboard_export": ("audit",),
    "student_feed": (
        "feed_students",
        "feed_dormitory",
        "feed_dormitory_community",
        "detail_students",
        "detail_dormitory",
        "detail_dormitory_community",
    ),
}
ALIASES = {
    "former_employee": "alumni",
    "employee_moderator": "employee",
    "employee_administrator": "employee",
}
USER_ACTIONS = tuple(MATRIX)[:11]


@dataclass(frozen=True)
class Case:
    action: str
    actor: str
    column: str
    probe: str
    grant: Grant
    issue: int | None = None

    @property
    def cell(self) -> str:
        return f"{self.action}/{self.actor}"

    @property
    def id(self) -> str:
        return f"{self.cell}/{self.probe}"


def cases() -> list[Case]:
    result: list[Case] = []
    for action, grants in MATRIX.items():
        actors = dict(zip(COLUMNS, COLUMNS, strict=True))
        if action in USER_ACTIONS:
            actors.update(ALIASES)
        for actor, column in actors.items():
            grant = grants[COLUMNS.index(column)]
            result.extend(
                Case(action, actor, column, probe, grant)
                for probe in LIVE.get(action, ())
            )
            for probe, issue in PENDING.get(action, {}).items():
                result.append(Case(action, actor, column, probe, grant, issue))
            if action == "student_feed" and actor == "employee_moderator":
                result.append(
                    Case(action, actor, column, "attached_complaint", grant, 92)
                )
    return result


# Executed regressions, not feature skips. Strict XPASS forces removal when
# the permission bug is fixed, without broadening this test-only issue.
KNOWN_FAILURES: dict[str, int] = {}
