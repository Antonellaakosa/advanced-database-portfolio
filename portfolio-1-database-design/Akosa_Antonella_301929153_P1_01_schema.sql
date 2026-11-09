-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1
-- File    : Akosa_Antonella_301929153_P1_01_schema.sql
-- Purpose : Creates the relational schema (15 tables, 1 view) in PostgreSQL 16.
-- Run     : psql -U library_admin -d upln -f Akosa_Antonella_301929153_P1_01_schema.sql
-- Note    : Safe to re-run. It drops existing UPLN tables first.
-- Note    : Secondary (non-key) indexes are deliberately NOT created here.
--           Portfolio 2 adds them so the before/after comparison is fair.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Clean slate (children first, so foreign keys do not block the drops)
-- ---------------------------------------------------------------------
SET client_min_messages = warning;   -- hide "does not exist, skipping" notices
DROP VIEW IF EXISTS v_fine_balance;
DROP TABLE IF EXISTS payment          CASCADE;
DROP TABLE IF EXISTS fine             CASCADE;
DROP TABLE IF EXISTS copy_transfer    CASCADE;
DROP TABLE IF EXISTS reservation      CASCADE;
DROP TABLE IF EXISTS loan             CASCADE;
DROP TABLE IF EXISTS copy             CASCADE;
DROP TABLE IF EXISTS title_author     CASCADE;
DROP TABLE IF EXISTS title            CASCADE;
DROP TABLE IF EXISTS category         CASCADE;
DROP TABLE IF EXISTS author           CASCADE;
DROP TABLE IF EXISTS publisher        CASCADE;
DROP TABLE IF EXISTS staff            CASCADE;
DROP TABLE IF EXISTS member           CASCADE;
DROP TABLE IF EXISTS membership_type  CASCADE;
DROP TABLE IF EXISTS branch           CASCADE;

-- ---------------------------------------------------------------------
-- 1. Reference / lookup tables
-- ---------------------------------------------------------------------

-- A site in the network: the Abuja headquarters or one of four city branches.
CREATE TABLE branch (
    branch_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_name      VARCHAR(100) NOT NULL UNIQUE,
    city             VARCHAR(60)  NOT NULL,
    state            VARCHAR(60)  NOT NULL,
    address          VARCHAR(200) NOT NULL,
    phone            VARCHAR(20),
    is_headquarters  BOOLEAN      NOT NULL DEFAULT FALSE,
    opened_date      DATE         NOT NULL DEFAULT CURRENT_DATE
);

-- Business rule: the network has exactly ONE headquarters.
-- A partial unique index allows many FALSE rows but only one TRUE row.
CREATE UNIQUE INDEX uq_one_headquarters
    ON branch (is_headquarters)
    WHERE is_headquarters;

-- Loan rules live here once, instead of being repeated on every member row.
CREATE TABLE membership_type (
    type_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type_name     VARCHAR(30)   NOT NULL UNIQUE,
    max_loans     INTEGER       NOT NULL CHECK (max_loans > 0),
    loan_days     INTEGER       NOT NULL CHECK (loan_days > 0),
    fine_per_day  NUMERIC(8,2)  NOT NULL CHECK (fine_per_day >= 0),   -- naira
    annual_fee    NUMERIC(10,2) NOT NULL CHECK (annual_fee >= 0)      -- naira
);

CREATE TABLE publisher (
    publisher_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    publisher_name  VARCHAR(120) NOT NULL UNIQUE,
    country         VARCHAR(60)
);

CREATE TABLE author (
    author_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name  VARCHAR(120) NOT NULL
);

CREATE TABLE category (
    category_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name  VARCHAR(60) NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- 2. People
-- ---------------------------------------------------------------------

CREATE TABLE member (
    member_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name      VARCHAR(60)  NOT NULL,
    last_name       VARCHAR(60)  NOT NULL,
    email           VARCHAR(120) NOT NULL UNIQUE
                    CHECK (email LIKE '_%@_%.__%'),
    phone           VARCHAR(20),
    address         VARCHAR(200),
    type_id         INTEGER      NOT NULL REFERENCES membership_type (type_id),
    home_branch_id  INTEGER      NOT NULL REFERENCES branch (branch_id),
    joined_date     DATE         NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(10)  NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'suspended', 'expired'))
);

