"""Message catalogs and language negotiation."""

from pathlib import Path

import pytest
from babel.messages.extract import extract_from_dir
from babel.messages.pofile import read_po

from campus.core.i18n import LOCALES_DIR, SUPPORTED_LOCALES, negotiate, translate

SOURCE_DIR = Path(__file__).parents[1] / "src" / "campus"


def extracted_messages() -> set[str]:
    return {
        message
        for _, _, message, *_ in extract_from_dir(SOURCE_DIR)
        if isinstance(message, str) and message
    }


def catalog_messages(path: Path, locale: str | None = None) -> dict[str, str]:
    with path.open("rb") as po_file:
        catalog = read_po(po_file, locale=locale)
    return {
        str(message.id): str(message.string)
        for message in catalog
        if message.id and not message.fuzzy
    }


def test_template_is_up_to_date() -> None:
    # Run `pybabel extract` (backend/README.md) when this fails.
    template = catalog_messages(LOCALES_DIR / "messages.pot")

    assert set(template) == extracted_messages()


@pytest.mark.parametrize("locale", [loc for loc in SUPPORTED_LOCALES if loc != "en"])
def test_translations_are_complete(locale: str) -> None:
    # Run `pybabel update` and translate the new messages when this fails.
    path = LOCALES_DIR / locale / "LC_MESSAGES" / "messages.po"
    translations = catalog_messages(path, locale)

    assert set(translations) == extracted_messages()
    assert [msgid for msgid, text in translations.items() if not text] == []


def test_translation_fills_parameters() -> None:
    assert translate("Must be at most {le}.", "ru", le=5) == "Должно быть не больше 5."
    assert translate("Must be at most {le}.", "en", le=5) == "Must be at most 5."
    assert translate("Not found", "en") == "Not found"


@pytest.mark.parametrize(
    ("header", "expected"),
    [
        (None, "ru"),
        ("", "ru"),
        ("en", "en"),
        ("EN-us", "en"),
        ("en-US,ru;q=0.5", "en"),
        ("ru;q=0.3, en;q=0.9", "en"),
        ("de, en-GB;q=0.2", "en"),
        ("ru;q=0, en;q=0.1", "en"),
        ("en;q=0", "ru"),
        ("en;q=abc, ru;q=0.5", "ru"),
        ("de, fr", "ru"),
        ("*", "ru"),
    ],
)
def test_language_is_negotiated(header: str | None, expected: str) -> None:
    assert negotiate(header, "ru") == expected


def test_default_language_is_configurable() -> None:
    assert negotiate("de", "en") == "en"
