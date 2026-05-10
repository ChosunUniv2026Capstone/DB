\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    professor_id BIGINT;
    student_id BIGINT;
    course_id BIGINT;
    assignment_id BIGINT;
    submission_id BIGINT;
    learning_item_id BIGINT;
    notice_id BIGINT;
    exam_id BIGINT;
    question_id BIGINT;
    option_id BIGINT;
    exam_submission_id BIGINT;
    answer_id BIGINT;
    report_export_id BIGINT;
    jobs INTEGER;
BEGIN
    INSERT INTO users (professor_id, name, role, password)
    VALUES ('prof-obj-test', 'Object Professor', 'professor', 'devpass123')
    RETURNING id INTO professor_id;

    INSERT INTO users (student_id, name, role, password)
    VALUES ('stu-obj-test', 'Object Student', 'student', 'devpass123')
    RETURNING id INTO student_id;

    INSERT INTO courses (course_code, title, professor_user_id)
    VALUES ('OBJ101', 'Object Storage Contract', professor_id)
    RETURNING id INTO course_id;

    INSERT INTO assignments (course_id, title, description, opens_at, due_at)
    VALUES (course_id, 'Storage Assignment', 'Trigger fixture', NOW(), NOW() + INTERVAL '1 day')
    RETURNING id INTO assignment_id;

    INSERT INTO assignment_submissions (assignment_id, student_user_id, submission_text)
    VALUES (assignment_id, student_id, 'fixture')
    RETURNING id INTO submission_id;

    INSERT INTO assignment_submission_attachments (
        submission_id, original_filename, stored_filename, mime_type, file_size_bytes,
        storage_provider, bucket_name, storage_key
    ) VALUES (
        submission_id, 'submission.txt', 'submission.txt', 'text/plain', 7,
        's3', 'smart-class', 'assignments/1/submissions/1/students/1/submission.txt'
    );

    DELETE FROM assignment_submissions WHERE id = submission_id;

    SELECT COUNT(*) INTO jobs
    FROM object_deletion_jobs
    WHERE storage_key = 'assignments/1/submissions/1/students/1/submission.txt'
      AND owner_domain = 'assignment_submission'
      AND owner_id = submission_id
      AND status = 'pending';

    IF jobs <> 1 THEN
        RAISE EXCEPTION 'expected assignment cascade deletion job, found %', jobs;
    END IF;

    INSERT INTO learning_items (course_id, created_by_user_id, title, description, item_type, is_published)
    VALUES (course_id, professor_id, 'Lecture 1', 'video', 'video', true)
    RETURNING id INTO learning_item_id;

    INSERT INTO learning_item_attachments (
        learning_item_id, original_filename, stored_filename, mime_type, file_size_bytes, storage_key
    ) VALUES (
        learning_item_id, 'lecture.mp4', 'lecture.mp4', 'video/mp4', 100, 'learning/OBJ101/1/lecture.mp4'
    );

    DELETE FROM learning_items WHERE id = learning_item_id;

    SELECT COUNT(*) INTO jobs
    FROM object_deletion_jobs
    WHERE storage_key = 'learning/OBJ101/1/lecture.mp4'
      AND owner_domain = 'learning_item'
      AND owner_id = learning_item_id;

    IF jobs <> 1 THEN
        RAISE EXCEPTION 'expected learning cascade deletion job, found %', jobs;
    END IF;

    INSERT INTO notices (course_id, author_user_id, title, body)
    VALUES (course_id, professor_id, 'Notice', 'with attachment')
    RETURNING id INTO notice_id;

    INSERT INTO notice_attachments (
        notice_id, original_filename, stored_filename, mime_type, file_size_bytes, storage_key
    ) VALUES (
        notice_id, 'notice.pdf', 'notice.pdf', 'application/pdf', 42, 'notices/1/notice.pdf'
    );

    DELETE FROM notices WHERE id = notice_id;

    SELECT COUNT(*) INTO jobs
    FROM object_deletion_jobs
    WHERE storage_key = 'notices/1/notice.pdf'
      AND owner_domain = 'notice'
      AND owner_id = notice_id;

    IF jobs <> 1 THEN
        RAISE EXCEPTION 'expected notice cascade deletion job, found %', jobs;
    END IF;

    INSERT INTO exams (
        course_id, title, description, starts_at, ends_at, duration_minutes
    ) VALUES (
        course_id, 'Object Exam', 'fixture', NOW(), NOW() + INTERVAL '1 day', 30
    ) RETURNING id INTO exam_id;

    INSERT INTO exam_questions (exam_id, question_order, question_type, prompt, correct_answer_text)
    VALUES (exam_id, 1, 'multiple_choice', 'Prompt', 'A')
    RETURNING id INTO question_id;

    INSERT INTO exam_question_options (question_id, option_order, option_text, is_correct)
    VALUES (question_id, 1, 'A', true)
    RETURNING id INTO option_id;

    INSERT INTO exam_question_attachments (
        question_id, original_filename, stored_filename, mime_type, file_size_bytes, storage_key
    ) VALUES (
        question_id, 'prompt.png', 'prompt.png', 'image/png', 12, 'exams/1/questions/1/prompt.png'
    );

    INSERT INTO exam_submissions (
        exam_id, student_user_id, attempt_no, expires_at, time_limit_snapshot_minutes
    ) VALUES (
        exam_id, student_id, 1, NOW() + INTERVAL '30 minutes', 30
    ) RETURNING id INTO exam_submission_id;

    INSERT INTO exam_submission_answers (
        exam_id, submission_id, question_id, selected_option_id, answer_text
    ) VALUES (
        exam_id, exam_submission_id, question_id, option_id, 'A'
    ) RETURNING id INTO answer_id;

    INSERT INTO exam_answer_attachments (
        answer_id, original_filename, stored_filename, mime_type, file_size_bytes, storage_key
    ) VALUES (
        answer_id, 'answer.txt', 'answer.txt', 'text/plain', 5, 'exams/1/submissions/1/answers/1/answer.txt'
    );

    DELETE FROM exams WHERE id = exam_id;

    SELECT COUNT(*) INTO jobs
    FROM object_deletion_jobs
    WHERE storage_key = 'exams/1/questions/1/prompt.png'
      AND owner_domain = 'exam_question'
      AND owner_id = question_id;

    IF jobs <> 1 THEN
        RAISE EXCEPTION 'expected exam question cascade deletion job, found %', jobs;
    END IF;

    SELECT COUNT(*) INTO jobs
    FROM object_deletion_jobs
    WHERE storage_key = 'exams/1/submissions/1/answers/1/answer.txt'
      AND owner_domain = 'exam_submission_answer'
      AND owner_id = answer_id;

    IF jobs <> 1 THEN
        RAISE EXCEPTION 'expected exam answer cascade deletion job, found %', jobs;
    END IF;

    INSERT INTO report_exports (
        course_id, requested_by_user_id, report_domain, export_format,
        original_filename, stored_filename, mime_type, file_size_bytes, storage_key
    ) VALUES (
        course_id, professor_id, 'attendance', 'csv',
        'attendance.csv', 'attendance.csv', 'text/csv', 21, 'reports/attendance/OBJ101/2026/05/attendance.csv'
    ) RETURNING id INTO report_export_id;

    DELETE FROM report_exports WHERE id = report_export_id;

    SELECT COUNT(*) INTO jobs
    FROM object_deletion_jobs
    WHERE storage_key = 'reports/attendance/OBJ101/2026/05/attendance.csv'
      AND owner_domain = 'report_export'
      AND owner_id = report_export_id;

    IF jobs <> 1 THEN
        RAISE EXCEPTION 'expected report export deletion job, found %', jobs;
    END IF;

    INSERT INTO object_deletion_jobs (
        storage_provider, bucket_name, storage_key, owner_domain, owner_id
    ) VALUES (
        's3', 'smart-class', 'learning/OBJ101/duplicate.pdf', 'learning_item', 9999
    );

    INSERT INTO learning_items (course_id, created_by_user_id, title, item_type)
    VALUES (course_id, professor_id, 'Duplicate guard', 'file')
    RETURNING id INTO learning_item_id;

    INSERT INTO learning_item_attachments (
        learning_item_id, original_filename, stored_filename, mime_type, file_size_bytes, storage_key
    ) VALUES (
        learning_item_id, 'duplicate.pdf', 'duplicate.pdf', 'application/pdf', 1, 'learning/OBJ101/duplicate.pdf'
    );

    DELETE FROM learning_items WHERE id = learning_item_id;

    SELECT COUNT(*) INTO jobs
    FROM object_deletion_jobs
    WHERE storage_key = 'learning/OBJ101/duplicate.pdf'
      AND status IN ('pending', 'processing');

    IF jobs <> 1 THEN
        RAISE EXCEPTION 'expected duplicate guard to keep one active deletion job, found %', jobs;
    END IF;
END $$;

ROLLBACK;
