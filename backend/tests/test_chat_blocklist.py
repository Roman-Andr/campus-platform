"""Incoming message policy and the personal blacklist on PostgreSQL.

The tests cover owner scoping, both block directions, neutral refusals,
listing visibility, started interactions and concurrent block/message races.
"""

import asyncio
from datetime import timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx2
from sqlalchemy import select

from campus.core import clock
from campus.modules.chat import Chat, ChatMessage
from campus.modules.identity import Block
from campus.modules.listings import Interaction
from tests.test_chat import (
    ROOT,
    Reference,
    account,
    bearer,
    chat_auth,
    create_chat,
    publish_listing,
    reference,
    send_message,
    subscription_token,
)
from tests.test_profile import Account

LISTINGS = "/api/v1/listings"
ME = "/api/v1/me"

__all__ = ["chat_auth", "reference"]


def api_key() -> str:
    return str(uuid4())


async def set_policy(
    account: Account, policy: str, key: str | None = None
) -> httpx2.Response:
    return await account.auth.client.put(
        f"{ME}/message-policy",
        json={"policy": policy},
        headers={"Idempotency-Key": key or api_key(), **bearer(account)},
    )


async def block(
    account: Account, target: Any, key: str | None = None
) -> httpx2.Response:
    target_id = target if isinstance(target, str) else target.tokens["user"]["id"]
    return await account.auth.client.post(
        f"{ME}/blocks",
        json={"user_id": target_id},
        headers={"Idempotency-Key": key or api_key(), **bearer(account)},
    )


async def unblock(
    account: Account, target: Any, key: str | None = None
) -> httpx2.Response:
    target_id = target if isinstance(target, str) else target.tokens["user"]["id"]
    return await account.auth.client.delete(
        f"{ME}/blocks/{target_id}",
        headers={"Idempotency-Key": key or api_key(), **bearer(account)},
    )


async def blocks(account: Account) -> httpx2.Response:
    return await account.auth.client.get(f"{ME}/blocks", headers=bearer(account))


async def feed(account: Account, q: str | None = None) -> httpx2.Response:
    return await account.auth.client.get(
        LISTINGS, params={"q": q} if q is not None else None, headers=bearer(account)
    )


async def reserve(account: Account, listing_id: str) -> httpx2.Response:
    return await account.auth.client.post(
        f"{LISTINGS}/{listing_id}/reservations",
        headers={"Idempotency-Key": api_key(), **bearer(account)},
    )


async def publish_event(account: Account, reference: Reference) -> dict[str, Any]:
    response = await account.auth.client.post(
        f"{LISTINGS}/events",
        json={
            "category_id": str(reference.category),
            "title": "Campus concert",
            "description": "Meet in the hall",
            "starts_at": (clock.now() + timedelta(days=3)).isoformat(),
            "ends_at": (clock.now() + timedelta(days=3, hours=2)).isoformat(),
            "location": "Hall A",
            "capacity": 3,
        },
        headers={"Idempotency-Key": api_key(), **bearer(account)},
    )
    assert response.status_code == 201, response.text
    result: dict[str, Any] = response.json()
    return result


async def transition(
    account: Account, listing_id: str, interaction_id: str, status: str
) -> httpx2.Response:
    return await account.auth.client.post(
        f"{LISTINGS}/{listing_id}/interactions/{interaction_id}/transition",
        json={"status": status},
        headers={"Idempotency-Key": api_key(), **bearer(account)},
    )


async def test_message_policy_is_owner_scoped_and_defaults_to_all(
    chat_auth: Any,
) -> None:
    alice = await account(chat_auth, "policy-alice@university.example")
    bob = await account(chat_auth, "policy-bob@university.example")

    me = await alice.auth.client.get(ME, headers=bearer(alice))
    assert me.status_code == 200
    assert me.json()["message_policy"] == "all"
    policy = await alice.auth.client.get(f"{ME}/message-policy", headers=bearer(alice))
    assert policy.json() == {"policy": "all"}

    changed = await set_policy(alice, "related")
    assert changed.status_code == 200, changed.text
    assert changed.json() == {"policy": "related"}
    assert (await alice.auth.client.get(ME, headers=bearer(alice))).json()[
        "message_policy"
    ] == "related"
    # Changing one's own policy never touches another account.
    assert (await bob.auth.client.get(ME, headers=bearer(bob))).json()[
        "message_policy"
    ] == "all"
    assert (await set_policy(bob, "all")).status_code == 200
    own_policy = await alice.auth.client.get(
        f"{ME}/message-policy", headers=bearer(alice)
    )
    assert own_policy.json() == {"policy": "related"}
    invalid = await set_policy(alice, "nobody")
    assert invalid.status_code == 422

    # The idempotency key is bound to the request body, not just the route.
    policy_key = api_key()
    assert (await set_policy(alice, "all", policy_key)).status_code == 200
    conflict = await set_policy(alice, "related", policy_key)
    assert conflict.status_code == 422
    assert conflict.json()["code"] == "idempotency_key_reused"


