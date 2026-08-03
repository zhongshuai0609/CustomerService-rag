import os

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from errors import AppError


def get_conn():
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise AppError(500, "DATABASE_URL is not configured")
    return psycopg.connect(database_url, row_factory=dict_row)


def get_or_create_conversation(conn, user_id, conversation_id):
    row = conn.execute("SELECT id, user_id FROM conversations WHERE id = %s", (conversation_id,)).fetchone()
    if row is not None:
        if row["user_id"] != user_id:
            raise AppError(403, "conversation_id does not belong to this user_id")
        return row["id"]

    row = conn.execute(
        "INSERT INTO conversations (id, user_id) VALUES (%s, %s) RETURNING id",
        (conversation_id, user_id),
    ).fetchone()
    return row["id"]


def validate_message_seq(conn, conversation_id, message_seq):
    row = conn.execute(
        "SELECT COALESCE(MAX(message_seq), 0) AS latest_seq FROM messages WHERE conversation_id = %s",
        (conversation_id,),
    ).fetchone()
    latest_seq = row["latest_seq"]
    if message_seq <= latest_seq:
        raise AppError(
            400,
            f"message_seq {message_seq} is not valid; it must be greater than current latest seq {latest_seq}",
        )


def save_message(conn, conversation_id, message_seq, role, content, structured_output=None):
    conn.execute(
        """
        INSERT INTO messages (conversation_id, message_seq, role, content, structured_output)
        VALUES (%s, %s, %s, %s, %s)
        """,
        (conversation_id, message_seq, role, content, Jsonb(structured_output) if structured_output else None),
    )


def get_history(conn, conversation_id):
    rows = conn.execute(
        """
        SELECT role, content
        FROM messages
        WHERE conversation_id = %s
        ORDER BY message_seq ASC, id ASC
        """,
        (conversation_id,),
    ).fetchall()
    return [{"role": row["role"], "content": row["content"]} for row in rows]


def get_faq_rows_without_embedding(conn):
    return conn.execute(
        """
        SELECT id, question, similar_questions, keywords, answer
        FROM faq_entries
        WHERE status = 'active' AND embedding IS NULL
        ORDER BY id
        """
    ).fetchall()


def update_faq_embedding(conn, faq_id, embedding):
    conn.execute(
        "UPDATE faq_entries SET embedding = %s::vector, updated_at = now() WHERE id = %s",
        (to_pgvector(embedding), faq_id),
    )


def search_faq_by_embedding(conn, embedding, limit):
    vector = to_pgvector(embedding)
    return conn.execute(
        """
        SELECT id, category, subcategory, question, answer, requires_human,
               1 - (embedding <=> %s::vector) AS score
        FROM faq_entries
        WHERE status = 'active' AND embedding IS NOT NULL
        ORDER BY embedding <=> %s::vector
        LIMIT %s
        """,
        (vector, vector, limit),
    ).fetchall()


def to_pgvector(values):
    return "[" + ",".join(str(float(v)) for v in values) + "]"