CREATE TABLE staff (
    staff_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id   INTEGER      NOT NULL REFERENCES branch (branch_id),
    first_name  VARCHAR(60)  NOT NULL,
    last_name   VARCHAR(60)  NOT NULL,
    email       VARCHAR(120) NOT NULL UNIQUE
                CHECK (email LIKE '_%@_%.__%'),
    role        VARCHAR(20)  NOT NULL
                CHECK (role IN ('librarian', 'branch_manager', 'administrator')),
    hired_date  DATE         NOT NULL DEFAULT CURRENT_DATE
);

-- ---------------------------------------------------------------------
-- 3. Catalogue: a TITLE is the work; a COPY is one physical item.
-- ---------------------------------------------------------------------

CREATE TABLE title (
    title_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    isbn              CHAR(13) UNIQUE                        -- NULL allowed (e.g. some DVDs)
                      CHECK (isbn ~ '^97[89][0-9]{10}$'),
    title_name        VARCHAR(200) NOT NULL,
    publisher_id      INTEGER      REFERENCES publisher (publisher_id),
    category_id       INTEGER      NOT NULL REFERENCES category (category_id),
    publication_year  INTEGER      CHECK (publication_year BETWEEN 1450 AND 2100),
    media_type        VARCHAR(12)  NOT NULL DEFAULT 'book'
                      CHECK (media_type IN ('book', 'dvd', 'audiobook', 'magazine')),
    language          VARCHAR(30)  NOT NULL DEFAULT 'English'
);

-- Many-to-many: a title can have several authors; an author several titles.
CREATE TABLE title_author (
    title_id      INTEGER  NOT NULL REFERENCES title (title_id)   ON DELETE CASCADE,
    author_id     INTEGER  NOT NULL REFERENCES author (author_id),
    author_order  SMALLINT NOT NULL DEFAULT 1 CHECK (author_order >= 1),
    PRIMARY KEY (title_id, author_id)                       -- composite primary key
);

-- One physical item with its own barcode, currently held at one branch.
-- 'status' is a deliberate controlled denormalisation (see README, section 5).
CREATE TABLE copy (
    copy_id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title_id          INTEGER      NOT NULL REFERENCES title (title_id),
    branch_id         INTEGER      NOT NULL REFERENCES branch (branch_id),
    barcode           VARCHAR(20)  NOT NULL UNIQUE,
    status            VARCHAR(12)  NOT NULL DEFAULT 'available'
                      CHECK (status IN ('available', 'on_loan', 'in_transit',
                                        'reserved', 'lost', 'withdrawn')),
    copy_condition    VARCHAR(10)  NOT NULL DEFAULT 'good'
                      CHECK (copy_condition IN ('new', 'good', 'fair', 'poor')),
    acquired_date     DATE         NOT NULL DEFAULT CURRENT_DATE,
    acquisition_cost  NUMERIC(10,2) CHECK (acquisition_cost >= 0)
);

-- ---------------------------------------------------------------------
-- 4. Circulation
-- ---------------------------------------------------------------------

CREATE TABLE loan (
    loan_id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    copy_id             INTEGER     NOT NULL REFERENCES copy (copy_id),
    member_id           INTEGER     NOT NULL REFERENCES member (member_id),
    issued_by_staff_id  INTEGER     NOT NULL REFERENCES staff (staff_id),
    checkout_branch_id  INTEGER     NOT NULL REFERENCES branch (branch_id),
    return_branch_id    INTEGER     REFERENCES branch (branch_id),   -- NULL until returned
    loaned_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_at              TIMESTAMPTZ NOT NULL,
    returned_at         TIMESTAMPTZ,                                 -- NULL = still on loan
    renewals            SMALLINT    NOT NULL DEFAULT 0 CHECK (renewals BETWEEN 0 AND 2),
    CONSTRAINT ck_loan_due_after_loan   CHECK (due_at > loaned_at),
    CONSTRAINT ck_loan_return_after_loan CHECK (returned_at IS NULL OR returned_at >= loaned_at),
    CONSTRAINT ck_loan_return_pair      CHECK ((returned_at IS NULL) = (return_branch_id IS NULL))
);

