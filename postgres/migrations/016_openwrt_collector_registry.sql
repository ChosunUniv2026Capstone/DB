CREATE TABLE IF NOT EXISTS access_points (
    id BIGSERIAL PRIMARY KEY,
    collector_ap_id VARCHAR(64) NOT NULL UNIQUE,
    label VARCHAR(120) NOT NULL,
    management_ip VARCHAR(64),
    tailnet_ip VARCHAR(64),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    token_hash VARCHAR(128),
    token_version INTEGER NOT NULL DEFAULT 0,
    token_revoked_at TIMESTAMPTZ,
    last_rotated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS access_point_interfaces (
    id BIGSERIAL PRIMARY KEY,
    access_point_id BIGINT NOT NULL REFERENCES access_points(id) ON DELETE CASCADE,
    interface_id VARCHAR(64) NOT NULL,
    bssid VARCHAR(32),
    ssid VARCHAR(120),
    classroom_network_id BIGINT NOT NULL REFERENCES classroom_networks(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (access_point_id, interface_id),
    UNIQUE (classroom_network_id)
);

CREATE INDEX IF NOT EXISTS idx_access_point_interfaces_network_id
    ON access_point_interfaces (classroom_network_id);

UPDATE classroom_networks
SET collection_mode = 'openwrt-push',
    gateway_host = CASE
        WHEN ap_id LIKE 'phy0-%' OR ap_id LIKE 'phy1-%' THEN '192.168.97.1'
        WHEN ap_id LIKE 'phy4-%' OR ap_id LIKE 'phy5-%' THEN '192.168.98.1'
        WHEN ap_id LIKE 'phy7-%' OR ap_id LIKE 'phy8-%' THEN '192.168.99.1'
        ELSE gateway_host
    END
WHERE ap_id IN ('phy0-ap0','phy1-ap0','phy4-ap0','phy5-ap0','phy7-ap0','phy8-ap0');

INSERT INTO access_points (collector_ap_id, label, management_ip, tailnet_ip, status)
VALUES
    ('openwrt-a', 'Demo AP A / B101', '192.168.97.1', '100.78.116.89', 'active'),
    ('openwrt-b', 'Demo AP B / B102', '192.168.98.1', '100.86.49.51', 'active'),
    ('openwrt-c', 'Demo AP C / C201', '192.168.99.1', '100.99.237.79', 'active')
ON CONFLICT (collector_ap_id) DO UPDATE
SET label = EXCLUDED.label,
    management_ip = EXCLUDED.management_ip,
    tailnet_ip = EXCLUDED.tailnet_ip,
    status = EXCLUDED.status,
    updated_at = NOW();

DELETE FROM access_point_interfaces api
USING access_points ap
WHERE api.access_point_id = ap.id
  AND ap.collector_ap_id IN ('openwrt-a', 'openwrt-b', 'openwrt-c')
  AND api.interface_id <> 'phy1-ap0';

INSERT INTO access_point_interfaces (access_point_id, interface_id, ssid, classroom_network_id)
SELECT ap.id, mapping.interface_id, cn.ssid, cn.id
FROM (VALUES
    ('openwrt-a', 'phy1-ap0', 'phy1-ap0'),
    ('openwrt-b', 'phy1-ap0', 'phy4-ap0'),
    ('openwrt-c', 'phy1-ap0', 'phy7-ap0')
) AS mapping(collector_ap_id, interface_id, classroom_ap_id)
JOIN access_points ap ON ap.collector_ap_id = mapping.collector_ap_id
JOIN classroom_networks cn ON cn.ap_id = mapping.classroom_ap_id
ON CONFLICT (access_point_id, interface_id) DO UPDATE
SET ssid = EXCLUDED.ssid,
    classroom_network_id = EXCLUDED.classroom_network_id;
