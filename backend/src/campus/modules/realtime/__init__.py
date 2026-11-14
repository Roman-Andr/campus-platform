"""Realtime channels of the service.

Public interface of the module. Other modules import only this package,
never its submodules (enforced by import-linter).

Chat modules project their membership here: ``grant_chat_access`` in the
transaction that adds a member, ``revoke_chat_access`` in the transaction
that removes one. Realtime then issues subscription tokens from the live
grant and force-unsubscribes the user through the outbox. Session revocation
disconnects the user's connections through the identity event contract.
"""

# Importing registers the outbox and session-revocation handlers.
from campus.modules.realtime import consumers as _consumers  # noqa: F401
from campus.modules.realtime.api import router
from campus.modules.realtime.channels import (
    Channel,
    ChannelKind,
    can_access,
    chat_channel,
    grant_chat_access,
    parse_channel,
    personal_channel,
    revoke_chat_access,
)
from campus.modules.realtime.models import ChannelGrant
from campus.modules.realtime.publish import publish_personal
from campus.modules.realtime.tokens import connection_token, subscription_token

__all__ = [
    "Channel",
    "ChannelGrant",
    "ChannelKind",
    "can_access",
    "chat_channel",
    "connection_token",
    "grant_chat_access",
    "parse_channel",
    "personal_channel",
    "publish_personal",
    "revoke_chat_access",
    "router",
    "subscription_token",
]
