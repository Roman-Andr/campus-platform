"""Entry point of the API process: ``campus-api``."""

import uvicorn

from campus.core.config import get_settings


def main() -> None:
    """Serve the API with uvicorn."""
    settings = get_settings()
    uvicorn.run(
        "campus.api.app:create_app",
        factory=True,
        host=settings.api_host,
        port=settings.api_port,
        # Logging is configured by the application (campus.core.logging);
        # requests are logged by AccessLogMiddleware without client data.
        log_config=None,
        access_log=False,
        server_header=False,
    )


if __name__ == "__main__":
    main()
