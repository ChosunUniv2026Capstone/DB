-- Existing-volume upgrade for selected LMS subset.
-- Run after 016_openwrt_collector_registry.sql on persisted Service deployments.
-- Mirrors postgres/init/016_selected_lms_subset.sql and
-- postgres/init/017_selected_lms_demo_seed.sql without psql include paths so it
-- can be executed from any operator working directory.

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

-- Demo seed data for selected LMS subset.
-- Provides one graded assignment/feedback example, one answered Q&A thread,
-- and one learning-progress snapshot without duplicating rows on replay.

WITH course AS (
    SELECT id FROM courses WHERE course_code = 'CSE116'
), professor AS (
    SELECT id FROM users WHERE professor_id = 'PRF002'
), student AS (
    SELECT id FROM users WHERE student_id = '20201239'
), inserted_assignment AS (
    INSERT INTO assignments (course_id, title, description, opens_at, due_at, max_score)
    SELECT course.id,
           '데모 과제: 출석 네트워크 분석',
           'OpenWrt AP 수집 데이터를 바탕으로 재실성 판단 흐름을 요약하세요.',
           TIMESTAMPTZ '2026-05-09 00:00:00+09',
           TIMESTAMPTZ '2026-05-23 23:59:00+09',
           100.00
    FROM course
    WHERE NOT EXISTS (
        SELECT 1
        FROM assignments existing
        WHERE existing.course_id = course.id
          AND existing.title = '데모 과제: 출석 네트워크 분석'
    )
    RETURNING id
), assignment_row AS (
    SELECT id FROM inserted_assignment
    UNION ALL
    SELECT assignments.id
    FROM assignments
    JOIN course ON course.id = assignments.course_id
    WHERE assignments.title = '데모 과제: 출석 네트워크 분석'
    LIMIT 1
)
INSERT INTO assignment_submissions (
    assignment_id,
    student_user_id,
    submission_text,
    submitted_at,
    score,
    feedback,
    graded_by_user_id,
    graded_at,
    grading_status
)
SELECT assignment_row.id,
       student.id,
       'AP snapshot soft/hard TTL과 push collector 구조를 비교했습니다.',
       TIMESTAMPTZ '2026-05-15 10:00:00+09',
       92.00,
       '근거와 장애 상황 설명이 명확합니다. TTL 경계 조건을 조금 더 보강하세요.',
       professor.id,
       TIMESTAMPTZ '2026-05-16 10:00:00+09',
       'graded'
FROM assignment_row, student, professor
ON CONFLICT (assignment_id, student_user_id) DO UPDATE
SET score = EXCLUDED.score,
    feedback = EXCLUDED.feedback,
    graded_by_user_id = EXCLUDED.graded_by_user_id,
    graded_at = EXCLUDED.graded_at,
    grading_status = EXCLUDED.grading_status,
    updated_at = NOW();

WITH course AS (
    SELECT id FROM courses WHERE course_code = 'CSE116'
), professor AS (
    SELECT id FROM users WHERE professor_id = 'PRF002'
), student AS (
    SELECT id FROM users WHERE student_id = '20201239'
), inserted_learning AS (
    INSERT INTO learning_items (course_id, created_by_user_id, title, description, item_type, sort_order, is_published, created_at, updated_at)
    SELECT course.id,
           professor.id,
           '데모 학습자료: SmartClass AP Collector',
           'OpenWrt local collector push 방식과 Redis snapshot 구조를 설명합니다.',
           'video',
           1,
           TRUE,
           TIMESTAMPTZ '2026-05-16 09:00:00+09',
           TIMESTAMPTZ '2026-05-16 09:00:00+09'
    FROM course, professor
    WHERE NOT EXISTS (
        SELECT 1
        FROM learning_items existing
        WHERE existing.course_id = course.id
          AND existing.title = '데모 학습자료: SmartClass AP Collector'
    )
    RETURNING id
), learning_row AS (
    SELECT id FROM inserted_learning
    UNION ALL
    SELECT learning_items.id
    FROM learning_items
    JOIN course ON course.id = learning_items.course_id
    WHERE learning_items.title = '데모 학습자료: SmartClass AP Collector'
    LIMIT 1
)
INSERT INTO learning_progress (learning_item_id, student_user_id, progress_percent, status, last_viewed_at, completed_at, updated_at)
SELECT learning_row.id,
       student.id,
       75.00,
       'in_progress',
       TIMESTAMPTZ '2026-05-16 13:00:00+09',
       NULL,
       TIMESTAMPTZ '2026-05-16 13:00:00+09'
