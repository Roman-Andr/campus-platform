"""Translation of user-facing messages (gettext catalogs via Babel).

Messages are written in English and marked with :func:`N_` where they are
defined; the English text is the message ID. They are translated when a
response is rendered, into the language negotiated from ``Accept-Language``.

Catalogs: ``campus/locales/messages.pot`` (template) and
``campus/locales/<lang>/LC_MESSAGES/messages.po``. The ``.po`` files are
compiled in memory on first use, so no binary ``.mo`` files are committed.
Update them with ``pybabel`` (see backend/README.md).
"""

import gettext
from functools import cache
from io import BytesIO
from pathlib import Path
from typing import get_args

from babel.core import negotiate_locale
from babel.messages.mofile import write_mo
from babel.messages.pofile import read_po

from campus.core.config import Locale

LOCALES_DIR = Path(__file__).parents[1] / "locales"
DOMAIN = "messages"
SOURCE_LOCALE: Locale = "en"
SUPPORTED_LOCALES: tuple[Locale, ...] = get_args(Locale.__value__)


def N_(message: str) -> str:  # noqa: N802 - the gettext convention
    """Mark ``message`` for extraction; it is translated later."""
    return message


@cache
def translations(locale: Locale) -> gettext.NullTranslations:
    """Compiled catalog of ``locale``; the source language needs none."""
    if locale == SOURCE_LOCALE:
        return gettext.NullTranslations()
    path = LOCALES_DIR / locale / "LC_MESSAGES" / f"{DOMAIN}.po"
    with path.open("rb") as po_file:
        catalog = read_po(po_file, locale=locale, domain=DOMAIN)
    compiled = BytesIO()
    write_mo(compiled, catalog)
    compiled.seek(0)
    return gettext.GNUTranslations(compiled)


def translate(message: str, locale: Locale, /, **params: object) -> str:
    """Translate ``message`` into ``locale`` and fill in ``{name}`` params."""
    text = translations(locale).gettext(message)
    return text.format(**params) if params else text


def _preferred(accept_language: str) -> list[str]:
    """Language tags of an ``Accept-Language`` header, best first."""
    weighted: list[tuple[float, int, str]] = []
    for index, part in enumerate(accept_language.split(",")):
        tag, _, parameters = part.strip().partition(";")
        tag = tag.strip().lower()
        quality = 1.0
        for parameter in parameters.split(";"):
            name, _, value = parameter.strip().partition("=")
            if name.strip().lower() == "q":
                try:
                    quality = float(value)
                except ValueError:
                    quality = 0.0
        if tag and tag != "*" and quality > 0:
            weighted.append((-quality, index, tag))
    return [tag for _, _, tag in sorted(weighted)]


def negotiate(accept_language: str | None, default: Locale) -> Locale:
    """Pick the supported locale that best matches ``Accept-Language``."""
    if not accept_language:
        return default
    match = negotiate_locale(_preferred(accept_language), SUPPORTED_LOCALES, sep="-")
    for locale in SUPPORTED_LOCALES:
        if locale == match:
            return locale
    return default
