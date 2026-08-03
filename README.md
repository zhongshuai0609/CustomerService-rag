# Customer Service RAG Lambda

基于LLM RAG的客服系统：
- Lambda 入口：`lambda_function.lambda_handler`
- 数据库：PostgreSQL + pgvector
- 向量化：OpenAI 在线 embedding API

## 部署前准备

1. 在 PostgreSQL 执行初始化 SQL：

```bash
psql "$DATABASE_URL" -f db_init.sql
```

2. 配置 Lambda 环境变量：

```bash
DATABASE_URL=postgresql://user:password@host:5432/dbname
OPENAI_API_KEY=your_openai_api_key
LLM_MODEL=gpt-5.6-luna
EMBEDDING_MODEL=text-embedding-3-small
LOG_LEVEL=INFO
```

## Warmup 和 FAQ Embedding

线上每 5 分钟 warmup 调用一次 Lambda 时，传这个事件：

```json
{
  "hello": "just4warmingup"
}
```

代码会在 warmup 调用中查找 `embedding IS NULL` 的 FAQ，并调用 OpenAI embedding API 生成向量。普通客服请求不会批量刷新 FAQ embedding，避免影响用户响应时间。

FAQ 内容更新后，把对应行的 `embedding` 置空即可：

```sql
UPDATE faq_entries
SET answer = 'new answer', embedding = NULL
WHERE id = 10;
```

## 本地打包

如果在 macOS 上打包给 AWS Lambda 使用，依赖必须按 Lambda 的 Linux 平台下载。每次打包前都要删除旧的 `package/`，避免把 macOS wheel 或旧版本 `psycopg_binary` 混进 zip。

```bash
./scripts/build_zip.sh
```

`psycopg[binary]` 会同时安装 `psycopg` 和 `psycopg_binary`。这两个包必须来自同一次 Linux 平台安装；如果复用旧 `package/`，就容易出现 `no pq wrapper available`。

如需调整 Python 版本或 Lambda 平台：

```bash
PYTHON_VERSION=3.12 LAMBDA_PLATFORM=manylinux2014_x86_64 ./scripts/build_zip.sh
```

## 请求示例

```json
{
  "user_id": "test_user_001",
  "conversation_id": "1000000001",
  "message_seq": 1,
  "message": "Where is my order?"
}
```

`conversation_id` 和 `message_seq` 必须由调用方传入。`message_seq` 需要大于当前会话已有的最大轮次，允许跳号，但不能重复或回退。