FROM learning_row, student
ON CONFLICT (learning_item_id, student_user_id) DO UPDATE
SET progress_percent = EXCLUDED.progress_percent,
    status = EXCLUDED.status,
    last_viewed_at = EXCLUDED.last_viewed_at,
    completed_at = EXCLUDED.completed_at,
    updated_at = EXCLUDED.updated_at;

WITH course AS (
    SELECT id FROM courses WHERE course_code = 'CSE116'
), professor AS (
    SELECT id FROM users WHERE professor_id = 'PRF002'
), student AS (
    SELECT id FROM users WHERE student_id = '20201239'
), inserted_thread AS (
    INSERT INTO course_qna_threads (course_id, student_user_id, title, body, status, created_at, updated_at)
    SELECT course.id,
           student.id,
           '스마트 출석 인접성 확인 기준 문의',
           '동일 SSID에서 AP가 바뀌면 인접성 판단은 어떤 기준으로 처리되나요?',
           'answered',
           TIMESTAMPTZ '2026-05-16 14:00:00+09',
           TIMESTAMPTZ '2026-05-16 15:00:00+09'
    FROM course, student
    WHERE NOT EXISTS (
        SELECT 1
        FROM course_qna_threads existing
        WHERE existing.course_id = course.id
          AND existing.student_user_id = student.id
          AND existing.title = '스마트 출석 인접성 확인 기준 문의'
    )
    RETURNING id
), thread_row AS (
    SELECT id FROM inserted_thread
    UNION ALL
    SELECT course_qna_threads.id
    FROM course_qna_threads
    JOIN course ON course.id = course_qna_threads.course_id
    JOIN student ON student.id = course_qna_threads.student_user_id
    WHERE course_qna_threads.title = '스마트 출석 인접성 확인 기준 문의'
    LIMIT 1
), question_post AS (
    INSERT INTO course_qna_posts (thread_id, author_user_id, body, post_type, created_at)
    SELECT thread_row.id,
           student.id,
           '동일 SSID에서 AP가 바뀌면 인접성 판단은 어떤 기준으로 처리되나요?',
           'question',
           TIMESTAMPTZ '2026-05-16 14:00:00+09'
    FROM thread_row, student
    WHERE NOT EXISTS (
        SELECT 1
        FROM course_qna_posts existing
        WHERE existing.thread_id = thread_row.id
          AND existing.post_type = 'question'
          AND existing.body = '동일 SSID에서 AP가 바뀌면 인접성 판단은 어떤 기준으로 처리되나요?'
    )
)
INSERT INTO course_qna_posts (thread_id, author_user_id, body, post_type, created_at)
SELECT thread_row.id,
       professor.id,
       'collector payload의 classroom/network mapping과 등록 단말 매칭 결과를 기준으로 판정합니다.',
       'answer',
       TIMESTAMPTZ '2026-05-16 15:00:00+09'
FROM thread_row, professor
WHERE NOT EXISTS (
    SELECT 1
    FROM course_qna_posts existing
    WHERE existing.thread_id = thread_row.id
      AND existing.post_type = 'answer'
      AND existing.body = 'collector payload의 classroom/network mapping과 등록 단말 매칭 결과를 기준으로 판정합니다.'
);
