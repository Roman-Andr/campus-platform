"""Personal and group chats with reliable, ordered and deduplicated delivery.

Public interface of the module. Other modules import only this package,
never its submodules (enforced by import-linter).
"""

# Importing registers the outbox handler that publishes committed messages
# and the cleanup jobs for archived messages and empty chats.
from campus.modules.chat import consumers as _consumers  # noqa: F401
from campus.modules.chat import retention as _retention  # noqa: F401
from campus.modules.chat.api import router
from campus.modules.chat.groups import sync_group_chat
from campus.modules.chat.models import (
    GROUP_CHAT_KINDS,
    GROUP_CHATS,
    PERSONAL_KIND,
    Chat,
    ChatMember,
    ChatMessage,
    ChatMessageArchive,
    ChatMessageDedup,
    ChatMessageHistory,
    ChatMessageSnapshot,
    ChatMessageSnapshotPhoto,
    ChatMessageVersion,
)
from campus.modules.chat.retention import purge_message_versions
from campus.modules.chat.service import (
    MESSAGE_TOPIC,
    check_link,
    create_personal_chat,
    delete_message,
    edit_message,
    leave_chat,
    message_evidence,
    post_message,
    require_membership,
    snapshot_message,
    snapshot_photos,
)

__all__ = [
    "GROUP_CHATS",
    "GROUP_CHAT_KINDS",
    "MESSAGE_TOPIC",
    "PERSONAL_KIND",
    "Chat",
    "ChatMember",
    "ChatMessage",
    "ChatMessageArchive",
    "ChatMessageDedup",
    "ChatMessageHistory",
    "ChatMessageSnapshot",
    "ChatMessageSnapshotPhoto",
    "ChatMessageVersion",
    "check_link",
    "create_personal_chat",
    "delete_message",
    "edit_message",
    "leave_chat",
    "message_evidence",
    "post_message",
    "purge_message_versions",
    "require_membership",
    "router",
    "snapshot_message",
    "snapshot_photos",
    "sync_group_chat",
]
