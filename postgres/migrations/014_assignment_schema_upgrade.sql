-- Existing-volume upgrade for the assignment domain schema.
--
-- PostgreSQL runs postgres/init/*.sql only for brand-new data directories.
-- Run this idempotent migration against persisted Service postgres-data volumes
-- that predate assignment tables before enabling assignment-capable app images.

-- Assignment domain schema
-- One mutable submission row per assignment and student.
-- Files are stored on the backend local filesystem and only metadata is stored here.

CREATE TABLE IF NOT EXISTS assignments (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    opens_at TIMESTAMPTZ NOT NULL,
    due_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (due_at > opens_at)
);

COMMENT ON TABLE assignments IS 'Course assignment master records.';

CREATE INDEX IF NOT EXISTS idx_assignments_course_due_at
    ON assignments (course_id, due_at DESC);

CREATE TABLE IF NOT EXISTS assignment_submissions (
    id BIGSERIAL PRIMARY KEY,
    assignment_id BIGINT NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
    student_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    submission_text TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (assignment_id, student_user_id)
);

COMMENT ON TABLE assignment_submissions IS 'Latest submission per assignment and student.';

CREATE INDEX IF NOT EXISTS idx_assignment_submissions_assignment_student
    ON assignment_submissions (assignment_id, student_user_id);

CREATE INDEX IF NOT EXISTS idx_assignment_submissions_student_submitted_at
    ON assignment_submissions (student_user_id, submitted_at DESC);

CREATE TABLE IF NOT EXISTS assignment_submission_attachments (
    id BIGSERIAL PRIMARY KEY,
    submission_id BIGINT NOT NULL REFERENCES assignment_submissions(id) ON DELETE CASCADE,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(120),
    file_size_bytes INTEGER NOT NULL CHECK (file_size_bytes >= 0),
    storage_key VARCHAR(500) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE assignment_submission_attachments IS 'Attachment metadata for assignment submissions.';
COMMENT ON COLUMN assignment_submission_attachments.storage_key IS 'Internal backend storage path or key, not a public URL.';

CREATE INDEX IF NOT EXISTS idx_assignment_submission_attachments_submission
    ON assignment_submission_attachments (submission_id, created_at ASC);
