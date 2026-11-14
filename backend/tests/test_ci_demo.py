from campus.modules.listings import untested


def test_untested_fails_on_purpose() -> None:
    """CI demo for #32: a failing test."""
    assert untested(1) == 3
