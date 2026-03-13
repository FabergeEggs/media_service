from pydantic import BaseModel, AnyUrl, Field
from uuid import UUID
from datetime import datetime
from typing import Optional, List


class MediaDTO(BaseModel):
    id: UUID
    owner_id: UUID
    url: AnyUrl
    mime_type: str
    size_bytes: int
    created_at: datetime
    description: Optional[str] = None

    class Config:
        from_attributes = True


class MediaCreateDTO(BaseModel):
    owner_id: UUID
    mime_type: str
    size_bytes: int = Field(..., ge=0)
    description: Optional[str] = None


class MediaBulkCreateDTO(BaseModel):
    items: List[MediaCreateDTO]

