-- =========================================================
-- 강의 영상 게시판
-- =========================================================
CREATE TABLE IF NOT EXISTS course_videos (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,      -- 소속 강의
    author_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,   -- 작성자
    title VARCHAR(200) NOT NULL,                                               -- 제목
    body TEXT,                                                                 -- 영상 설명
    video_url TEXT NOT NULL CHECK (char_length(video_url) > 0),               -- 영상 파일/스트리밍 URL
    view_count INTEGER NOT NULL DEFAULT 0 CHECK (view_count >= 0),            -- 조회수
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),                             -- 생성 시각
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()                              -- 수정 시각
);

-- 조회/정렬 성능용 인덱스
CREATE INDEX IF NOT EXISTS idx_course_videos_course_id
    ON course_videos (course_id);

CREATE INDEX IF NOT EXISTS idx_course_videos_author_user_id
    ON course_videos (author_user_id);

CREATE INDEX IF NOT EXISTS idx_course_videos_created_at
    ON course_videos (created_at DESC);

-- 수정 시 updated_at 자동 갱신
DROP TRIGGER IF EXISTS trg_course_videos_updated_at ON course_videos;
CREATE TRIGGER trg_course_videos_updated_at
BEFORE UPDATE ON course_videos
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =========================================================
-- 영상 댓글 (영상 삭제 시 댓글 자동 삭제)
-- =========================================================
CREATE TABLE IF NOT EXISTS video_comments (
    id BIGSERIAL PRIMARY KEY,
    video_id BIGINT NOT NULL REFERENCES course_videos(id) ON DELETE CASCADE,  -- 대상 영상
    author_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,    -- 작성자
    body TEXT NOT NULL,                                                         -- 댓글 본문
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()                               -- 작성 시각
);

CREATE INDEX IF NOT EXISTS idx_video_comments_video_id
    ON video_comments (video_id);

CREATE INDEX IF NOT EXISTS idx_video_comments_author_user_id
    ON video_comments (author_user_id);

-- =========================================================
-- 강의 자료 게시판
-- =========================================================
CREATE TABLE IF NOT EXISTS course_materials (
    id BIGSERIAL PRIMARY KEY,
    course_id BIGINT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,        -- 소속 강의
    author_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,     -- 작성자
    title VARCHAR(200) NOT NULL,                                                 -- 제목
    body TEXT,                                                                   -- 자료 설명
    file_url TEXT NOT NULL CHECK (char_length(file_url) > 0),                   -- 자료 파일 URL
    view_count INTEGER NOT NULL DEFAULT 0 CHECK (view_count >= 0),              -- 조회수
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),                               -- 생성 시각
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()                                -- 수정 시각
);

CREATE INDEX IF NOT EXISTS idx_course_materials_course_id
    ON course_materials (course_id);

CREATE INDEX IF NOT EXISTS idx_course_materials_author_user_id
    ON course_materials (author_user_id);

CREATE INDEX IF NOT EXISTS idx_course_materials_created_at
    ON course_materials (created_at DESC);

DROP TRIGGER IF EXISTS trg_course_materials_updated_at ON course_materials;
CREATE TRIGGER trg_course_materials_updated_at
BEFORE UPDATE ON course_materials
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =========================================================
-- 자료 댓글 (자료 삭제 시 댓글 자동 삭제)
-- =========================================================
CREATE TABLE IF NOT EXISTS material_comments (
    id BIGSERIAL PRIMARY KEY,
    material_id BIGINT NOT NULL REFERENCES course_materials(id) ON DELETE CASCADE, -- 대상 자료
    author_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,         -- 작성자
    body TEXT NOT NULL,                                                              -- 댓글 본문
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()                                    -- 작성 시각
);

CREATE INDEX IF NOT EXISTS idx_material_comments_material_id
    ON material_comments (material_id);

CREATE INDEX IF NOT EXISTS idx_material_comments_author_user_id
    ON material_comments (author_user_id);
