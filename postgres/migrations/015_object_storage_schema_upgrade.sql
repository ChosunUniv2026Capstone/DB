-- Existing-volume upgrade for object-storage metadata and deletion outbox.
--
-- Run after 014_assignment_schema_upgrade.sql on persisted Service
-- postgres-data volumes that predate the object-storage schema. This file
-- mirrors postgres/init/015_object_storage_schema.sql and remains idempotent so
-- operators can safely rerun it after a partially completed rollout.

-- Garage/S3-compatible object storage metadata foundation.
-- The database stores object metadata and durable deletion jobs only; object bytes
-- stay behind Backend storage APIs.

ALTER TABLE assignment_submission_attachments
    ADD COLUMN IF NOT EXISTS storage_provider VARCHAR(20) NOT NULL DEFAULT 'local',
    ADD COLUMN IF NOT EXISTS bucket_name VARCHAR(120) NOT NULL DEFAULT 'local',
    ADD COLUMN IF NOT EXISTS checksum_sha256 VARCHAR(64);

COMMENT ON COLUMN assignment_submission_attachments.storage_provider IS 'Provider-neutral storage backend identifier such as local or s3.';
COMMENT ON COLUMN assignment_submission_attachments.bucket_name IS 'Storage bucket/container name; not exposed to Front.';
COMMENT ON COLUMN assignment_submission_attachments.checksum_sha256 IS 'Optional lowercase hex SHA-256 checksum captured by Backend when available.';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_assignment_submission_attachments_storage_provider'
    ) THEN
        ALTER TABLE assignment_submission_attachments
            ADD CONSTRAINT chk_assignment_submission_attachments_storage_provider
            CHECK (storage_provider IN ('local', 's3'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_assignment_submission_attachments_bucket_name'
    ) THEN
        ALTER TABLE assignment_submission_attachments
            ADD CONSTRAINT chk_assignment_submission_attachments_bucket_name
            CHECK (bucket_name <> '');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_assignment_submission_attachments_storage_key_internal'
    ) THEN
        ALTER TABLE assignment_submission_attachments
            ADD CONSTRAINT chk_assignment_submission_attachments_storage_key_internal
            CHECK (storage_key <> '' AND storage_key !~* '^https?://');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_assignment_submission_attachments_checksum_sha256'
    ) THEN
        ALTER TABLE assignment_submission_attachments
            ADD CONSTRAINT chk_assignment_submission_attachments_checksum_sha256
            CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS learning_items (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    created_by_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    item_type VARCHAR(20) NOT NULL DEFAULT 'file'
        CHECK (item_type IN ('document', 'video', 'file', 'link')),
    external_url TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_published BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK ((item_type = 'link' AND external_url IS NOT NULL) OR (item_type <> 'link'))
);

COMMENT ON TABLE learning_items IS 'Persisted course learning materials owned by Backend; Front no longer treats learning content as local-only state.';
COMMENT ON COLUMN learning_items.external_url IS 'Optional external link for link-type learning items; uploaded files use learning_item_attachments.';

CREATE INDEX IF NOT EXISTS idx_learning_items_course_published_sort
    ON learning_items (course_id, is_published, sort_order, created_at DESC);

