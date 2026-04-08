CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    student_id VARCHAR(32) UNIQUE,
    professor_id VARCHAR(32) UNIQUE,
    admin_id VARCHAR(32) UNIQUE,
    name VARCHAR(120) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('student', 'professor', 'admin')),
    password VARCHAR(120) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS classrooms (
    id BIGSERIAL PRIMARY KEY,
    classroom_code VARCHAR(32) NOT NULL UNIQUE,
    name VARCHAR(120) NOT NULL,
    building VARCHAR(120),
    floor_label VARCHAR(32),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS courses (
    id BIGSERIAL PRIMARY KEY,
    course_code VARCHAR(32) NOT NULL UNIQUE,
    title VARCHAR(200) NOT NULL,
    professor_user_id BIGINT REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS course_enrollments (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    student_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (course_id, student_user_id)
);

CREATE TABLE IF NOT EXISTS course_schedules (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    classroom_id BIGINT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
    day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    starts_at TIME NOT NULL,
    ends_at TIME NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notices (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT REFERENCES courses(id) ON DELETE CASCADE,
    author_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS classroom_networks (
    id BIGSERIAL PRIMARY KEY,
    classroom_id BIGINT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
    ap_id VARCHAR(64) NOT NULL,
    ssid VARCHAR(120) NOT NULL,
    gateway_host VARCHAR(120),
    signal_threshold_dbm INTEGER,
    collection_mode VARCHAR(40) NOT NULL DEFAULT 'openwrt-ssh',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (classroom_id, ap_id)
);

CREATE TABLE IF NOT EXISTS registered_devices (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label VARCHAR(120),
    mac_address VARCHAR(17) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_registered_devices_user_id
    ON registered_devices (user_id);

CREATE TABLE IF NOT EXISTS presence_eligibility_logs (
    id BIGSERIAL PRIMARY KEY,
    student_user_id BIGINT REFERENCES users(id),
    course_id BIGINT REFERENCES courses(id),
    classroom_id BIGINT REFERENCES classrooms(id),
    purpose VARCHAR(20) NOT NULL,
    eligible BOOLEAN NOT NULL,
    reason_code VARCHAR(64) NOT NULL,
    matched_device_mac VARCHAR(17),
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    observed_at TIMESTAMPTZ,
    snapshot_age_seconds INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS refresh_sessions (
    id BIGSERIAL PRIMARY KEY,
    session_key VARCHAR(128) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    current_token_hash VARCHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    replay_detected_at TIMESTAMPTZ,
    last_rotated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_sessions_user_id
    ON refresh_sessions (user_id);

CREATE TABLE IF NOT EXISTS attendance_sessions (
    id BIGSERIAL PRIMARY KEY,
    projection_key VARCHAR(255) NOT NULL,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    classroom_id BIGINT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
    session_date DATE NOT NULL,
    slot_start_at TIME NOT NULL,
    slot_end_at TIME NOT NULL,
    mode VARCHAR(16) NOT NULL CHECK (mode IN ('manual', 'smart', 'canceled')),
    status VARCHAR(16) NOT NULL CHECK (status IN ('active', 'closed', 'expired', 'canceled')),
    opened_by_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    latest_version INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS attendance_session_slots (
    id BIGSERIAL PRIMARY KEY,
    attendance_session_id BIGINT NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    projection_key VARCHAR(255) NOT NULL,
    classroom_id BIGINT NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
    session_date DATE NOT NULL,
    slot_start_at TIME NOT NULL,
    slot_end_at TIME NOT NULL,
    slot_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (attendance_session_id, projection_key)
);

CREATE TABLE IF NOT EXISTS attendance_records (
    id BIGSERIAL PRIMARY KEY,
    attendance_session_id BIGINT NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    projection_key VARCHAR(255) NOT NULL,
    student_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    final_status VARCHAR(16) NOT NULL CHECK (final_status IN ('present', 'absent', 'late', 'official', 'sick')),
    attendance_reason VARCHAR(500),
    finalized_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    finalized_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (attendance_session_id, projection_key, student_user_id)
);

CREATE TABLE IF NOT EXISTS attendance_status_audit_logs (
    id BIGSERIAL PRIMARY KEY,
    attendance_session_id BIGINT NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    projection_key VARCHAR(255) NOT NULL,
    student_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    actor_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    actor_role VARCHAR(16) NOT NULL,
    change_source VARCHAR(32) NOT NULL,
    previous_status VARCHAR(16),
    new_status VARCHAR(16),
    reason VARCHAR(500),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    version INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_attendance_session_slots_session_order
    ON attendance_session_slots (attendance_session_id, slot_order);

CREATE INDEX IF NOT EXISTS idx_attendance_session_slots_projection
    ON attendance_session_slots (projection_key);

CREATE INDEX IF NOT EXISTS idx_attendance_sessions_course_date
    ON attendance_sessions (course_id, session_date);

CREATE INDEX IF NOT EXISTS idx_attendance_records_student_session_projection
    ON attendance_records (student_user_id, attendance_session_id, projection_key);

CREATE INDEX IF NOT EXISTS idx_attendance_status_audit_logs_student_changed_at
    ON attendance_status_audit_logs (student_user_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_attendance_status_audit_logs_session_projection
    ON attendance_status_audit_logs (attendance_session_id, projection_key, changed_at DESC);
