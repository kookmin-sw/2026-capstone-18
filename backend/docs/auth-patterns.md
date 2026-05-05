# Auth Patterns

Reference card for protecting future endpoints. All patterns assume the request carries `Authorization: Bearer <supabase_jwt>`.

## Protect an endpoint with the current user

```python
from typing import Annotated

from fastapi import APIRouter, Depends

from app.auth.dependencies import get_current_user
from app.models.user import User

router = APIRouter(prefix="/things", tags=["things"])


@router.get("")
async def list_things(
    user: Annotated[User, Depends(get_current_user)],
) -> list[Thing]:
    ...
```

`get_current_user` chains: `get_current_user_id` (extracts and verifies the JWT; raises 401) → DB lookup by `supabase_user_id` (raises 404 if missing, 403 if `deleted_at` is set).

## Require admin role

```python
from app.auth.dependencies import require_admin


@router.post("/admin/something")
async def admin_action(
    user: Annotated[User, Depends(require_admin)],
) -> dict:
    ...
```

`require_admin` adds a check on `user.role == "admin"` and raises 403 otherwise.

## Use only the user_id (skip DB lookup)

For high-throughput endpoints where the DB row isn't needed:

```python
import uuid
from app.auth.dependencies import get_current_user_id


@router.get("/cheap")
async def cheap(
    user_id: Annotated[uuid.UUID, Depends(get_current_user_id)],
) -> dict:
    ...
```

## Tests for protected endpoints

Use the `make_jwt` fixture from `app/tests/conftest_jwt.py`:

```python
async def test_my_protected_endpoint(db_session, make_jwt):
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as http:
        response = await http.get(
            "/api/v1/things",
            headers={"Authorization": f"Bearer {make_jwt(sub=str(user.supabase_user_id))}"},
        )
    assert response.status_code == 200
```
