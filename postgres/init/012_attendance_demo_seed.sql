WITH demo_refs AS (
    SELECT
        course.id AS course_id,
        course.course_code,
        classroom.id AS classroom_id,
        classroom.classroom_code,
        professor.id AS professor_user_id,
        student_a.id AS student_a_user_id,
        student_b.id AS student_b_user_id
    FROM courses course
    JOIN classrooms classroom ON classroom.classroom_code = 'B101'
    JOIN users professor ON professor.professor_id = 'PRF002'
    JOIN users student_a ON student_a.student_id = '20201239'
    JOIN users student_b ON student_b.student_id = '20201240'
    WHERE course.course_code = 'CSE116'
),
insert_smart_session AS (
    INSERT INTO attendance_sessions (
        projection_key,
        course_id,
        classroom_id,
        session_date,
        slot_start_at,
        slot_end_at,
        mode,
        status,
        opened_by_user_id,
        opened_at,
        closed_at,
        expires_at,
        latest_version
    )
    SELECT
        'CSE116:B101:2026-03-09:15:00:00:15:30:00',
        course_id,
        classroom_id,
        DATE '2026-03-09',
        TIME '15:00:00',
        TIME '15:30:00',
        'smart',
        'closed',
        professor_user_id,
        TIMESTAMPTZ '2026-03-09 06:00:00+00',
        TIMESTAMPTZ '2026-03-09 06:12:00+00',
        TIMESTAMPTZ '2026-03-09 06:10:00+00',
        3
    FROM demo_refs
    RETURNING id
),
insert_canceled_session AS (
    INSERT INTO attendance_sessions (
        projection_key,
        course_id,
        classroom_id,
        session_date,
        slot_start_at,
        slot_end_at,
        mode,
        status,
        opened_by_user_id,
        opened_at,
        closed_at,
        expires_at,
        latest_version
    )
    SELECT
        'CSE116:B101:2026-03-16:15:00:00:15:30:00',
        course_id,
        classroom_id,
        DATE '2026-03-16',
        TIME '15:00:00',
        TIME '15:30:00',
        'canceled',
        'canceled',
        professor_user_id,
        TIMESTAMPTZ '2026-03-16 06:00:00+00',
        TIMESTAMPTZ '2026-03-16 06:00:00+00',
        NULL,
        1
    FROM demo_refs
    RETURNING id
),
insert_manual_session AS (
    INSERT INTO attendance_sessions (
        projection_key,
        course_id,
        classroom_id,
        session_date,
        slot_start_at,
        slot_end_at,
        mode,
        status,
        opened_by_user_id,
        opened_at,
        closed_at,
        expires_at,
        latest_version
    )
    SELECT
        'CSE116:B101:2026-03-23:15:00:00:15:30:00',
        course_id,
        classroom_id,
        DATE '2026-03-23',
        TIME '15:00:00',
        TIME '15:30:00',
        'manual',
        'closed',
        professor_user_id,
        TIMESTAMPTZ '2026-03-23 06:00:00+00',
        TIMESTAMPTZ '2026-03-23 06:20:00+00',
        NULL,
        2
    FROM demo_refs
    RETURNING id
),
insert_session_slots AS (
    INSERT INTO attendance_session_slots (
        attendance_session_id,
        projection_key,
        classroom_id,
        session_date,
        slot_start_at,
        slot_end_at,
        slot_order
    )
    SELECT
        insert_smart_session.id,
        'CSE116:B101:2026-03-09:15:00:00:15:30:00',
        demo_refs.classroom_id,
        DATE '2026-03-09',
        TIME '15:00:00',
        TIME '15:30:00',
        0
    FROM insert_smart_session, demo_refs
    UNION ALL
    SELECT
        insert_canceled_session.id,
        'CSE116:B101:2026-03-16:15:00:00:15:30:00',
        demo_refs.classroom_id,
        DATE '2026-03-16',
        TIME '15:00:00',
        TIME '15:30:00',
        0
    FROM insert_canceled_session, demo_refs
    UNION ALL
    SELECT
        insert_manual_session.id,
        'CSE116:B101:2026-03-23:15:00:00:15:30:00',
        demo_refs.classroom_id,
        DATE '2026-03-23',
        TIME '15:00:00',
        TIME '15:30:00',
        0
    FROM insert_manual_session, demo_refs
    RETURNING id
)
INSERT INTO attendance_records (
    attendance_session_id,
    projection_key,
    student_user_id,
    final_status,
    attendance_reason,
    finalized_by_user_id,
    finalized_at
)
SELECT insert_smart_session.id, 'CSE116:B101:2026-03-09:15:00:00:15:30:00', demo_refs.student_a_user_id, 'late', '지각 확인', demo_refs.professor_user_id, TIMESTAMPTZ '2026-03-09 06:12:00+00'
FROM insert_smart_session, demo_refs
UNION ALL
SELECT insert_smart_session.id, 'CSE116:B101:2026-03-09:15:00:00:15:30:00', demo_refs.student_b_user_id, 'present', '학생 self check-in', demo_refs.student_b_user_id, TIMESTAMPTZ '2026-03-09 06:05:00+00'
FROM insert_smart_session, demo_refs
UNION ALL
SELECT insert_manual_session.id, 'CSE116:B101:2026-03-23:15:00:00:15:30:00', demo_refs.student_a_user_id, 'official', '공결 승인', demo_refs.professor_user_id, TIMESTAMPTZ '2026-03-23 06:10:00+00'
FROM insert_manual_session, demo_refs
UNION ALL
SELECT insert_manual_session.id, 'CSE116:B101:2026-03-23:15:00:00:15:30:00', demo_refs.student_b_user_id, 'absent', '무단 결석', demo_refs.professor_user_id, TIMESTAMPTZ '2026-03-23 06:12:00+00'
FROM insert_manual_session, demo_refs;

