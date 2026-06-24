import os
from typing import AsyncIterator

from openai import AsyncOpenAI

from app.config import settings


class AIService:
    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.openai_api_key or os.getenv("OPENAI_API_KEY"))

    async def ask(
        self,
        system_prompt: str,
        user_message: str,
        temperature: float = 0.7,
    ) -> str:
        if not self.client.api_key:
            return "AI service is not configured. Please set OPENAI_API_KEY."

        response = await self.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
            temperature=temperature,
        )
        return response.choices[0].message.content or ""

    async def ask_stream(
        self,
        system_prompt: str,
        user_message: str,
    ) -> AsyncIterator[str]:
        if not self.client.api_key:
            yield "AI service is not configured. Please set OPENAI_API_KEY."
            return

        stream = await self.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
            stream=True,
        )

        async for chunk in stream:
            content = chunk.choices[0].delta.content
            if content:
                yield content
