import json
import traceback

from errors import AppError
from log_utils import log_progress
from service import chat, refresh_faq_embeddings


def lambda_handler(event, context):
    try:
        if is_warmup_event(event):
            result = refresh_faq_embeddings()
            log_progress("warmup event completed", updated_embeddings=result["updated_embeddings"])
            return response(200, result)

        request = parse_event(event)
        log_progress(
            "chat request parsed",
            user_id=request.get("user_id"),
            conversation_id=request.get("conversation_id"),
            message_seq=request.get("message_seq"),
            message_len=len(str(request.get("message") or "")),
        )
        result = chat(request)
        log_progress(
            "chat request completed",
            conversation_id=result["conversation_id"],
            message_seq=result["message_seq"],
            category=result["category"],
            confidence=result["confidence"],
            need_human_support=result["need_human_support"],
        )
        return response(200, result)
    except AppError as exc:
        log_progress("application error", status_code=exc.status_code, message=exc.message)
        return response(exc.status_code, {"error": exc.message})
    except Exception as exc:
        log_progress("unexpected error while handling lambda invocation")
        traceback.print_exc()
        return response(500, {"error": f"internal error: {exc}"})


def is_warmup_event(event):
    return isinstance(event, dict) and event.get("hello") == "just4warmingup"


def parse_event(event):
    body = event.get("body", event)
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except json.JSONDecodeError as exc:
            raise AppError(400, f"body must be valid JSON: {exc}") from exc
    if not isinstance(body, dict):
        raise AppError(400, "request body must be a JSON object")
    return body


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }
