"""Personal chats with reliable, ordered and deduplicated delivery.

Public interface of the module. Other modules import only this package,
never its submodules (enforced by import-linter).
"""

# Importing registers the outbox handler that publishes committed messages
# and the cleanup jobs for archived messages and empty chats.
from campus.modules.chat import consumers as _consumers  # noqa: F401
from campus.modules.chat import retention as _retention  # noqa: F401
from campus.modules.chat.api import router
from campus.modules.chat.models import (
    PERSONAL_KIND,
    Chat,
    ChatMember,
    ChatMessage,
    ChatMessageArchive,
    ChatMessageDedup,
    ChatMessageHistory,
    ChatMessageSnapshot,
)
from campus.modules.chat.service import (
    MESSAGE_TOPIC,
    check_link,
    create_personal_chat,
    leave_chat,
    post_message,
    require_membership,
    snapshot_message,
)

__all__ = [
    "MESSAGE_TOPIC",
    "PERSONAL_KIND",
    "Chat",
    "ChatMember",
    "ChatMessage",
    "ChatMessageArchive",
    "ChatMessageDedup",
    "ChatMessageHistory",
    "ChatMessageSnapshot",
    "check_link",
    "create_personal_chat",
    "leave_chat",
    "post_message",
    "require_membership",
    "router",
    "snapshot_message",
]