async def test_related_policy_requires_a_listing_or_interaction_relation(
    chat_auth: Any, reference: Reference
) -> None:
    alice = await account(
        chat_auth, "related-alice@university.example", reference.places
    )
    bob = await account(chat_auth, "related-bob@university.example", reference.places)
    carol = await account(
        chat_auth, "related-carol@university.example", reference.places
    )
    assert (await set_policy(alice, "related")).status_code == 200

    denied = await create_chat(bob, alice)
    assert denied.status_code == 403, denied.text
    assert denied.json()["code"] == "chat_forbidden"
    assert "block" not in denied.json()["detail"].lower()

    # A message to a user who allows everybody is still possible.
    assert (await create_chat(alice, bob)).status_code == 201

    listing = await publish_listing(alice, reference)
    linked = await create_chat(bob, alice, listing_id=listing["id"])
    assert linked.status_code == 201, linked.text
    assert linked.json()["listing_id"] == listing["id"]
    # A listing link cannot attach an unrelated third user.
    third = await create_chat(bob, carol, listing_id=listing["id"])
    assert third.status_code == 404, third.text

    # A started interaction is a permitted relation for a direct chat,
    # including a brand-new pair with no chat yet.
    interaction = Interaction(
        listing_id=UUID(listing["id"]),
        participant_id=UUID(carol.tokens["user"]["id"]),
        slot=None,
        status="accepted",
    )
    chat_auth.db.add(interaction)
    await chat_auth.db.commit()
    direct = await create_chat(carol, alice)
    assert direct.status_code == 201, direct.text
    assert direct.json()["listing_id"] is None

    # The policy is enforced on every incoming message, not only at creation:
    # the existing direct chat between Alice and Bob has no permitted relation.
    bob_chat = (await create_chat(alice, bob)).json()
    assert (await send_message(bob, bob_chat["id"], "no relation")).status_code == 403
    # Alice may write to Bob because Bob's incoming policy is still "all".
    assert (await send_message(alice, bob_chat["id"], "hello")).status_code == 201


async def test_block_crud_is_owner_scoped_and_idempotent(chat_auth: Any) -> None:
    alice = await account(chat_auth, "crud-alice@university.example")
    bob = await account(chat_auth, "crud-bob@university.example")
    alice_id = alice.tokens["user"]["id"]
    bob_id = bob.tokens["user"]["id"]

    assert (await block(alice, alice_id)).status_code == 422
    assert (await block(alice, str(uuid4()))).status_code == 404

    key = api_key()
    created = await block(alice, bob, key)
    assert created.status_code == 201, created.text
    assert created.json()["id"] == bob_id
    assert created.json()["first_name"]

    # A different key repeats the command as a success without a duplicate.
    repeated = await block(alice, bob)
    assert repeated.status_code == 200, repeated.text
    assert repeated.json()["id"] == bob_id
    # The same key replays the original 201 response.
    replayed = await block(alice, bob, key)
    assert replayed.status_code == 201, replayed.text
    assert replayed.headers.get("Idempotent-Replayed") == "true"
    conflict = await block(alice, str(uuid4()), key)
    assert conflict.status_code == 422
    assert conflict.json()["code"] == "idempotency_key_reused"

    alice_blocks = await blocks(alice)
    assert alice_blocks.status_code == 200
    assert [item["id"] for item in alice_blocks.json()["items"]] == [bob_id]
    # The blacklist is private: another account sees its own empty list.
    assert (await blocks(bob)).json()["items"] == []

    # Bob cannot remove Alice's block by calling his own endpoint.
    assert (await unblock(bob, alice)).status_code == 204
    assert [item["id"] for item in (await blocks(alice)).json()["items"]] == [bob_id]

    assert (await unblock(alice, bob)).status_code == 204
    assert (await unblock(alice, bob)).status_code == 204
    assert (await blocks(alice)).json()["items"] == []