WITH demo_refs AS (
    SELECT
        professor.id AS professor_user_id,
        student_a.id AS student_a_user_id,
        student_b.id AS student_b_user_id
    FROM users professor
    JOIN users student_a ON student_a.student_id = '20201239'
    JOIN users student_b ON student_b.student_id = '20201240'
    WHERE professor.professor_id = 'PRF002'
),
smart_session AS (
    SELECT id FROM attendance_sessions WHERE projection_key = 'CSE116:B101:2026-03-09:15:00:00:15:30:00'
),
manual_session AS (
    SELECT id FROM attendance_sessions WHERE projection_key = 'CSE116:B101:2026-03-23:15:00:00:15:30:00'
)
INSERT INTO attendance_status_audit_logs (
    attendance_session_id,
    projection_key,
    student_user_id,
    actor_user_id,
    actor_role,
    change_source,
    previous_status,
    new_status,
    reason,
    changed_at,
    version
)
SELECT smart_session.id, 'CSE116:B101:2026-03-09:15:00:00:15:30:00', demo_refs.student_a_user_id, demo_refs.student_a_user_id, 'student', 'self-checkin', NULL, 'present', '학생 self check-in', TIMESTAMPTZ '2026-03-09 06:03:00+00', 1
FROM smart_session, demo_refs
UNION ALL
SELECT smart_session.id, 'CSE116:B101:2026-03-09:15:00:00:15:30:00', demo_refs.student_a_user_id, demo_refs.professor_user_id, 'professor', 'professor-manual', 'present', 'late', '지각 확인', TIMESTAMPTZ '2026-03-09 06:12:00+00', 2
FROM smart_session, demo_refs
UNION ALL
SELECT smart_session.id, 'CSE116:B101:2026-03-09:15:00:00:15:30:00', demo_refs.student_b_user_id, demo_refs.student_b_user_id, 'student', 'self-checkin', NULL, 'present', '학생 self check-in', TIMESTAMPTZ '2026-03-09 06:05:00+00', 3
FROM smart_session, demo_refs
UNION ALL
SELECT manual_session.id, 'CSE116:B101:2026-03-23:15:00:00:15:30:00', demo_refs.student_a_user_id, demo_refs.professor_user_id, 'professor', 'professor-manual', NULL, 'official', '공결 승인', TIMESTAMPTZ '2026-03-23 06:10:00+00', 1
FROM manual_session, demo_refs
UNION ALL
SELECT manual_session.id, 'CSE116:B101:2026-03-23:15:00:00:15:30:00', demo_refs.student_b_user_id, demo_refs.professor_user_id, 'professor', 'professor-manual', NULL, 'absent', '무단 결석', TIMESTAMPTZ '2026-03-23 06:12:00+00', 2
FROM manual_session, demo_refs;
