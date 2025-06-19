from abc import ABC, abstractmethod
from typing import Dict, Any
import openai
from datetime import datetime
import os

class BaseAgent(ABC):
    """Base class for all AI agents"""
    
    def __init__(self, name: str):
        self.name = name
        self.client = openai.OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    
    @abstractmethod
    async def process(self, input_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process input and return results"""
        pass
    
    async def call_llm(self, prompt: str, system_prompt: str = None) -> str:
        """Make a call to the LLM"""
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})
        
        response = await self.client.chat.completions.create(
            model="gpt-4o",
            messages=messages,
            temperature=0.7
        )
        
        return response.choices[0].message.content