CREATE TABLE IF NOT EXISTS learning_item_attachments (
    id BIGSERIAL PRIMARY KEY,
    learning_item_id BIGINT NOT NULL REFERENCES learning_items(id) ON DELETE CASCADE,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(120),
    file_size_bytes BIGINT NOT NULL CHECK (file_size_bytes >= 0),
    storage_provider VARCHAR(20) NOT NULL DEFAULT 's3' CHECK (storage_provider IN ('local', 's3')),
    bucket_name VARCHAR(120) NOT NULL DEFAULT 'smart-class' CHECK (bucket_name <> ''),
    storage_key VARCHAR(700) NOT NULL CHECK (storage_key <> '' AND storage_key !~* '^https?://'),
    checksum_sha256 VARCHAR(64) CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE learning_item_attachments IS 'Object metadata for course learning materials and lecture videos.';
COMMENT ON COLUMN learning_item_attachments.storage_key IS 'Internal object key, for example learning/{course_code}/{item_id}/{uuid}_{filename}.';

CREATE INDEX IF NOT EXISTS idx_learning_item_attachments_item
    ON learning_item_attachments (learning_item_id, created_at ASC);

CREATE TABLE IF NOT EXISTS notice_attachments (
    id BIGSERIAL PRIMARY KEY,
    notice_id BIGINT NOT NULL REFERENCES notices(id) ON DELETE CASCADE,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(120),
    file_size_bytes BIGINT NOT NULL CHECK (file_size_bytes >= 0),
    storage_provider VARCHAR(20) NOT NULL DEFAULT 's3' CHECK (storage_provider IN ('local', 's3')),
    bucket_name VARCHAR(120) NOT NULL DEFAULT 'smart-class' CHECK (bucket_name <> ''),
    storage_key VARCHAR(700) NOT NULL CHECK (storage_key <> '' AND storage_key !~* '^https?://'),
    checksum_sha256 VARCHAR(64) CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE notice_attachments IS 'Object metadata for course or global notice attachments.';
COMMENT ON COLUMN notice_attachments.storage_key IS 'Internal object key, for example notices/{notice_id}/{uuid}_{filename}.';

CREATE INDEX IF NOT EXISTS idx_notice_attachments_notice
    ON notice_attachments (notice_id, created_at ASC);

CREATE TABLE IF NOT EXISTS exam_question_attachments (
    id BIGSERIAL PRIMARY KEY,
    question_id BIGINT NOT NULL REFERENCES exam_questions(id) ON DELETE CASCADE,
    attachment_role VARCHAR(20) NOT NULL DEFAULT 'prompt'
        CHECK (attachment_role IN ('prompt', 'explanation')),
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(120),
    file_size_bytes BIGINT NOT NULL CHECK (file_size_bytes >= 0),
    storage_provider VARCHAR(20) NOT NULL DEFAULT 's3' CHECK (storage_provider IN ('local', 's3')),
    bucket_name VARCHAR(120) NOT NULL DEFAULT 'smart-class' CHECK (bucket_name <> ''),
    storage_key VARCHAR(700) NOT NULL CHECK (storage_key <> '' AND storage_key !~* '^https?://'),
    checksum_sha256 VARCHAR(64) CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE exam_question_attachments IS 'Object metadata for professor-authored exam question or explanation media.';
COMMENT ON COLUMN exam_question_attachments.storage_key IS 'Internal object key, for example exams/{exam_id}/questions/{question_id}/{uuid}_{filename}.';

CREATE INDEX IF NOT EXISTS idx_exam_question_attachments_question
    ON exam_question_attachments (question_id, created_at ASC);

CREATE TABLE IF NOT EXISTS exam_answer_attachments (
    id BIGSERIAL PRIMARY KEY,
    answer_id BIGINT NOT NULL REFERENCES exam_submission_answers(id) ON DELETE CASCADE,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(120),
    file_size_bytes BIGINT NOT NULL CHECK (file_size_bytes >= 0),
    storage_provider VARCHAR(20) NOT NULL DEFAULT 's3' CHECK (storage_provider IN ('local', 's3')),
    bucket_name VARCHAR(120) NOT NULL DEFAULT 'smart-class' CHECK (bucket_name <> ''),
    storage_key VARCHAR(700) NOT NULL CHECK (storage_key <> '' AND storage_key !~* '^https?://'),
    checksum_sha256 VARCHAR(64) CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE exam_answer_attachments IS 'Future-compatible object metadata for student exam answer files; first-pass objective exams do not require file-answer UI.';
COMMENT ON COLUMN exam_answer_attachments.storage_key IS 'Internal object key, for example exams/{exam_id}/submissions/{submission_id}/answers/{answer_id}/{uuid}_{filename}.';

CREATE INDEX IF NOT EXISTS idx_exam_answer_attachments_answer
    ON exam_answer_attachments (answer_id, created_at ASC);

CREATE TABLE IF NOT EXISTS report_exports (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT REFERENCES courses(id) ON DELETE SET NULL,
    requested_by_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    report_domain VARCHAR(20) NOT NULL DEFAULT 'attendance'
        CHECK (report_domain IN ('attendance', 'grade', 'assignment', 'exam')),
    export_format VARCHAR(20) NOT NULL DEFAULT 'csv'
        CHECK (export_format IN ('csv', 'pdf')),
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(120),
    file_size_bytes BIGINT NOT NULL CHECK (file_size_bytes >= 0),
    storage_provider VARCHAR(20) NOT NULL DEFAULT 's3' CHECK (storage_provider IN ('local', 's3')),
    bucket_name VARCHAR(120) NOT NULL DEFAULT 'smart-class' CHECK (bucket_name <> ''),
    storage_key VARCHAR(700) NOT NULL CHECK (storage_key <> '' AND storage_key !~* '^https?://'),
    checksum_sha256 VARCHAR(64) CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$'),
    status VARCHAR(20) NOT NULL DEFAULT 'ready'
        CHECK (status IN ('pending', 'ready', 'failed', 'deleted')),
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE report_exports IS 'Metadata for generated report files; first pass stores attendance CSV exports only, other domains are future-compatible.';
COMMENT ON COLUMN report_exports.storage_key IS 'Internal object key, for example reports/{domain}/{course_code}/{yyyy}/{mm}/{uuid}_{filename}.';

CREATE INDEX IF NOT EXISTS idx_report_exports_course_domain_created
    ON report_exports (course_id, report_domain, created_at DESC);

CREATE TABLE IF NOT EXISTS object_deletion_jobs (
    id BIGSERIAL PRIMARY KEY,
    storage_provider VARCHAR(20) NOT NULL CHECK (storage_provider IN ('local', 's3')),
    bucket_name VARCHAR(120) NOT NULL CHECK (bucket_name <> ''),
    storage_key VARCHAR(700) NOT NULL CHECK (storage_key <> '' AND storage_key !~* '^https?://'),
    owner_domain VARCHAR(80) NOT NULL,
    owner_id BIGINT,
    reason VARCHAR(80) NOT NULL DEFAULT 'metadata_deleted',
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    CHECK ((status = 'completed' AND completed_at IS NOT NULL) OR (status <> 'completed'))
);

COMMENT ON TABLE object_deletion_jobs IS 'Durable outbox for DB-driven immediate object deletion after metadata delete/replace.';
COMMENT ON COLUMN object_deletion_jobs.owner_domain IS 'Domain/table context that owned the deleted object metadata.';
COMMENT ON COLUMN object_deletion_jobs.owner_id IS 'Owning domain row id captured from the deleted metadata row when available.';

CREATE INDEX IF NOT EXISTS idx_object_deletion_jobs_status_created
    ON object_deletion_jobs (status, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_object_deletion_jobs_object_active
    ON object_deletion_jobs (storage_provider, bucket_name, storage_key)
    WHERE status IN ('pending', 'processing');

CREATE OR REPLACE FUNCTION enqueue_object_deletion_job()
RETURNS TRIGGER AS $$
DECLARE
    owner_domain_value TEXT := TG_ARGV[0];
    owner_id_column TEXT := TG_ARGV[1];
    owner_id_value BIGINT;
BEGIN
    IF OLD.storage_key IS NULL OR btrim(OLD.storage_key) = '' THEN
        RETURN OLD;
    END IF;

    IF owner_id_column IS NOT NULL AND owner_id_column <> '' THEN
        owner_id_value := NULLIF(to_jsonb(OLD)->>owner_id_column, '')::BIGINT;
    END IF;

    INSERT INTO object_deletion_jobs (
        storage_provider,
        bucket_name,
        storage_key,
        owner_domain,
        owner_id,
        reason
    )
    SELECT
        OLD.storage_provider,
        OLD.bucket_name,
        OLD.storage_key,
        owner_domain_value,
        owner_id_value,
        'metadata_deleted'
    WHERE NOT EXISTS (
        SELECT 1
        FROM object_deletion_jobs existing
        WHERE existing.storage_provider = OLD.storage_provider
          AND existing.bucket_name = OLD.bucket_name
          AND existing.storage_key = OLD.storage_key
          AND existing.status IN ('pending', 'processing')
    );

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_assignment_submission_attachments_object_delete ON assignment_submission_attachments;
CREATE TRIGGER trg_assignment_submission_attachments_object_delete
    AFTER DELETE ON assignment_submission_attachments
    FOR EACH ROW EXECUTE FUNCTION enqueue_object_deletion_job('assignment_submission', 'submission_id');

DROP TRIGGER IF EXISTS trg_learning_item_attachments_object_delete ON learning_item_attachments;
CREATE TRIGGER trg_learning_item_attachments_object_delete
    AFTER DELETE ON learning_item_attachments
    FOR EACH ROW EXECUTE FUNCTION enqueue_object_deletion_job('learning_item', 'learning_item_id');

DROP TRIGGER IF EXISTS trg_notice_attachments_object_delete ON notice_attachments;
CREATE TRIGGER trg_notice_attachments_object_delete
    AFTER DELETE ON notice_attachments
    FOR EACH ROW EXECUTE FUNCTION enqueue_object_deletion_job('notice', 'notice_id');

DROP TRIGGER IF EXISTS trg_exam_question_attachments_object_delete ON exam_question_attachments;
CREATE TRIGGER trg_exam_question_attachments_object_delete
    AFTER DELETE ON exam_question_attachments
    FOR EACH ROW EXECUTE FUNCTION enqueue_object_deletion_job('exam_question', 'question_id');

DROP TRIGGER IF EXISTS trg_exam_answer_attachments_object_delete ON exam_answer_attachments;
CREATE TRIGGER trg_exam_answer_attachments_object_delete
    AFTER DELETE ON exam_answer_attachments
    FOR EACH ROW EXECUTE FUNCTION enqueue_object_deletion_job('exam_submission_answer', 'answer_id');

DROP TRIGGER IF EXISTS trg_report_exports_object_delete ON report_exports;
CREATE TRIGGER trg_report_exports_object_delete
    AFTER DELETE ON report_exports
    FOR EACH ROW EXECUTE FUNCTION enqueue_object_deletion_job('report_export', 'id');
