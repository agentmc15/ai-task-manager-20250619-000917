"""
AI Service Layer for Clarity
Primary: XETA/RTX Model Hub
Fallback: Local Ollama (Phi-3 Mini)

Usage:
    from src.clarity.core.ai_service import ai_service

    # General chat completion
    result = await ai_service.chat_completion(messages=[...])

    # Questionnaire help
    answer = await ai_service.answer_questionnaire(question, context)

    # Project recommendations
    recs = await ai_service.get_recommendations(project_details)
"""

import os
import logging
from typing import Optional

import httpx

logger = logging.getLogger(__name__)


class AIService:
    """Unified AI service with XETA primary and Ollama fallback."""

    def __init__(self):
        # XETA / RTX Model Hub
        self.xeta_base_url = os.getenv("META_OPENAI_URL_BASE", "")
        self.xeta_api_url = os.getenv("META_OPENAI_URL", "")
        self.xeta_api_key = os.getenv("META_OPENAI_KEY", "")

        # Ollama (local)
        self.ollama_base_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        self.ollama_model = os.getenv("OLLAMA_MODEL", "phi3-mini")

        # Settings
        self.timeout = int(os.getenv("AI_TIMEOUT", "60"))

    @property
    def xeta_configured(self) -> bool:
        return bool(self.xeta_api_url and self.xeta_api_key)

    # -------------------------------------------------------------------------
    # Core completion
    # -------------------------------------------------------------------------

    async def chat_completion(
        self,
        messages: list[dict],
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> dict:
        """
        Send a chat completion request.
        Tries XETA first, falls back to Ollama if XETA fails or is not configured.
        """
        if self.xeta_configured:
            try:
                result = await self._xeta_completion(messages, model, temperature, max_tokens)
                logger.info("AI response from XETA/Model Hub")
                return result
            except Exception as e:
                logger.warning(f"XETA failed, falling back to Ollama: {e}")

        try:
            result = await self._ollama_completion(messages, temperature, max_tokens)
            logger.info("AI response from Ollama (fallback)")
            return result
        except Exception as e:
            logger.error(f"All AI services failed: {e}")
            raise RuntimeError("AI service unavailable") from e

    async def get_response_text(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> str:
        """Convenience method — returns just the text content from a completion."""
        result = await self.chat_completion(messages, temperature=temperature, max_tokens=max_tokens)
        choices = result.get("choices", [])
        if choices:
            return choices[0].get("message", {}).get("content", "")
        return ""

    # -------------------------------------------------------------------------
    # Questionnaire assistance
    # -------------------------------------------------------------------------

    async def answer_questionnaire(
        self,
        question: str,
        context: str = "",
        project_name: str = "",
        project_description: str = "",
    ) -> str:
        """
        Generate a suggested answer for an IRAMP/ATO questionnaire question.
        """
        system_prompt = """You are an expert in IRAMP (Integrated Risk and Authorization Management Process) 
and ATO (Authority to Operate) compliance for defense and aerospace systems. 
You help engineers fill out security and compliance questionnaires accurately.

Guidelines:
- Provide clear, specific answers appropriate for the question type
- Reference relevant NIST 800-37, DFARS, ITAR, and FedRAMP frameworks when applicable
- If the question requires project-specific information you don't have, explain what information is needed
- Keep answers concise but thorough
- Use professional language appropriate for compliance documentation"""

        user_message = f"Question: {question}"
        if project_name:
            user_message = f"Project: {project_name}\n{user_message}"
        if project_description:
            user_message = f"Project Description: {project_description}\n{user_message}"
        if context:
            user_message = f"{user_message}\n\nAdditional Context: {context}"

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ]

        return await self.get_response_text(messages, temperature=0.3, max_tokens=512)

    # -------------------------------------------------------------------------
    # Project recommendations
    # -------------------------------------------------------------------------

    async def get_recommendations(
        self,
        project_name: str,
        project_description: str,
        attributes: list[str] = None,
        tags: list[str] = None,
    ) -> str:
        """
        Generate recommendations for a project based on its details.
        """
        system_prompt = """You are an expert advisor for IRAMP/ATO projects in defense and aerospace.
Based on the project details provided, give actionable recommendations for:
1. Key compliance areas to focus on
2. Potential risks or gaps to address early
3. Suggested next steps for the IRAMP/ATO process

Be specific and practical. Keep recommendations concise."""

        user_message = f"Project: {project_name}\nDescription: {project_description}"
        if attributes:
            user_message += f"\nAttributes: {', '.join(attributes)}"
        if tags:
            user_message += f"\nTags: {', '.join(tags)}"

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ]

        return await self.get_response_text(messages, temperature=0.5, max_tokens=1024)

    # -------------------------------------------------------------------------
    # Chat / copilot
    # -------------------------------------------------------------------------

    async def copilot_chat(
        self,
        user_message: str,
        conversation_history: list[dict] = None,
    ) -> str:
        """
        General-purpose copilot chat for Clarity users.
        Maintains conversation history for multi-turn interactions.
        """
        system_prompt = """You are the Clarity AI Copilot, an assistant for the Clarity IRAMP/ATO 
workflow automation platform. You help users with:
- Understanding IRAMP/ATO requirements and processes
- Filling out compliance questionnaires
- Navigating the Clarity application
- General questions about security compliance, NIST frameworks, and authorization processes

Be helpful, concise, and professional. If you don't know something specific to the user's 
project, say so and suggest what information would help."""

        messages = [{"role": "system", "content": system_prompt}]

        if conversation_history:
            messages.extend(conversation_history)

        messages.append({"role": "user", "content": user_message})

        return await self.get_response_text(messages, temperature=0.7, max_tokens=1024)

    # -------------------------------------------------------------------------
    # Health check
    # -------------------------------------------------------------------------

    async def health_check(self) -> dict:
        """Check availability of all AI services."""
        status = {"xeta": "unconfigured", "ollama": "unavailable"}

        if self.xeta_configured:
            try:
                async with httpx.AsyncClient(timeout=5, verify=False) as client:
                    resp = await client.get(
                        f"{self.xeta_base_url or self.xeta_api_url}/models",
                        headers={"Authorization": f"Bearer {self.xeta_api_key}"},
                    )
                    status["xeta"] = "available" if resp.status_code == 200 else f"error:{resp.status_code}"
            except Exception as e:
                status["xeta"] = f"error:{e}"

        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(f"{self.ollama_base_url}/api/tags")
                if resp.status_code == 200:
                    models = [m["name"] for m in resp.json().get("models", [])]
                    if any(self.ollama_model in m for m in models):
                        status["ollama"] = "available"
                    else:
                        status["ollama"] = f"running but model '{self.ollama_model}' not found"
                else:
                    status["ollama"] = f"error:{resp.status_code}"
        except Exception as e:
            status["ollama"] = f"unavailable:{e}"

        return status

    # -------------------------------------------------------------------------
    # Private methods
    # -------------------------------------------------------------------------

    async def _xeta_completion(
        self,
        messages: list[dict],
        model: Optional[str],
        temperature: float,
        max_tokens: int,
    ) -> dict:
        """Call XETA/RTX Model Hub."""
        async with httpx.AsyncClient(timeout=self.timeout, verify=False) as client:
            response = await client.post(
                f"{self.xeta_api_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.xeta_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model or "gpt-4o",
                    "messages": messages,
                    "temperature": temperature,
                    "max_tokens": max_tokens,
                },
            )
            response.raise_for_status()
            return response.json()

    async def _ollama_completion(
        self,
        messages: list[dict],
        temperature: float,
        max_tokens: int,
    ) -> dict:
        """Call local Ollama."""
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                f"{self.ollama_base_url}/v1/chat/completions",
                json={
                    "model": self.ollama_model,
                    "messages": messages,
                    "temperature": temperature,
                    "max_tokens": max_tokens,
                },
            )
            response.raise_for_status()
            return response.json()


# Singleton instance
ai_service = AIService()
