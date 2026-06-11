-- Smoke test for continuous_presence_v1 DB contract.
-- Run after postgres/init/*.sql or after applying migration 018 to an existing DB.
-- The test writes inside a transaction and rolls back all fixture rows.

BEGIN;

DO $$
DECLARE
    v_course_id BIGINT;
    v_classroom_id BIGINT;
    v_professor_user_id BIGINT;
    v_student_user_id BIGINT;
    v_session_id BIGINT;
    v_cse999_schedule_count INTEGER;
    v_cse999_enrollment_count INTEGER;
    v_student_count INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'attendance_sessions'
          AND column_name = 'attendance_policy'
    ) THEN
        RAISE EXCEPTION 'attendance_sessions.attendance_policy is missing';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'attendance_monitoring_leases') THEN
        RAISE EXCEPTION 'attendance_monitoring_leases table is missing';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'attendance_monitoring_states') THEN
        RAISE EXCEPTION 'attendance_monitoring_states table is missing';
    END IF;

    SELECT COUNT(*) INTO v_cse999_schedule_count
    FROM course_schedules cs
    JOIN courses c ON c.id = cs.course_id
    WHERE c.course_code = 'CSE999';

    IF v_cse999_schedule_count <> 14 THEN
        RAISE EXCEPTION 'CSE999 24/7 schedule expected 14 rows, got %', v_cse999_schedule_count;
    END IF;

    SELECT COUNT(*) INTO v_cse999_enrollment_count
    FROM course_enrollments ce
    JOIN courses c ON c.id = ce.course_id
    WHERE c.course_code = 'CSE999'
      AND ce.status = 'active';

    SELECT COUNT(*) INTO v_student_count
    FROM users
    WHERE role = 'student'
      AND student_id IS NOT NULL;

    IF v_cse999_enrollment_count <> v_student_count THEN
        RAISE EXCEPTION 'CSE999 expected active enrollments for all % students, got %', v_student_count, v_cse999_enrollment_count;
    END IF;

    SELECT c.id, cl.id, professor.id, student.id
    INTO v_course_id, v_classroom_id, v_professor_user_id, v_student_user_id
    FROM courses c
    JOIN classrooms cl ON cl.classroom_code = 'B101'
    JOIN users professor ON professor.professor_id = 'PRF002'
    JOIN users student ON student.student_id = '20201239'
    WHERE c.course_code = 'CSE999';

    INSERT INTO attendance_sessions (
        projection_key,
        course_id,
        classroom_id,
        session_date,
        slot_start_at,
        slot_end_at,
        mode,
        status,
        attendance_policy,
        opened_by_user_id,
        opened_at,
        expires_at
    ) VALUES (
        'CSE999:B101:2026-06-11:00:00:00:00:30:00',
        v_course_id,
        v_classroom_id,
        DATE '2026-06-11',
        TIME '00:00:00',
        TIME '00:30:00',
        'smart',
        'active',
        'continuous_presence_v1',
        v_professor_user_id,
        TIMESTAMPTZ '2026-06-11 00:00:00+09',
        TIMESTAMPTZ '2026-06-11 00:30:00+09'
    )
    RETURNING id INTO v_session_id;

    INSERT INTO attendance_session_slots (
        attendance_session_id,
        projection_key,
        classroom_id,
        session_date,
        slot_start_at,
        slot_end_at,
        slot_order
    ) VALUES (
        v_session_id,
        'CSE999:B101:2026-06-11:00:00:00:00:30:00',
        v_classroom_id,
        DATE '2026-06-11',
        TIME '00:00:00',
        TIME '00:30:00',
        0
    );

    INSERT INTO attendance_monitoring_leases (
        attendance_session_id,
        lease_owner,
        lease_until,
        heartbeat_at
    ) VALUES (
        v_session_id,
        'continuous-attendance-sql-smoke',
        NOW() + INTERVAL '30 seconds',
        NOW()
    );

    INSERT INTO attendance_monitoring_states (
        attendance_session_id,
        projection_key,
        student_user_id,
        slot_start_at,
        slot_end_at,
        last_accounted_until,
        away_seconds,
        unknown_seconds_consumed,
        current_presence_state,
        last_presence_reason,
        status_candidate
    ) VALUES (
        v_session_id,
        'CSE999:B101:2026-06-11:00:00:00:00:30:00',
        v_student_user_id,
        TIME '00:00:00',
        TIME '00:30:00',
        TIMESTAMPTZ '2026-06-11 00:00:10+09',
        610,
        60,
        'away',
        'AP_OFFLINE',
        'late'
    );

    IF NOT EXISTS (
        SELECT 1
        FROM attendance_monitoring_states ams
        WHERE ams.attendance_session_id = v_session_id
          AND ams.projection_key = 'CSE999:B101:2026-06-11:00:00:00:00:30:00'
          AND ams.student_user_id = v_student_user_id
          AND ams.status_candidate = 'late'
    ) THEN
        RAISE EXCEPTION 'continuous monitoring state smoke insert did not persist';
    END IF;
END $$;

ROLLBACK;
