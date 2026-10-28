-- Starter schema; Codex must add migrations, ownership policies and indexes.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE app_users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), auth_kind text NOT NULL DEFAULT 'guest', created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE people (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
 display_name text NOT NULL, birth_date date NOT NULL, birth_time_local time NOT NULL,
 birth_timezone text NOT NULL, birth_place_name text NOT NULL,
 latitude numeric(9,6) NOT NULL CHECK(latitude BETWEEN -90 AND 90),
 longitude numeric(9,6) NOT NULL CHECK(longitude BETWEEN -180 AND 180),
 time_accuracy text NOT NULL DEFAULT 'exact', revision integer NOT NULL DEFAULT 1,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_people_owner ON people(owner_id);
CREATE TABLE matches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
 person1_id uuid NOT NULL REFERENCES people(id), person2_id uuid NOT NULL REFERENCES people(id),
 person1_revision integer NOT NULL, person2_revision integer NOT NULL,
 settings_json jsonb NOT NULL, settings_hash text NOT NULL, engine_version text,
 status text NOT NULL DEFAULT 'pending', facts_json jsonb, narrative_json jsonb,
 failure_code text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(person1_id <> person2_id)
);
CREATE INDEX idx_matches_owner ON matches(owner_id);
CREATE TABLE comparisons (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
 person1_id uuid NOT NULL REFERENCES people(id), settings_json jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE comparison_items (
 comparison_id uuid NOT NULL REFERENCES comparisons(id) ON DELETE CASCADE,
 person2_id uuid NOT NULL REFERENCES people(id), match_id uuid REFERENCES matches(id),
 PRIMARY KEY(comparison_id,person2_id)
);
CREATE TABLE reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
 match_id uuid NOT NULL REFERENCES matches(id) ON DELETE CASCADE, locale text NOT NULL CHECK(locale IN ('en','hi')),
 status text NOT NULL DEFAULT 'pending', s3_key text UNIQUE,
 content_sha256 text, failure_code text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_reports_owner ON reports(owner_id);
