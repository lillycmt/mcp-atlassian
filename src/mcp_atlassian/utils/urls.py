"""URL-related utility functions for MCP Atlassian."""

import re
from urllib.parse import urlparse


def build_atlassian_base_url(
    product: str, scoped_token_mode: bool, cloud_id: str | None, classic_url: str | None
) -> str:
    """Build the base URL for Atlassian API requests.

    Args:
        product: The Atlassian product, either "jira" or "confluence"
        scoped_token_mode: Whether to use scoped token mode (api.atlassian.com/ex/...)
        cloud_id: The cloud ID (required when scoped_token_mode is True)
        classic_url: The classic URL (required when scoped_token_mode is False)

    Returns:
        The base URL for API requests

    Raises:
        ValueError: If scoped_token_mode is True but cloud_id is missing, or if
            scoped_token_mode is False but classic_url is missing
    """
    if scoped_token_mode:
        if not cloud_id:
            raise ValueError(
                "ATLASSIAN_SCOPED_TOKEN is enabled but ATLASSIAN_CLOUD_ID is missing"
            )
        if product == "jira":
            # Return base URL without /rest/api/3 - the atlassian-python-api library will append it
            return f"https://api.atlassian.com/ex/jira/{cloud_id}"
        elif product == "confluence":
            # Return base URL without /wiki/rest/api - the atlassian-python-api library will append it
            return f"https://api.atlassian.com/ex/confluence/{cloud_id}"
        else:
            raise ValueError(f"Unknown product: {product}")
    else:
        if not classic_url:
            raise ValueError("classic_url is required when scoped_token_mode is False")
        return classic_url


def is_atlassian_cloud_url(url: str) -> bool:
    """Determine if a URL belongs to Atlassian Cloud or Server/Data Center.

    Args:
        url: The URL to check

    Returns:
        True if the URL is for an Atlassian Cloud instance, False for Server/Data Center
    """
    # Localhost and IP-based URLs are always Server/Data Center
    if url is None or not url:
        return False

    parsed_url = urlparse(url)
    hostname = parsed_url.hostname or ""

    # Check for localhost or IP address
    if (
        hostname == "localhost"
        or re.match(r"^127\.", hostname)
        or re.match(r"^192\.168\.", hostname)
        or re.match(r"^10\.", hostname)
        or re.match(r"^172\.(1[6-9]|2[0-9]|3[0-1])\.", hostname)
    ):
        return False

    # The standard check for Atlassian cloud domains
    return (
        ".atlassian.net" in hostname
        or ".jira.com" in hostname
        or ".jira-dev.com" in hostname
        or "api.atlassian.com" in hostname
        or "bitbucket.org" in hostname  # Bitbucket Cloud
        or "api.bitbucket.org" in hostname  # Bitbucket Cloud API
    )
