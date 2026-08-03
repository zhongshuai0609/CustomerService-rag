-- PostgreSQL initialization script for the Lambda RAG customer service demo.
-- Run once before deploying the Lambda function:
--   psql "$DATABASE_URL" -f db_init.sql
--
-- The FAQ rows are inserted here for easy learning/deployment.
-- Embeddings are intentionally left NULL and are filled by lambda_function.py
-- through OpenAI's online embedding API on the first Lambda invocation.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS conversations (
    id          VARCHAR(255) PRIMARY KEY,
    user_id     VARCHAR(255) NOT NULL,
    title       VARCHAR(255),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id);

CREATE TABLE IF NOT EXISTS messages (
    id                  BIGSERIAL PRIMARY KEY,
    conversation_id     VARCHAR(255) NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    message_seq         INTEGER NOT NULL,
    role                VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant')),
    content             TEXT NOT NULL,
    structured_output   JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (conversation_id, message_seq, role)
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_seq ON messages(conversation_id, message_seq);

CREATE TABLE IF NOT EXISTS faq_entries (
    id                  INTEGER PRIMARY KEY,
    category            TEXT NOT NULL,
    subcategory         TEXT,
    question            TEXT NOT NULL,
    similar_questions   JSONB NOT NULL DEFAULT '[]'::jsonb,
    keywords            JSONB NOT NULL DEFAULT '[]'::jsonb,
    answer              TEXT NOT NULL,
    requires_human      BOOLEAN NOT NULL DEFAULT false,
    escalation          TEXT,
    applicable_models   JSONB NOT NULL DEFAULT '[]'::jsonb,
    source_ticket_ids   JSONB NOT NULL DEFAULT '[]'::jsonb,
    last_updated        DATE,
    status              TEXT NOT NULL DEFAULT 'active',
    language            TEXT NOT NULL DEFAULT 'en',
    confidence_threshold NUMERIC(4, 3),
    placeholders        JSONB NOT NULL DEFAULT '[]'::jsonb,
    media               JSONB NOT NULL DEFAULT '[]'::jsonb,
    tags                JSONB NOT NULL DEFAULT '[]'::jsonb,
    raw_data            JSONB NOT NULL,
    embedding           vector(1536),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_faq_entries_status ON faq_entries(status);
CREATE INDEX IF NOT EXISTS idx_faq_entries_embedding
    ON faq_entries USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 10)
    WHERE embedding IS NOT NULL;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_conversations_updated_at ON conversations;
CREATE TRIGGER trg_conversations_updated_at
BEFORE UPDATE ON conversations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_faq_entries_updated_at ON faq_entries;
CREATE TRIGGER trg_faq_entries_updated_at
BEFORE UPDATE ON faq_entries
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

WITH data AS (
    SELECT $faq$[
  {
    "id": 10,
    "category": "Logistics",
    "subcategory": "Order Tracking",
    "question": "Where is my order?",
    "similar_questions": [
      "When will my order arrive?",
      "What's the status of my order?",
      "Can you track my order?",
      "Has my order shipped yet?",
      "Where is my shipment?",
      "Is my order on its way?"
    ],
    "keywords": [
      "order status",
      "track order",
      "order tracking",
      "delivery status",
      "where is my order",
      "shipment status"
    ],
    "answer": "Your order #[ORDER_ID] is currently [STATUS]. Estimated delivery: [DATE]. Track here: [LINK]. If you don't see updates after 48 hours of receiving this message please reply and we'll investigate.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.7,
    "placeholders": [
      "ORDER_ID",
      "STATUS",
      "DATE",
      "LINK"
    ],
    "media": [],
    "tags": [
      "shipping",
      "tracking",
      "order-status"
    ]
  },
  {
    "id": 11,
    "category": "Logistics",
    "subcategory": "Damaged Package",
    "question": "My grill arrived damaged.",
    "similar_questions": [
      "The grill I received is damaged",
      "My grill came broken",
      "Grill arrived with damage",
      "I got my grill and it's damaged",
      "Grill was damaged during shipping",
      "My new grill has cracks/dents from transit"
    ],
    "keywords": [
      "damaged grill",
      "arrived damaged",
      "shipping damage",
      "replacement",
      "photo evidence",
      "claim"
    ],
    "answer": "I'm so sorry your grill arrived damaged. Please send photos of both the box and the grill to support@briskit.ai so we can file a claim with the carrier. Please do NOT discard the packaging since we may need additional photos. Once we receive your photos we'll ship a replacement immediately at no cost to you.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [
      "EMAIL"
    ],
    "media": [],
    "tags": [
      "shipping",
      "damage",
      "claim"
    ]
  },
  {
    "id": 12,
    "category": "Logistics",
    "subcategory": "Missing Parts",
    "question": "Parts are missing from my grill.",
    "similar_questions": [
      "I didn't get all the parts for my grill",
      "Some components of my grill are missing",
      "Missing parts in my grill shipment",
      "I'm missing some parts from the box",
      "Where are the missing parts for my grill?",
      "My grill is missing some pieces",
      "Not all parts were included with my grill"
    ],
    "keywords": [
      "missing parts",
      "grill parts missing",
      "replacement parts",
      "missing components",
      "order parts",
      "parts not included",
      "missing grill parts",
      "parts list"
    ],
    "answer": "We apologize for the inconvenience. Please first check the parts list in your manual against what you received since sometimes parts are hidden inside the firebox or under packaging. If items are confirmed missing email support@briskit.ai with your order number, the model, and a list of the missing parts. We will ship replacement parts to you ASAP at no charge.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [
      "EMAIL"
    ],
    "media": [],
    "tags": [
      "shipping",
      "missing-parts",
      "fulfillment"
    ]
  },
  {
    "id": 13,
    "category": "Logistics",
    "subcategory": "Change Address",
    "question": "I need to change my shipping address.",
    "similar_questions": [
      "Can I update my delivery address?",
      "How do I change my shipping address?",
      "I need to modify the address on my order.",
      "Is it possible to change my shipping address after placing the order?",
      "What should I do if I entered the wrong shipping address?"
    ],
    "keywords": [
      "change shipping address",
      "update address",
      "modify order address",
      "shipping address change",
      "order address update"
    ],
    "answer": "If your order hasn't shipped yet contact support@briskit.ai immediately with your order number and the new address. If your order has already shipped you'll need to contact the courier directly with your tracking number.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [
      "EMAIL"
    ],
    "media": [],
    "tags": [
      "shipping",
      "address"
    ]
  },
  {
    "id": 14,
    "category": "Partnerships",
    "subcategory": "Collaboration",
    "question": "I'd like to collaborate with Brisk It.",
    "similar_questions": [
      "How can I partner with Brisk It?",
      "I want to work with Brisk It.",
      "Who do I contact for collaboration opportunities?",
      "Is there a partnership program with Brisk It?",
      "How do I propose a collaboration with Brisk It?"
    ],
    "keywords": [
      "partnership",
      "collaboration",
      "Brisk It",
      "influencer",
      "contact",
      "proposal"
    ],
    "answer": "Thanks so much for reaching out. We deeply appreciate the interest in featuring us! Please direct your proposal to our partnerships team at influencer@briskitgrills.com and they'll be happy to explore it further with you.",
    "requires_human": false,
    "escalation": "none",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.7,
    "placeholders": [],
    "media": [],
    "tags": [
      "partnerships",
      "influencer"
    ]
  },
  {
    "id": 20,
    "category": "Product Setup",
    "subcategory": "Assembly Instructions",
    "question": "How do I assemble my grill?",
    "similar_questions": [
      "How do I put my grill together?",
      "What are the assembly instructions?",
      "Where can I find the assembly manual?",
      "Can you help me assemble the grill?",
      "Is there a guide for setting up the grill?",
      "I need assistance with grill assembly.",
      "How to set up the grill step by step?"
    ],
    "keywords": [
      "assemble",
      "assembly",
      "manual",
      "setup",
      "guide",
      "instructions"
    ],
    "answer": "Your grill comes with a printed assembly guide in the box. You can also access the digital version at briskit.ai/manuals. If you're stuck at a specific step reply with the step number and a photo and we'll help directly.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.7,
    "placeholders": [],
    "media": [
      "https://briskit.ai/manuals"
    ],
    "tags": [
      "setup",
      "assembly",
      "manual"
    ]
  },
  {
    "id": 21,
    "category": "Technical Issues",
    "subcategory": "Ignition",
    "question": "My grill won't ignite.",
    "similar_questions": [
      "Why won't my grill light?",
      "Grill not igniting",
      "Ignition failure on my grill",
      "My grill won't start",
      "No flame when I try to ignite"
    ],
    "keywords": [
      "ignite",
      "ignition",
      "won't start",
      "no flame",
      "pellet grill not lighting"
    ],
    "answer": "Please ensure the hopper has pellets, the fire pot is clear of ash, and the grill is plugged in. Try running a shutdown cycle and restarting. If the issue persists email support@briskit.ai with your model and a description of what happens when you try to start it.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [],
    "media": [],
    "tags": [
      "technical",
      "ignition",
      "startup"
    ]
  },
  {
    "id": 22,
    "category": "Technical Issues",
    "subcategory": "Wifi Connection",
    "question": "My grill won't connect to wifi.",
    "similar_questions": [
      "My grill is not connecting to WiFi",
      "Why won't my grill connect to the Wi-Fi network?",
      "Grill WiFi connection failed",
      "Can't get my grill to connect to Wi-Fi",
      "How do I fix my grill's WiFi connection?",
      "Grill won't pair with Wi-Fi during setup"
    ],
    "keywords": [
      "wifi connection",
      "grill wifi",
      "connectivity issue",
      "setup wifi",
      "2.4GHz",
      "bluetooth setup",
      "network connection",
      "grill not connecting"
    ],
    "answer": "Make sure you are connecting to a 2.4GHz network and that your phone's bluetooth is on during setup. Restart the grill and try again. If the issue persists email support@briskit.ai with your model and router details.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [],
    "media": [],
    "tags": [
      "technical",
      "wifi",
      "connectivity"
    ]
  },
  {
    "id": 23,
    "category": "Technical Issues",
    "subcategory": "Firmware",
    "question": "How do I update my grill's firmware?",
    "similar_questions": [
      "How do I get the latest firmware for my grill?",
      "Why isn't my grill updating the firmware automatically?",
      "Can I manually update the grill's firmware?",
      "How to check and update the firmware version on my smart grill?",
      "My grill isn't updating firmware, what should I do?",
      "Is there a way to force a firmware update on the Brisk It app?"
    ],
    "keywords": [
      "firmware update",
      "grill firmware",
      "update grill",
      "Brisk It app",
      "firmware version",
      "automatic update",
      "wifi update"
    ],
    "answer": "Firmware updates are delivered automatically through the Brisk It app when your grill is connected to wifi. Make sure your app is up to date and your grill is connected. If you are not seeing an update prompt email support@briskit.ai with your model and current firmware version.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [],
    "media": [],
    "tags": [
      "technical",
      "firmware",
      "update"
    ]
  },
  {
    "id": 24,
    "category": "Technical Issues",
    "subcategory": "Mechanical Failure",
    "question": "My grill has a mechanical problem.",
    "similar_questions": [
      "My grill has a mechanical issue.",
      "There's a mechanical problem with my grill.",
      "I'm having a mechanical malfunction with my grill.",
      "My grill is not working mechanically.",
      "The grill has a mechanical failure."
    ],
    "keywords": [
      "mechanical problem",
      "grill malfunction",
      "mechanical issue",
      "grill repair",
      "support email"
    ],
    "answer": "We are sorry to hear that. Please email support@briskit.ai with your order number, model, a description of the issue, and photos or video if possible. We will respond within 48 hours to help diagnose and resolve the problem.",
    "requires_human": true,
    "escalation": "hard",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [],
    "media": [],
    "tags": [
      "technical",
      "mechanical",
      "failure"
    ]
  },
  {
    "id": 30,
    "category": "Cooking Usage",
    "subcategory": "Temperature",
    "question": "What temperature should I cook my food at?",
    "similar_questions": [
      "What temperature do I set for grilling?",
      "What's the right temperature for cooking on this grill?",
      "How hot should the grill be for different foods?",
      "Can you tell me the recommended cooking temperatures?",
      "What temperature should I use for steak/chicken/veggies?"
    ],
    "keywords": [
      "temperature",
      "cook",
      "grill",
      "food",
      "recommended",
      "setting"
    ],
    "answer": "I have forwarded you to a human agent. In the meantime please check out our Brisk It app as it contains very detailed information on cooking instructions.",
    "requires_human": true,
    "escalation": "hard",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.7,
    "placeholders": [],
    "media": [],
    "tags": [
      "cooking",
      "temperature"
    ]
  },
  {
    "id": 31,
    "category": "Cooking Usage",
    "subcategory": "Smoke",
    "question": "How do I get more smoke flavor from my grill?",
    "similar_questions": [
      "How can I increase the smoke flavor on my grill?",
      "Any tips for getting more smoky taste from my grill?",
      "How do I make my food smokier on this grill?",
      "What can I do to enhance the smoke flavor?",
      "How to get a stronger smoke flavor when cooking?"
    ],
    "keywords": [
      "smoke flavor",
      "increase smoke",
      "smoky taste",
      "smoke settings",
      "more smoke"
    ],
    "answer": "I have forwarded you to a human agent. In the meantime please check out our Brisk It app as it contains very detailed information on cooking instructions including smoke settings.",
    "requires_human": true,
    "escalation": "hard",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.7,
    "placeholders": [],
    "media": [],
    "tags": [
      "cooking",
      "smoke"
    ]
  },
  {
    "id": 32,
    "category": "Cooking Usage",
    "subcategory": "Pellet",
    "question": "What type of pellets should I use?",
    "similar_questions": [
      "Which pellets are best for this grill?",
      "Can I use any wood pellets?",
      "What pellets are recommended?",
      "What kind of pellets should I buy?",
      "Are there specific pellets I need to use?"
    ],
    "keywords": [
      "pellets",
      "pellet types",
      "recommended pellets",
      "wood pellets",
      "pellet selection"
    ],
    "answer": "I have forwarded you to a human agent. In the meantime please check out our Brisk It app as it contains very detailed information on pellet types and recommendations.",
    "requires_human": true,
    "escalation": "hard",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.7,
    "placeholders": [],
    "media": [],
    "tags": [
      "cooking",
      "pellets"
    ]
  },
  {
    "id": 40,
    "category": "After-sales Support",
    "subcategory": "Refund Policy",
    "question": "How do I return my grill for a refund?",
    "similar_questions": [
      "How can I get a refund for my grill?",
      "What is the return process for the grill?",
      "Can I return my grill for a money back guarantee?",
      "How do I initiate a return for my smart grill?",
      "What are the steps to return the grill for a refund?",
      "How long do I have to return my grill under the trial?",
      "Do I have to pay for return shipping?",
      "What is the return policy for grills bought from briskit.ai?"
    ],
    "keywords": [
      "grill return",
      "refund process",
      "return authorization",
      "90-day trial",
      "return policy",
      "return shipping",
      "briskit return"
    ],
    "answer": "For grills purchased from briskit.ai we offer a 90-Day Risk-Free Trial. Email support@briskit.ai within 90 days to get a Return Authorization number. You must have this before shipping. Package your grill with all original parts and ship with tracking. Customer pays return shipping. Refund processed 2-3 weeks after we receive and inspect. Limited to 1 return per household per year. Original shipping charges non-refundable. For Amazon or Walmart purchases you must return through that retailer's policy. Accessories can be returned within 14 days if unused. Consumables are NOT returnable.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [
      "EMAIL"
    ],
    "media": [],
    "tags": [
      "after-sales",
      "refund",
      "return"
    ]
  },
  {
    "id": 41,
    "category": "After-sales Support",
    "subcategory": "Exchange Process",
    "question": "Can I exchange my grill for a different model?",
    "similar_questions": [
      "Can I swap my grill for a different model?",
      "Is it possible to change my grill model after buying?",
      "How do I exchange my grill for another version?",
      "Can I upgrade or downgrade my grill model?",
      "What's the process to get a different model grill?"
    ],
    "keywords": [
      "exchange",
      "different model",
      "upgrade",
      "downgrade",
      "30 days",
      "return for model change"
    ],
    "answer": "Exchanges for different models are available within 30 days of delivery. Email support@briskit.ai with your order number and the model you want. You'll pay the price difference if upgrading or receive credit if downgrading. After 30 days exchanges are not available.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [
      "EMAIL"
    ],
    "media": [],
    "tags": [
      "after-sales",
      "exchange",
      "replacement"
    ]
  },
  {
    "id": 42,
    "category": "After-sales Support",
    "subcategory": "Warranty",
    "question": "What does the warranty cover?",
    "similar_questions": [
      "What is covered under the warranty?",
      "What does the limited warranty include?",
      "What are the warranty terms?",
      "Does the warranty cover manufacturing defects?",
      "What is not covered by the warranty?",
      "How do I file a warranty claim?",
      "What do I need to submit for a warranty claim?"
    ],
    "keywords": [
      "warranty coverage",
      "limited warranty",
      "manufacturing defects",
      "warranty claim",
      "proof of purchase",
      "serial number",
      "warranty exclusions"
    ],
    "answer": "We offer a 3-year limited warranty covering manufacturing defects in materials and workmanship under normal residential use. To file a claim email support@briskit.ai with proof of purchase, photos or video of the issue, serial number, and a detailed description. Warranty does NOT cover normal wear and tear, cosmetic damage, paint, rust, misuse, grease fires, neglect, unauthorized modifications, commercial use, or temperature variance. Customer is responsible for shipping costs unless required by law.",
    "requires_human": false,
    "escalation": "soft",
    "applicable_models": [
      "all"
    ],
    "source_ticket_ids": [],
    "last_updated": "2026-06-07",
    "status": "active",
    "language": "en",
    "confidence_threshold": 0.72,
    "placeholders": [
      "EMAIL"
    ],
    "media": [],
    "tags": [
      "after-sales",
      "warranty"
    ]
  }
]$faq$::jsonb AS items
)
INSERT INTO faq_entries (
    id, category, subcategory, question, similar_questions, keywords, answer,
    requires_human, escalation, applicable_models, source_ticket_ids, last_updated,
    status, language, confidence_threshold, placeholders, media, tags, raw_data
)
SELECT
    (item->>'id')::integer,
    item->>'category',
    item->>'subcategory',
    item->>'question',
    COALESCE(item->'similar_questions', '[]'::jsonb),
    COALESCE(item->'keywords', '[]'::jsonb),
    item->>'answer',
    COALESCE((item->>'requires_human')::boolean, false),
    item->>'escalation',
    COALESCE(item->'applicable_models', '[]'::jsonb),
    COALESCE(item->'source_ticket_ids', '[]'::jsonb),
    NULLIF(item->>'last_updated', '')::date,
    COALESCE(item->>'status', 'active'),
    COALESCE(item->>'language', 'en'),
    NULLIF(item->>'confidence_threshold', '')::numeric,
    COALESCE(item->'placeholders', '[]'::jsonb),
    COALESCE(item->'media', '[]'::jsonb),
    COALESCE(item->'tags', '[]'::jsonb),
    item
