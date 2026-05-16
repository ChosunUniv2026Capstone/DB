-- Selected LMS subset schema.
-- Adds grading/feedback, Q&A, and learning-progress DB contracts for the
-- first demo/operation scope. The file is intentionally idempotent so it can
-- be replayed safely.

ALTER TABLE assignments
    ADD COLUMN IF NOT EXISTS max_score NUMERIC(8,2);

UPDATE assignments
SET max_score = 100.00
WHERE max_score IS NULL;

ALTER TABLE assignments
    ALTER COLUMN max_score SET DEFAULT 100.00,
    ALTER COLUMN max_score SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_assignments_max_score_positive'
    ) THEN
        ALTER TABLE assignments
            ADD CONSTRAINT chk_assignments_max_score_positive
            CHECK (max_score > 0);
    END IF;
END $$;

COMMENT ON COLUMN assignments.max_score IS 'Assignment maximum score for selected LMS grade summaries; existing rows default to 100.00.';

ALTER TABLE assignment_submissions
    ADD COLUMN IF NOT EXISTS score NUMERIC(8,2),
    ADD COLUMN IF NOT EXISTS feedback TEXT,
    ADD COLUMN IF NOT EXISTS graded_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS graded_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS grading_status VARCHAR(20);

UPDATE assignment_submissions
SET grading_status = 'submitted'
WHERE grading_status IS NULL;

ALTER TABLE assignment_submissions
    ALTER COLUMN grading_status SET DEFAULT 'submitted',
    ALTER COLUMN grading_status SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_assignment_submissions_score_nonnegative'
    ) THEN
        ALTER TABLE assignment_submissions
            ADD CONSTRAINT chk_assignment_submissions_score_nonnegative
            CHECK (score IS NULL OR score >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_assignment_submissions_grading_status'
    ) THEN
        ALTER TABLE assignment_submissions
            ADD CONSTRAINT chk_assignment_submissions_grading_status
            CHECK (grading_status IN ('submitted', 'graded', 'returned'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_assignment_submissions_graded_at_consistency'
    ) THEN
        ALTER TABLE assignment_submissions
            ADD CONSTRAINT chk_assignment_submissions_graded_at_consistency
            CHECK (
                (grading_status = 'submitted' AND graded_at IS NULL AND score IS NULL)
                OR grading_status IN ('graded', 'returned')
            );
    END IF;
END $$;

COMMENT ON COLUMN assignment_submissions.score IS 'Professor-assigned score; NULL means ungraded.';
COMMENT ON COLUMN assignment_submissions.feedback IS 'Professor feedback shown to the student.';
COMMENT ON COLUMN assignment_submissions.graded_by_user_id IS 'Professor user who last graded or returned this submission.';
COMMENT ON COLUMN assignment_submissions.graded_at IS 'Timestamp of the last grading/return action.';
COMMENT ON COLUMN assignment_submissions.grading_status IS 'Selected LMS submission state: submitted, graded, or returned.';

CREATE INDEX IF NOT EXISTS idx_assignment_submissions_grading_status
    ON assignment_submissions (assignment_id, grading_status);

CREATE TABLE IF NOT EXISTS course_qna_threads (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    student_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'answered', 'closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (btrim(title) <> ''),
    CHECK (btrim(body) <> '')
);

COMMENT ON TABLE course_qna_threads IS 'Student-authored course Q&A/inquiry threads for the selected LMS subset.';
COMMENT ON COLUMN course_qna_threads.status IS 'Thread state visible to students and professors: open, answered, or closed.';

CREATE INDEX IF NOT EXISTS idx_course_qna_threads_course_status_updated
    ON course_qna_threads (course_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_course_qna_threads_student_updated
    ON course_qna_threads (student_user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS course_qna_posts (
    id BIGSERIAL PRIMARY KEY,
    thread_id BIGINT NOT NULL REFERENCES course_qna_threads(id) ON DELETE CASCADE,
    author_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    post_type VARCHAR(20) NOT NULL DEFAULT 'comment'
        CHECK (post_type IN ('question', 'answer', 'comment')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (btrim(body) <> '')
);

COMMENT ON TABLE course_qna_posts IS 'Posts inside a course Q&A thread: initial question, professor answer, or comments.';
COMMENT ON COLUMN course_qna_posts.post_type IS 'Q&A post type: question, answer, or comment.';

CREATE INDEX IF NOT EXISTS idx_course_qna_posts_thread_created
    ON course_qna_posts (thread_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_course_qna_posts_author_created
    ON course_qna_posts (author_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS learning_progress (
    id BIGSERIAL PRIMARY KEY,
    learning_item_id BIGINT NOT NULL REFERENCES learning_items(id) ON DELETE CASCADE,
    student_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    progress_percent NUMERIC(5,2) NOT NULL DEFAULT 0.00
        CHECK (progress_percent >= 0 AND progress_percent <= 100),
    status VARCHAR(20) NOT NULL DEFAULT 'not_started'
        CHECK (status IN ('not_started', 'in_progress', 'completed')),
    last_viewed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (learning_item_id, student_user_id),
    CHECK (status <> 'completed' OR progress_percent = 100.00)
);

COMMENT ON TABLE learning_progress IS 'Per-student learning material progress snapshot for selected LMS progress APIs.';
COMMENT ON COLUMN learning_progress.progress_percent IS 'Progress percentage from 0 through 100.';
COMMENT ON COLUMN learning_progress.status IS 'Learning progress state: not_started, in_progress, or completed.';

CREATE INDEX IF NOT EXISTS idx_learning_progress_student_status
    ON learning_progress (student_user_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_learning_progress_item_status
    ON learning_progress (learning_item_id, status, updated_at DESC);
