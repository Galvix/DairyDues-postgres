import os 
from fastapi import Header, HTTPException, status

_API_TOKEN = os.environ.get("API_TOKEN", "")
_PRINT_AGENT_TOKEN = os.environ.get("PRINT_AGENT_TOKEN", "")

def _bearer(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
        )
    return authorization.remove_prefix("Bearer ").strip()

async def require_auth(authorization: str | None = Header(default=None)) -> None:
    """Dependency to require a valid API token in the Authorization header."""
    token = _bearer(authorization)
    if token != _API_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API token",
        )
    
async def require_agent_auth(authorization: str | None = Header(default=None)) -> None:
    """Dependency to require a valid print agent token in the Authorization header."""
    token = _bearer(authorization)
    if token != _PRINT_AGENT_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid print agent token",
        )