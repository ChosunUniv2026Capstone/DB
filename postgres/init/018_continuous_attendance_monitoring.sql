-- Continuous attendance monitoring schema and demo seed.
-- Adds the DB contract for continuous_presence_v1 without changing the
-- existing smart_window_v1 attendance history semantics.

ALTER TABLE attendance_sessions
    ADD COLUMN IF NOT EXISTS attendance_policy VARCHAR(32);

UPDATE attendance_sessions
SET attendance_policy = CASE
    WHEN mode = 'smart' THEN 'smart_window_v1'
    ELSE 'manual_v1'
END
WHERE attendance_policy IS NULL;

ALTER TABLE attendance_sessions
    ALTER COLUMN attendance_policy SET DEFAULT 'smart_window_v1',
    ALTER COLUMN attendance_policy SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_attendance_sessions_policy'
    ) THEN
        ALTER TABLE attendance_sessions
            ADD CONSTRAINT chk_attendance_sessions_policy
            CHECK (attendance_policy IN ('manual_v1', 'smart_window_v1', 'continuous_presence_v1'));
    END IF;
END $$;

COMMENT ON COLUMN attendance_sessions.attendance_policy IS 'Attendance session policy: manual_v1, legacy/default 10-minute smart_window_v1, or explicitly requested continuous_presence_v1 monitoring.';

CREATE INDEX IF NOT EXISTS idx_attendance_sessions_policy_status
    ON attendance_sessions (attendance_policy, status, session_date);

