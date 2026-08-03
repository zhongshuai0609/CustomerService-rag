import json
import os
import traceback

from openai import OpenAI

from errors import AppError


LLM_MODEL = os.environ.get("LLM_MODEL", "gpt-5.6-luna")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-3-small")

_openai_client = None


def get_openai_client():
    global _openai_client
    if _openai_client is None:
        api_key = os.environ.get("OPENAI_API_KEY")
        if not api_key:
            raise AppError(500, "OPENAI_API_KEY is not configured")
        client_args = {"api_key": api_key}
        if os.environ.get("OPENAI_BASE_URL"):
            client_args["base_url"] = os.environ["OPENAI_BASE_URL"]
        _openai_client = OpenAI(**client_args)
    return _openai_client


def embed_text(text):
    try:
        result = get_openai_client().embeddings.create(model=EMBEDDING_MODEL, input=text)
        return result.data[0].embedding
    except Exception as exc:
        print("OpenAI embedding request failed", flush=True)
        traceback.print_exc()
        raise AppError(502, f"OpenAI embedding call failed: {exc}") from exc


def call_llm(messages):
    try:
        llm_response = get_openai_client().chat.completions.create(
            model=LLM_MODEL,
            messages=messages,
            response_format={"type": "json_object"},
        )
        raw_content = llm_response.choices[0].message.content
        parsed = json.loads(raw_content)
    except json.JSONDecodeError as exc:
        print("OpenAI chat response was not valid JSON", flush=True)
        traceback.print_exc()
        raise AppError(502, f"LLM did not return valid JSON: {exc}") from exc
    except Exception as exc:
        print("OpenAI chat request failed", flush=True)
        traceback.print_exc()
        raise AppError(502, f"OpenAI chat call failed: {exc}") from exc

    required = {"category", "answer", "confidence", "relevance", "need_human_support", "risk_level"}
    missing = required - set(parsed)
    if missing:
        print(f"OpenAI chat response missing required fields: missing={sorted(missing)}", flush=True)
        raise AppError(502, f"LLM response is missing fields: {sorted(missing)}")
    return parsed
