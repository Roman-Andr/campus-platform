"""Administration: dictionaries, roles, dashboards and the action journal.

Public interface of the module. Other modules import only this package,
never its submodules (enforced by import-linter). Modules record their
administrative actions with :mod:`campus.core.audit`.
"""

from campus.modules.administration.audit import (
    AuditRecordOut,
    purge_audit_records,
)
from campus.modules.administration.audit import router as audit_router

__all__ = ["AuditRecordOut", "audit_router", "purge_audit_records"]