CREATE TABLE IF NOT EXISTS attendance_monitoring_leases (
    attendance_session_id BIGINT PRIMARY KEY REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    lease_owner VARCHAR(120) NOT NULL,
    lease_until TIMESTAMPTZ NOT NULL,
    heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE attendance_monitoring_leases IS 'Session-scoped DB lease so only one Backend worker ticks an active continuous_presence_v1 attendance session.';
COMMENT ON COLUMN attendance_monitoring_leases.lease_owner IS 'Backend worker/instance identifier that currently owns the monitoring lease.';
COMMENT ON COLUMN attendance_monitoring_leases.lease_until IS 'Lease expiry timestamp; another worker may take over after this time.';
COMMENT ON COLUMN attendance_monitoring_leases.heartbeat_at IS 'Last lease heartbeat/renewal timestamp from the owning worker.';

CREATE INDEX IF NOT EXISTS idx_attendance_monitoring_leases_until
    ON attendance_monitoring_leases (lease_until);

CREATE TABLE IF NOT EXISTS attendance_monitoring_states (
    id BIGSERIAL PRIMARY KEY,
    attendance_session_id BIGINT NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    projection_key VARCHAR(255) NOT NULL,
    student_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    slot_start_at TIME NOT NULL,
    slot_end_at TIME NOT NULL,
    last_accounted_until TIMESTAMPTZ,
    away_seconds INTEGER NOT NULL DEFAULT 0 CHECK (away_seconds >= 0),
    unknown_seconds_consumed INTEGER NOT NULL DEFAULT 0 CHECK (unknown_seconds_consumed >= 0 AND unknown_seconds_consumed <= 60),
    current_presence_state VARCHAR(24) NOT NULL DEFAULT 'outside_time'
        CHECK (current_presence_state IN ('outside_time', 'present', 'away', 'unknown')),
    last_presence_reason VARCHAR(128),
    status_candidate VARCHAR(16) NOT NULL DEFAULT 'present'
        CHECK (status_candidate IN ('present', 'late', 'absent')),
    finalized_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (attendance_session_id, projection_key, student_user_id),
    FOREIGN KEY (attendance_session_id, projection_key)
        REFERENCES attendance_session_slots(attendance_session_id, projection_key)
        ON DELETE CASCADE
);

COMMENT ON TABLE attendance_monitoring_states IS 'Student/slot accumulator for continuous_presence_v1: away time, unknown grace, current evidence state, and candidate final status.';
COMMENT ON COLUMN attendance_monitoring_states.last_accounted_until IS 'Server timestamp through which away/unknown/present time has been accounted.';
COMMENT ON COLUMN attendance_monitoring_states.away_seconds IS 'Cumulative away seconds since slot start; <600 present, 600-899 late, >=900 absent.';
COMMENT ON COLUMN attendance_monitoring_states.unknown_seconds_consumed IS 'AP/PRESENCE outage grace consumed before fail-closed away accounting; capped at 60 seconds.';
COMMENT ON COLUMN attendance_monitoring_states.current_presence_state IS 'Display/accounting state: outside_time, present, away, or unknown.';
COMMENT ON COLUMN attendance_monitoring_states.last_presence_reason IS 'Latest evidence reason or outage reason from Backend/PresenceService.';
COMMENT ON COLUMN attendance_monitoring_states.status_candidate IS 'Current automatic status candidate derived from away_seconds: present, late, or absent.';
COMMENT ON COLUMN attendance_monitoring_states.finalized_at IS 'Set when the candidate has been written to attendance_records through Backend finalization.';

CREATE INDEX IF NOT EXISTS idx_attendance_monitoring_states_session_slot
    ON attendance_monitoring_states (attendance_session_id, projection_key);

CREATE INDEX IF NOT EXISTS idx_attendance_monitoring_states_student
    ON attendance_monitoring_states (student_user_id, attendance_session_id);

CREATE INDEX IF NOT EXISTS idx_attendance_monitoring_states_unfinalized
    ON attendance_monitoring_states (attendance_session_id, finalized_at)
    WHERE finalized_at IS NULL;

-- Always-available QA course for continuous attendance monitoring. The course
-- uses B101/openwrt-push demo classroom evidence and a split daily schedule:
-- 00:00-12:00 plus 12:00-00:00. The second half is intentionally overnight so
-- Backend slot projection can produce the final 23:30-00:00 segment without a
-- non-portable 24:00 TIME value.
WITH professor AS (
    SELECT id FROM users WHERE professor_id = 'PRF002'
)
INSERT INTO courses (course_code, title, professor_user_id)
SELECT 'CSE999', 'Continuous Presence 24/7 Test Course', professor.id
FROM professor
ON CONFLICT (course_code) DO UPDATE
SET title = EXCLUDED.title,
    professor_user_id = EXCLUDED.professor_user_id,
    updated_at = NOW();

WITH course AS (
    SELECT id FROM courses WHERE course_code = 'CSE999'
), classroom AS (
    SELECT id FROM classrooms WHERE classroom_code = 'B101'
), slots(day_of_week, starts_at, ends_at) AS (
    VALUES
        (0, TIME '00:00:00', TIME '12:00:00'),
        (0, TIME '12:00:00', TIME '00:00:00'),
        (1, TIME '00:00:00', TIME '12:00:00'),
        (1, TIME '12:00:00', TIME '00:00:00'),
        (2, TIME '00:00:00', TIME '12:00:00'),
        (2, TIME '12:00:00', TIME '00:00:00'),
        (3, TIME '00:00:00', TIME '12:00:00'),
        (3, TIME '12:00:00', TIME '00:00:00'),
        (4, TIME '00:00:00', TIME '12:00:00'),
        (4, TIME '12:00:00', TIME '00:00:00'),
        (5, TIME '00:00:00', TIME '12:00:00'),
        (5, TIME '12:00:00', TIME '00:00:00'),
        (6, TIME '00:00:00', TIME '12:00:00'),
        (6, TIME '12:00:00', TIME '00:00:00')
)
INSERT INTO course_schedules (course_id, classroom_id, day_of_week, starts_at, ends_at)
SELECT course.id, classroom.id, slots.day_of_week, slots.starts_at, slots.ends_at
FROM course, classroom, slots
WHERE NOT EXISTS (
    SELECT 1
    FROM course_schedules existing
    WHERE existing.course_id = course.id
      AND existing.classroom_id = classroom.id
      AND existing.day_of_week = slots.day_of_week
      AND existing.starts_at = slots.starts_at
      AND existing.ends_at = slots.ends_at
);

WITH course AS (
    SELECT id FROM courses WHERE course_code = 'CSE999'
), students AS (
    SELECT id
    FROM users
    WHERE role = 'student'
      AND student_id IS NOT NULL
)
INSERT INTO course_enrollments (course_id, student_user_id, status)
SELECT course.id, students.id, 'active'
FROM course, students
ON CONFLICT (course_id, student_user_id) DO UPDATE
SET status = EXCLUDED.status;
