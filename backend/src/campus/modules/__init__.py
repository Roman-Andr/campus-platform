"""Domain modules of the modular monolith (specification, section 4.1).

Each module is a package whose ``__init__`` is its public interface;
submodules are internal to the module.
"""

import importlib
import pkgutil


def import_all() -> None:
    """Import every module package, registering its tables in the metadata.

    A module imports its models in its ``__init__``; migrations and tests
    call this to see the whole schema.
    """
    for module in pkgutil.iter_modules(__path__, prefix=f"{__name__}."):
        importlib.import_module(module.name)