async def test_block_denies_messages_both_directions_but_keeps_history(
    chat_auth: Any,
) -> None:
    alice = await account(chat_auth, "msg-alice@university.example")
    bob = await account(chat_auth, "msg-bob@university.example")
    chat = (await create_chat(alice, bob)).json()
    assert (await send_message(alice, chat["id"], "before")).status_code == 201

    # An already issued subscription is not a write permission.
    token = await subscription_token(bob, f"chat:{chat['id']}")
    assert token.status_code == 200, token.text

    assert (await block(alice, bob)).status_code == 201
    from_bob = await send_message(bob, chat["id"], "after")
    assert from_bob.status_code == 403, from_bob.text
    assert from_bob.json()["code"] == "chat_forbidden"
    assert "block" not in from_bob.json()["detail"].lower()
    # A block disables both directions for personal messages.
    assert (await send_message(alice, chat["id"], "after")).status_code == 403

    history = await bob.auth.client.get(
        f"{ROOT}/{chat['id']}/messages", headers=bearer(bob)
    )
    assert history.status_code == 200
    assert [item["text"] for item in history.json()["items"]] == ["before"]

    # New dialogs are refused in both directions, too.
    assert (await create_chat(bob, alice)).status_code == 403
    assert (await create_chat(alice, bob)).status_code == 403

    assert (await unblock(alice, bob)).status_code == 204
    assert (await send_message(bob, chat["id"], "unblocked")).status_code == 201

    # The reverse block direction has the same effect.
    assert (await block(bob, alice)).status_code == 201
    assert (await send_message(alice, chat["id"], "reverse")).status_code == 403
    assert (await send_message(bob, chat["id"], "reverse")).status_code == 403
    assert (await unblock(bob, alice)).status_code == 204


async def test_block_hides_listings_and_refuses_new_responses(
    chat_auth: Any, reference: Reference
) -> None:
    alice = await account(chat_auth, "view-alice@university.example", reference.places)
    bob = await account(chat_auth, "view-bob@university.example", reference.places)
    carol = await account(chat_auth, "view-carol@university.example", reference.places)
    alice_listing = await publish_listing(alice, reference)
    bob_listing = await publish_listing(bob, reference)

    assert (await feed(alice)).status_code == 200
    assert {item["id"] for item in (await feed(alice, "desk")).json()["items"]} == {
        alice_listing["id"],
        bob_listing["id"],
    }

    assert (await block(alice, bob)).status_code == 201

    for viewer, hidden in ((alice, bob_listing), (bob, alice_listing)):
        page = await feed(viewer)
        assert hidden["id"] not in {item["id"] for item in page.json()["items"]}
        searched = await feed(viewer, "desk")
        assert hidden["id"] not in {item["id"] for item in searched.json()["items"]}
        direct = await viewer.auth.client.get(
            f"{LISTINGS}/{hidden['id']}", headers=bearer(viewer)
        )
        assert direct.status_code == 404

    # An unrelated user still sees both listings.
    assert {item["id"] for item in (await feed(carol, "desk")).json()["items"]} == {
        alice_listing["id"],
        bob_listing["id"],
    }

    refused = await bob.auth.client.post(
        f"{LISTINGS}/{alice_listing['id']}/reservations",
        headers={"Idempotency-Key": api_key(), **bearer(bob)},
    )
    assert refused.status_code == 404, refused.text
    assert refused.json()["code"] == "not_found"
    assert (await reserve(alice, bob_listing["id"])).status_code == 404


async def test_block_denies_event_signup(chat_auth: Any, reference: Reference) -> None:
    alice = await account(chat_auth, "event-alice@university.example", reference.places)
    bob = await account(chat_auth, "event-bob@university.example", reference.places)
    event = await publish_event(alice, reference)
    assert (await block(alice, bob)).status_code == 201
    signup = await bob.auth.client.post(
        f"{LISTINGS}/{event['id']}/signup",
        json={"join_queue": False},
        headers={"Idempotency-Key": api_key(), **bearer(bob)},
    )
    assert signup.status_code == 404, signup.text
    assert signup.json()["code"] == "not_found"