FROM data, jsonb_array_elements(data.items) AS item
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category,
    subcategory = EXCLUDED.subcategory,
    question = EXCLUDED.question,
    similar_questions = EXCLUDED.similar_questions,
    keywords = EXCLUDED.keywords,
    answer = EXCLUDED.answer,
    requires_human = EXCLUDED.requires_human,
    escalation = EXCLUDED.escalation,
    applicable_models = EXCLUDED.applicable_models,
    source_ticket_ids = EXCLUDED.source_ticket_ids,
    last_updated = EXCLUDED.last_updated,
    status = EXCLUDED.status,
    language = EXCLUDED.language,
    confidence_threshold = EXCLUDED.confidence_threshold,
    placeholders = EXCLUDED.placeholders,
    media = EXCLUDED.media,
    tags = EXCLUDED.tags,
    raw_data = EXCLUDED.raw_data,
    embedding = CASE
        WHEN faq_entries.question IS DISTINCT FROM EXCLUDED.question
          OR faq_entries.similar_questions IS DISTINCT FROM EXCLUDED.similar_questions
          OR faq_entries.keywords IS DISTINCT FROM EXCLUDED.keywords
          OR faq_entries.answer IS DISTINCT FROM EXCLUDED.answer
        THEN NULL
        ELSE faq_entries.embedding
    END;
