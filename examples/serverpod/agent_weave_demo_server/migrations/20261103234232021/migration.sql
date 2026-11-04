BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "agent_weave_event" (
    "id" bigserial PRIMARY KEY,
    "ownerId" text NOT NULL,
    "threadId" text NOT NULL,
    "runId" text NOT NULL,
    "sequence" bigint NOT NULL,
    "eventJson" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "agent_weave_event_owner_thread_run_sequence" ON "agent_weave_event" USING btree ("ownerId", "threadId", "runId", "sequence");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "agent_weave_run" (
    "id" bigserial PRIMARY KEY,
    "ownerId" text NOT NULL,
    "threadId" text NOT NULL,
    "runId" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "agent_weave_run_owner_run" ON "agent_weave_run" USING btree ("ownerId", "runId");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "agent_weave_thread" (
    "id" bigserial PRIMARY KEY,
    "ownerId" text NOT NULL,
    "threadId" text NOT NULL,
    "activeRun" text,
    "stateJson" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "agent_weave_thread_owner_thread" ON "agent_weave_thread" USING btree ("ownerId", "threadId");


--
-- MIGRATION VERSION FOR agent_weave_demo
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('agent_weave_demo', '20261103234232021', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261103234232021', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260824182259319', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260824182259319', "timestamp" = now();

--
-- MIGRATION VERSION FOR agent_weave_serverpod_storage
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('agent_weave_serverpod_storage', '20261103234218357', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261103234218357', "timestamp" = now();


COMMIT;
