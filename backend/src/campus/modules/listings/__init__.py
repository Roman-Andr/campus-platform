"""Listings and interactions between students.

Public interface of the module. Other modules import only this package,
never its submodules (enforced by import-linter).
"""


def untested(value: int) -> int:
    """CI demo for #32: uncovered code in a domain module."""
    if value > 0:
        return value * 2
    return -value
