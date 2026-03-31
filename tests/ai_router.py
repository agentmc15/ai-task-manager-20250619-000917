"""
AI API Routes for Clarity
Provides endpoints for questionnaire assistance, recommendations, and copilot chat.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from src.clarity.core.ai_service import ai_service

router = APIRouter(prefix="/ai", tags=["ai"])


# -------------------------------------------------------------------------
# Request/Response models
# -------------------------------------------------------------------------

class QuestionnaireRequest(BaseModel):
    question: str
    context: Optional[str] = ""
    project_name: Optional[str] = ""
    project_description: Optional[str] = ""


class QuestionnaireResponse(BaseModel):
    answer: str
    source: str  # "xeta" or "ollama"


class RecommendationRequest(BaseModel):
    project_name: str
    project_description: str
    attributes: Optional[list[str]] = []
    tags: Optional[list[str]] = []


class RecommendationResponse(BaseModel):
    recommendations: str
    source: str


class CopilotRequest(BaseModel):
    message: str
    conversation_history: Optional[list[dict]] = []


class CopilotResponse(BaseModel):
    reply: str
    source: str


class HealthResponse(BaseModel):
    xeta: str
    ollama: str


# -------------------------------------------------------------------------
# Endpoints
# -------------------------------------------------------------------------

@router.post("/questionnaire", response_model=QuestionnaireResponse)
async def questionnaire_help(request: QuestionnaireRequest):
    """Get AI-suggested answer for an IRAMP/ATO questionnaire question."""
    try:
        answer = await ai_service.answer_questionnaire(
            question=request.question,
            context=request.context,
            project_name=request.project_name,
            project_description=request.project_description,
        )
        status = await ai_service.health_check()
        source = "xeta" if status["xeta"] == "available" and ai_service.xeta_configured else "ollama"
        return QuestionnaireResponse(answer=answer, source=source)
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.post("/recommendations", response_model=RecommendationResponse)
async def get_recommendations(request: RecommendationRequest):
    """Get AI-generated recommendations for a project."""
    try:
        recommendations = await ai_service.get_recommendations(
            project_name=request.project_name,
            project_description=request.project_description,
            attributes=request.attributes,
            tags=request.tags,
        )
        status = await ai_service.health_check()
        source = "xeta" if status["xeta"] == "available" and ai_service.xeta_configured else "ollama"
        return RecommendationResponse(recommendations=recommendations, source=source)
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.post("/chat", response_model=CopilotResponse)
async def copilot_chat(request: CopilotRequest):
    """General-purpose AI copilot chat."""
    try:
        reply = await ai_service.copilot_chat(
            user_message=request.message,
            conversation_history=request.conversation_history,
        )
        status = await ai_service.health_check()
        source = "xeta" if status["xeta"] == "available" and ai_service.xeta_configured else "ollama"
        return CopilotResponse(reply=reply, source=source)
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.get("/health", response_model=HealthResponse)
async def ai_health():
    """Check AI service availability."""
    status = await ai_service.health_check()
    return HealthResponse(**status)
