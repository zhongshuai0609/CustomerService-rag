import traceback

import db
import llm_client
import prompts
from errors import AppError
from log_utils import log_progress


# RAG retrieves the 3 FAQ entries with the highest similarity.
FAQ_TOP_K = 3


def chat(req):
    user_id = req.get("user_id")
    conversation_id = req.get("conversation_id")
    message = clean_text(req.get("message"))
    message_seq = req.get("message_seq")

    validate_request(user_id, conversation_id, message_seq, message)

    conn = db.get_conn()
    try:
        conv_id = db.get_or_create_conversation(conn, user_id, conversation_id)
        db.validate_message_seq(conn, conv_id, message_seq)
        db.save_message(conn, conv_id, message_seq, "user", message)

        history = db.get_history(conn, conv_id)
        faq_context = search_faq(conn, message)
        log_progress(
            "RAG context",
            conversation_id=conv_id,
            history_count=len(history),
            faq_ids=[row["id"] for row in faq_context],
        )
        llm_messages = prompts.build_messages(history[:-1], message, faq_context)
        llm_result = llm_client.call_llm(llm_messages)
        log_progress(
            "LLM result received",
            conversation_id=conv_id,
            category=llm_result.get("category"),
            confidence=llm_result.get("confidence"),
            relevance=llm_result.get("relevance"),
            risk_level=llm_result.get("risk_level"),
            need_human_support=llm_result.get("need_human_support"),
        )

        db.save_message(
            conn,
            conv_id,
            message_seq,
            "assistant",
            llm_result["answer"],
            structured_output=llm_result,
        )
        conn.commit()
    except Exception:
        log_progress(
            "chat workflow failed; rolling back",
            user_id=user_id,
            conversation_id=conversation_id,
            message_seq=message_seq,
        )
        traceback.print_exc()
        conn.rollback()
        raise
    finally:
        conn.close()

    return {
        "conversation_id": str(conv_id),
        "message_seq": message_seq,
        "category": llm_result["category"],
        "answer": llm_result["answer"],
        "confidence": float(llm_result["confidence"]),
        "relevance":float(llm_result["relevance"]),
        "need_human_support": bool(llm_result["need_human_support"]),
        "risk_level": llm_result["risk_level"]
    }

def validate_request(user_id, conversation_id, message_seq, message):
    if not user_id:
        raise AppError(400, "user_id is required")
    if not conversation_id:
        raise AppError(400, "conversation_id is required")
    if not message:
        raise AppError(400, "message must not be empty")
    if not isinstance(message_seq, int) or message_seq < 1:
        raise AppError(400, "message_seq must be an integer >= 1")


def clean_text(value):
    if value is None:
        return None
    return str(value).strip()


def refresh_faq_embeddings():
    conn = db.get_conn()
    try:
        rows = db.get_faq_rows_without_embedding(conn)
        log_progress("FAQ rows without embedding loaded", count=len(rows))
        updated_count = 0

        for row in rows:
            embedding = llm_client.embed_text(build_faq_embedding_text(row))
            db.update_faq_embedding(conn, row["id"], embedding)
            updated_count += 1

        conn.commit()
        log_progress("FAQ embedding refresh committed", updated_count=updated_count)
    except Exception:
        log_progress("FAQ embedding refresh failed; rolling back")
        traceback.print_exc()
        conn.rollback()
        raise
    finally:
        conn.close()

    return {"status": "ok", "updated_embeddings": updated_count}


def search_faq(conn, message):
    query_embedding = llm_client.embed_text(message)
    return db.search_faq_by_embedding(conn, query_embedding, FAQ_TOP_K)


def build_faq_embedding_text(row):
    parts = [
        row["question"],
        " ".join(row.get("similar_questions") or []),
        " ".join(row.get("keywords") or []),
        row["answer"],
    ]
    return "\n".join(part for part in parts if part)