async def test_started_interaction_stays_readable_and_completable_after_block(
    chat_auth: Any, reference: Reference
) -> None:
    alice = await account(
        chat_auth, "started-alice@university.example", reference.places
    )
    bob = await account(chat_auth, "started-bob@university.example", reference.places)
    listing = await publish_listing(alice, reference)
    started = await reserve(bob, listing["id"])
    assert started.status_code == 201, started.text
    interaction = started.json()

    assert (await block(alice, bob)).status_code == 201

    # The participant keeps the card and the author can accept it.
    assert (
        await bob.auth.client.get(f"{LISTINGS}/{listing['id']}", headers=bearer(bob))
    ).status_code == 200
    accepted = await transition(alice, listing["id"], interaction["id"], "accepted")
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["status"] == "accepted"
    # A completion operation of the started interaction is still available.
    proposed = await alice.auth.client.post(
        f"{LISTINGS}/{listing['id']}/interactions/{interaction['id']}"
        "/meeting/proposals",
        json={
            "time": (clock.now() + timedelta(days=1)).isoformat(),
            "location": "Main library",
        },
        headers={"Idempotency-Key": api_key(), **bearer(alice)},
    )
    assert proposed.status_code == 200, proposed.text


async def test_block_races_message_and_response(
    chat_auth: Any, reference: Reference
) -> None:
    alice = await account(chat_auth, "race-alice@university.example", reference.places)
    bob = await account(chat_auth, "race-bob@university.example", reference.places)
    chat = (await create_chat(alice, bob)).json()
    listing = await publish_listing(alice, reference)

    blocked, sent, responded = await asyncio.gather(
        block(alice, bob),
        send_message(bob, chat["id"], "racing"),
        reserve(bob, listing["id"]),
    )
    assert blocked.status_code == 201, blocked.text
    assert sent.status_code in (201, 403)
    assert responded.status_code in (201, 404)

    # Whatever won the race, the committed block is authoritative afterwards.
    assert (await send_message(bob, chat["id"], "post-race")).status_code == 403
    assert (await reserve(bob, listing["id"])).status_code == 404
    rows = list(
        await chat_auth.db.scalars(
            select(Block).where(
                Block.blocker_id == UUID(alice.tokens["user"]["id"]),
                Block.blocked_id == UUID(bob.tokens["user"]["id"]),
            )
        )
    )
    assert len(rows) == 1
    # If the reservation won, it is a started interaction and keeps its card.
    if responded.status_code == 201:
        assert (
            await bob.auth.client.get(
                f"{LISTINGS}/{listing['id']}", headers=bearer(bob)
            )
        ).status_code == 200
        interaction_row = await chat_auth.db.scalar(
            select(Interaction).where(
                Interaction.listing_id == UUID(listing["id"]),
                Interaction.participant_id == UUID(bob.tokens["user"]["id"]),
            )
        )
        blocked_row = await chat_auth.db.scalar(
            select(Block).where(
                Block.blocker_id == UUID(alice.tokens["user"]["id"]),
                Block.blocked_id == UUID(bob.tokens["user"]["id"]),
            )
        )
        assert interaction_row is not None
        assert blocked_row is not None
        assert interaction_row.created_at <= blocked_row.created_at
    # A message committed after the block would mean the lock was bypassed.
    if sent.status_code == 201:
        message = await chat_auth.db.scalar(
            select(ChatMessage).where(ChatMessage.text == "racing")
        )
        blocked_row = await chat_auth.db.scalar(
            select(Block).where(
                Block.blocker_id == UUID(alice.tokens["user"]["id"]),
                Block.blocked_id == UUID(bob.tokens["user"]["id"]),
            )
        )
        assert message is not None
        assert blocked_row is not None
        assert message.created_at <= blocked_row.created_at


async def test_concurrent_block_commands_store_one_row(chat_auth: Any) -> None:
    alice = await account(chat_auth, "dup-alice@university.example")
    bob = await account(chat_auth, "dup-bob@university.example")
    first, second = await asyncio.gather(block(alice, bob), block(alice, bob))
    assert sorted((first.status_code, second.status_code)) == [200, 201]
    rows = list(
        await chat_auth.db.scalars(
            select(Block).where(
                Block.blocker_id == UUID(alice.tokens["user"]["id"]),
                Block.blocked_id == UUID(bob.tokens["user"]["id"]),
            )
        )
    )
    assert len(rows) == 1


async def test_existing_chat_model_is_unaffected_by_a_third_party_block(
    chat_auth: Any,
) -> None:
    alice = await account(chat_auth, "third-alice@university.example")
    bob = await account(chat_auth, "third-bob@university.example")
    carol = await account(chat_auth, "third-carol@university.example")
    chat = (await create_chat(alice, bob)).json()
    assert (await block(carol, alice)).status_code == 201
    assert (await send_message(bob, chat["id"], "still private")).status_code == 201
    stored = await chat_auth.db.get(Chat, UUID(chat["id"]))
    assert stored is not None