-- Business rule: a physical copy can have at most ONE active (unreturned) loan.
-- The database itself refuses a double-borrow. Portfolio 3 builds on this.
CREATE UNIQUE INDEX uq_one_active_loan_per_copy
    ON loan (copy_id)
    WHERE returned_at IS NULL;

CREATE TABLE reservation (
    reservation_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title_id          INTEGER     NOT NULL REFERENCES title (title_id),
    member_id         INTEGER     NOT NULL REFERENCES member (member_id),
    pickup_branch_id  INTEGER     NOT NULL REFERENCES branch (branch_id),
    reserved_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at        TIMESTAMPTZ,
    status            VARCHAR(10) NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'ready', 'fulfilled', 'cancelled', 'expired')),
    CONSTRAINT ck_reservation_expiry CHECK (expires_at IS NULL OR expires_at > reserved_at)
);

-- Business rule: a member may have only one OPEN reservation per title.
CREATE UNIQUE INDEX uq_one_open_reservation
    ON reservation (member_id, title_id)
    WHERE status IN ('pending', 'ready');

-- A copy moving between cities (e.g. Lagos -> Kano).
CREATE TABLE copy_transfer (
    transfer_id            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    copy_id                INTEGER     NOT NULL REFERENCES copy (copy_id),
    from_branch_id         INTEGER     NOT NULL REFERENCES branch (branch_id),
    to_branch_id           INTEGER     NOT NULL REFERENCES branch (branch_id),
    requested_by_staff_id  INTEGER     NOT NULL REFERENCES staff (staff_id),
    requested_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    shipped_at             TIMESTAMPTZ,
    received_at            TIMESTAMPTZ,
    status                 VARCHAR(10) NOT NULL DEFAULT 'requested'
                           CHECK (status IN ('requested', 'in_transit', 'received', 'cancelled')),
    CONSTRAINT ck_transfer_different_branches CHECK (from_branch_id <> to_branch_id),
    CONSTRAINT ck_transfer_ship_after_request CHECK (shipped_at IS NULL OR shipped_at >= requested_at),
    CONSTRAINT ck_transfer_receive_after_ship CHECK (received_at IS NULL
                                                     OR (shipped_at IS NOT NULL AND received_at >= shipped_at))
);

-- ---------------------------------------------------------------------
-- 5. Money
-- ---------------------------------------------------------------------

-- A charge raised against a loan (overdue, lost or damaged item).
-- Whether it is paid is NOT stored here; it is derived from payments
-- (see v_fine_balance), which avoids an update anomaly.
CREATE TABLE fine (
    fine_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    loan_id      INTEGER       NOT NULL REFERENCES loan (loan_id),
    amount       NUMERIC(10,2) NOT NULL CHECK (amount > 0),            -- naira
    reason       VARCHAR(10)   NOT NULL CHECK (reason IN ('overdue', 'lost', 'damaged')),
    assessed_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    waived       BOOLEAN       NOT NULL DEFAULT FALSE,
    UNIQUE (loan_id, reason)          -- one fine of each kind per loan
);

CREATE TABLE payment (
    payment_id            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fine_id               INTEGER       NOT NULL REFERENCES fine (fine_id),
    received_by_staff_id  INTEGER       NOT NULL REFERENCES staff (staff_id),
    amount                NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    paid_at               TIMESTAMPTZ   NOT NULL DEFAULT now(),
    method                VARCHAR(15)   NOT NULL
                          CHECK (method IN ('cash', 'card', 'bank_transfer', 'mobile_money'))
);

-- Outstanding balance per fine, always computed from the payments.
CREATE VIEW v_fine_balance AS
SELECT f.fine_id,
       f.loan_id,
       f.amount                                   AS amount_assessed,
       COALESCE(SUM(p.amount), 0)                 AS amount_paid,
       CASE WHEN f.waived THEN 0
            ELSE f.amount - COALESCE(SUM(p.amount), 0) END AS amount_outstanding,
       f.waived
FROM fine f
LEFT JOIN payment p ON p.fine_id = f.fine_id
GROUP BY f.fine_id, f.loan_id, f.amount, f.waived;
