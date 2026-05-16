CREATE TEMP TABLE seed_users (
    student_id VARCHAR(32),
    professor_id VARCHAR(32),
    admin_id VARCHAR(32),
    name VARCHAR(120),
    role VARCHAR(20),
    password VARCHAR(120)
);

\copy seed_users FROM '/seed-data/users.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO users (student_id, professor_id, admin_id, name, role, password)
SELECT student_id, professor_id, admin_id, name, role, password
FROM seed_users
ON CONFLICT DO NOTHING;

CREATE TEMP TABLE seed_classrooms (
    classroom_code VARCHAR(32),
    name VARCHAR(120),
    building VARCHAR(120),
    floor_label VARCHAR(32)
);

\copy seed_classrooms FROM '/seed-data/classrooms.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO classrooms (classroom_code, name, building, floor_label)
SELECT classroom_code, name, building, floor_label
FROM seed_classrooms
ON CONFLICT (classroom_code) DO NOTHING;

CREATE TEMP TABLE seed_networks (
    classroom_code VARCHAR(32),
    ap_id VARCHAR(64),
    ssid VARCHAR(120),
    gateway_host VARCHAR(120),
    collection_mode VARCHAR(40)
);

\copy seed_networks FROM '/seed-data/classroom_networks.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO classroom_networks (classroom_id, ap_id, ssid, gateway_host, collection_mode)
SELECT c.id, n.ap_id, n.ssid, n.gateway_host, n.collection_mode
FROM seed_networks n
JOIN classrooms c ON c.classroom_code = n.classroom_code
ON CONFLICT (classroom_id, ap_id) DO NOTHING;

CREATE TEMP TABLE seed_access_points (
    collector_ap_id VARCHAR(64),
    label VARCHAR(120),
    management_ip VARCHAR(64),
    tailnet_ip VARCHAR(64),
    status VARCHAR(20)
);

\copy seed_access_points FROM '/seed-data/access_points.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO access_points (collector_ap_id, label, management_ip, tailnet_ip, status)
SELECT collector_ap_id, label, management_ip, tailnet_ip, status
FROM seed_access_points
ON CONFLICT (collector_ap_id) DO UPDATE
SET label = EXCLUDED.label,
    management_ip = EXCLUDED.management_ip,
    tailnet_ip = EXCLUDED.tailnet_ip,
    status = EXCLUDED.status,
    updated_at = NOW();

CREATE TEMP TABLE seed_access_point_interfaces (
    collector_ap_id VARCHAR(64),
    interface_id VARCHAR(64),
    ap_id VARCHAR(64),
    bssid VARCHAR(32)
);

\copy seed_access_point_interfaces FROM '/seed-data/access_point_interfaces.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO access_point_interfaces (access_point_id, interface_id, bssid, ssid, classroom_network_id)
SELECT ap.id, iface.interface_id, NULLIF(iface.bssid, ''), cn.ssid, cn.id
FROM seed_access_point_interfaces iface
JOIN access_points ap ON ap.collector_ap_id = iface.collector_ap_id
JOIN classroom_networks cn ON cn.ap_id = iface.ap_id
ON CONFLICT (access_point_id, interface_id) DO UPDATE
SET bssid = EXCLUDED.bssid,
    ssid = EXCLUDED.ssid,
    classroom_network_id = EXCLUDED.classroom_network_id;


CREATE TEMP TABLE seed_courses (
    course_code VARCHAR(32),
    title VARCHAR(200),
    professor_id VARCHAR(32)
);

\copy seed_courses FROM '/seed-data/courses.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO courses (course_code, title, professor_user_id)
SELECT s.course_code, s.title, u.id
FROM seed_courses s
JOIN users u ON u.professor_id = s.professor_id
ON CONFLICT (course_code) DO NOTHING;

CREATE TEMP TABLE seed_schedules (
    course_code VARCHAR(32),
    classroom_code VARCHAR(32),
    day_of_week SMALLINT,
    starts_at TIME,
    ends_at TIME
);

\copy seed_schedules FROM '/seed-data/course_schedules.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO course_schedules (course_id, classroom_id, day_of_week, starts_at, ends_at)
SELECT co.id, cl.id, s.day_of_week, s.starts_at, s.ends_at
FROM seed_schedules s
JOIN courses co ON co.course_code = s.course_code
JOIN classrooms cl ON cl.classroom_code = s.classroom_code;

CREATE TEMP TABLE seed_enrollments (
    course_code VARCHAR(32),
    student_id VARCHAR(32),
    status VARCHAR(20)
);

\copy seed_enrollments FROM '/seed-data/course_enrollments.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO course_enrollments (course_id, student_user_id, status)
SELECT co.id, u.id, e.status
FROM seed_enrollments e
JOIN courses co ON co.course_code = e.course_code
JOIN users u ON u.student_id = e.student_id
ON CONFLICT (course_id, student_user_id) DO NOTHING;

CREATE TEMP TABLE seed_devices (
    student_id VARCHAR(32),
    label VARCHAR(120),
    mac_address VARCHAR(17),
    status VARCHAR(20)
);

\copy seed_devices FROM '/seed-data/registered_devices.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO registered_devices (user_id, label, mac_address, status)
SELECT u.id, d.label, d.mac_address, d.status
FROM seed_devices d
JOIN users u ON u.student_id = d.student_id
ON CONFLICT (mac_address) DO NOTHING;

CREATE TEMP TABLE seed_notices (
    course_code VARCHAR(32),
    professor_id VARCHAR(32),
    title VARCHAR(200),
    body TEXT
);

\copy seed_notices FROM '/seed-data/notices.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO notices (course_id, author_user_id, title, body)
SELECT c.id, u.id, n.title, n.body
FROM seed_notices n
JOIN courses c ON c.course_code = n.course_code
JOIN users u ON u.professor_id = n.professor_id;
