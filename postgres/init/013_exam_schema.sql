-- Exam domain schema
-- Each attempt expires at:
-- min(started_at + time_limit_snapshot_minutes, exams.ends_at)
-- Exam ownership is derived from courses.professor_user_id.

CREATE TABLE IF NOT EXISTS exams (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    exam_type VARCHAR(20) NOT NULL DEFAULT 'quiz'
        CHECK (exam_type IN ('quiz', 'midterm', 'final', 'practice', 'custom')),
    status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'published', 'open', 'closed', 'archived')),
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    requires_presence BOOLEAN NOT NULL DEFAULT TRUE,
    late_entry_allowed BOOLEAN NOT NULL DEFAULT TRUE,
    auto_submit_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    shuffle_questions BOOLEAN NOT NULL DEFAULT FALSE,
    shuffle_options BOOLEAN NOT NULL DEFAULT FALSE,
    max_attempts INTEGER NOT NULL DEFAULT 1 CHECK (max_attempts > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (ends_at > starts_at)
);

COMMENT ON TABLE exams IS 'Exam master records bound to a course. Ownership is derived from the course owner.';
COMMENT ON COLUMN exams.duration_minutes IS 'Per-student time budget in minutes before the global ends_at cap is applied.';
COMMENT ON COLUMN exams.late_entry_allowed IS 'When false, students may not start after starts_at.';
COMMENT ON COLUMN exams.auto_submit_enabled IS 'When true, in-progress attempts should be auto-submitted at expires_at.';

CREATE INDEX IF NOT EXISTS idx_exams_course_status_starts_at
    ON exams (course_id, status, starts_at);

CREATE TABLE IF NOT EXISTS exam_questions (
    id BIGSERIAL PRIMARY KEY,
    exam_id BIGINT NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
    question_order INTEGER NOT NULL CHECK (question_order > 0),
    question_type VARCHAR(30) NOT NULL
        CHECK (question_type IN ('multiple_choice', 'true_false')),
    prompt TEXT NOT NULL,
    points NUMERIC(6,2) NOT NULL DEFAULT 1.00 CHECK (points >= 0),
    correct_answer_text TEXT,
    explanation TEXT,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (exam_id, question_order),
    UNIQUE (id, exam_id)
);

COMMENT ON TABLE exam_questions IS 'Questions that belong to an exam.';
COMMENT ON COLUMN exam_questions.correct_answer_text IS 'Canonical answer text for auto-gradable question types.';

CREATE INDEX IF NOT EXISTS idx_exam_questions_exam_order
    ON exam_questions (exam_id, question_order);

CREATE TABLE IF NOT EXISTS exam_question_options (
    id BIGSERIAL PRIMARY KEY,
    question_id BIGINT NOT NULL REFERENCES exam_questions(id) ON DELETE CASCADE,
    option_order INTEGER NOT NULL CHECK (option_order > 0),
    option_text TEXT NOT NULL,
    is_correct BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (question_id, option_order),
    UNIQUE (id, question_id)
);

COMMENT ON TABLE exam_question_options IS 'Answer choices for multiple-choice and true-false questions.';

CREATE INDEX IF NOT EXISTS idx_exam_question_options_question_order
    ON exam_question_options (question_id, option_order);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_exam_question_options_one_correct
    ON exam_question_options (question_id)
    WHERE is_correct;

CREATE TABLE IF NOT EXISTS exam_submissions (
    id BIGSERIAL PRIMARY KEY,
    exam_id BIGINT NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
    student_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    attempt_no INTEGER NOT NULL DEFAULT 1 CHECK (attempt_no > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'in_progress'
        CHECK (status IN ('in_progress', 'submitted', 'auto_submitted', 'graded', 'expired')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    submitted_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    time_limit_snapshot_minutes INTEGER NOT NULL CHECK (time_limit_snapshot_minutes > 0),
    score NUMERIC(8,2) CHECK (score >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (exam_id, student_user_id, attempt_no),
    UNIQUE (id, exam_id),
    CHECK (submitted_at IS NULL OR submitted_at >= started_at),
    CHECK (expires_at >= started_at)
);

COMMENT ON TABLE exam_submissions IS 'One student attempt for one exam.';
COMMENT ON COLUMN exam_submissions.expires_at IS 'Application-computed personal deadline capped by the exam ends_at.';
COMMENT ON COLUMN exam_submissions.time_limit_snapshot_minutes IS 'Duration copied at attempt start so later exam edits do not rewrite past attempts.';

CREATE INDEX IF NOT EXISTS idx_exam_submissions_exam_student
    ON exam_submissions (exam_id, student_user_id);

CREATE INDEX IF NOT EXISTS idx_exam_submissions_student_status
    ON exam_submissions (student_user_id, status);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_exam_submissions_one_in_progress
    ON exam_submissions (exam_id, student_user_id)
    WHERE status = 'in_progress';

CREATE TABLE IF NOT EXISTS exam_submission_answers (
    id BIGSERIAL PRIMARY KEY,
    exam_id BIGINT NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
    submission_id BIGINT NOT NULL,
    question_id BIGINT NOT NULL,
    selected_option_id BIGINT,
    answer_text TEXT,
    is_correct BOOLEAN,
    awarded_score NUMERIC(8,2) CHECK (awarded_score >= 0),
    answered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (submission_id, question_id),
    CONSTRAINT fk_exam_submission_answers_submission_exam
        FOREIGN KEY (submission_id, exam_id)
        REFERENCES exam_submissions(id, exam_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_exam_submission_answers_question_exam
        FOREIGN KEY (question_id, exam_id)
        REFERENCES exam_questions(id, exam_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_exam_submission_answers_option_question
        FOREIGN KEY (selected_option_id, question_id)
        REFERENCES exam_question_options(id, question_id)
        ON DELETE SET NULL
);

COMMENT ON TABLE exam_submission_answers IS 'Per-question answers captured for a student attempt.';
COMMENT ON COLUMN exam_submission_answers.selected_option_id IS 'Used for objective question types when an option is selected.';
COMMENT ON COLUMN exam_submission_answers.exam_id IS 'Redundant consistency key used to guarantee that a submission answer points to a question from the same exam.';

CREATE INDEX IF NOT EXISTS idx_exam_submission_answers_submission_question
    ON exam_submission_answers (submission_id, question_id);
