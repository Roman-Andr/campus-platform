"""Publication identity anchored in the shared feed aggregate.

Text, author and audience scope live in the referenced listing root. This
base is shared by informational notices and future forum/page content;
comments, reactions and pages can reference its stable publication ID.
"""

from uuid import UUID

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from campus.core.db import Base


class Publication(Base):
    """A publication has no listing item or participation scenario."""

    __tablename__ = "publication"

    listing_id: Mapped[UUID] = mapped_column(ForeignKey("listing.id"), primary_key=True)
