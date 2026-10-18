-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 2
-- File    : 01_generate_data.sql
-- Purpose : Adds a realistic LARGE data set on top of the Portfolio 1 sample
--           data, so that query performance can be measured meaningfully.
--             ~50,000 members   ~100,000 titles   ~150,000 copies
--             ~1,000,000 loans  ~130,000 fines    ~90,000 payments
-- Run     : psql -U library_admin -d upln_perf -v ON_ERROR_STOP=1 -f 01_generate_data.sql
--           Optional smaller run for a quick test:  -v scale=0.1
-- Requires: a database that already contains 01_schema.sql and
--           02_sample_data.sql from Portfolio 1 (see README, section 3).
-- Note    : All data is SYNTHETIC. The random generator is seeded, so the
--           same data is produced each time (names and dates are repeatable).
-- Note    : This script deliberately creates NO extra indexes. Portfolio 2
--           first measures the slow "before" state, then adds indexes.
-- =====================================================================

\if :{?scale}
\else
  \set scale 1
\endif

\timing on
SET client_min_messages = warning;
SELECT setseed(0.42);

-- Sizes for this run (scale = 1 gives the sizes above)
CREATE TEMP TABLE _cfg AS
SELECT (50000   * :scale)::int - 8   AS n_members,     -- bulk members  (ids 9 ...)
       (100000  * :scale)::int - 10  AS n_titles,      -- bulk titles   (ids 11 ...)
       (20000   * :scale)::int       AS n_authors,     -- bulk authors  (ids 11 ...)
       (150000  * :scale)::int       AS n_copies,      -- bulk copies   (ids 20 ...)
       (1000000 * :scale)::int       AS n_loans,       -- bulk loans    (ids 11 ...)
       2000                          AS n_active;      -- loans still out (not yet returned)

-- Word lists used to build realistic-looking names and titles
CREATE TEMP TABLE _lists AS
SELECT
  ARRAY['Okafor','Bakare','Bello','Nwosu','Eze','Danjuma','Adeyemi','Obi','Ibekwe','Yusuf',
        'Adebayo','Ojo','Amadi','Garba','Lawal','Ugwu','Okonkwo','Abubakar','Balogun','Chukwu',
        'Musa','Ogunleye','Nnamdi','Ibrahim','Adewale','Okoro','Umar','Eke','Afolabi','Sani',
        'Onyeka','Salisu','Odunsi','Nwachukwu','Aliyu','Fashola','Ezekiel','Mohammed','Oyelaran','Igwe',
        'Taiwo','Kalu','Hassan','Olawale','Agu','Danladi','Ogbu','Soyinka','Achebe','Ekwueme',
        'Oladipo','Nwankwo','Usman','Idowu','Anyanwu','Bamidele','Lawan','Okeke','Shehu','Opara'] AS surnames,
  ARRAY['Adaeze','Tunde','Aisha','Emeka','Ngozi','Ibrahim','Funke','Chidi','Grace','Samuel',
        'Bola','Kemi','Dumebi','Hauwa','Musa','Ifeanyi','Zainab','Obinna','Folake','Yakubu',
        'Chioma','Segun','Fatima','Kelechi','Amina','Tobi','Nneka','Abdul','Yetunde','Uche',
        'Halima','Ikenna','Bukola','Sadiq','Amaka','Femi','Rukayat','Chinedu','Ladi','Kayode',
        'Blessing','Wale','Maryam','Ebuka','Titi','Garba','Ngozika','Dayo','Hadiza','Ose',
        'Nkechi','Lanre','Salamatu','Ifeoma','Biodun','Aminu','Chiamaka','Gbenga','Habiba','Ugo'] AS firstnames,
  ARRAY['Silent','Golden','Hidden','Ancient','Modern','Practical','Complete','Essential','Brave','Quiet',
        'Distant','Bright','Forgotten','Eternal','Young','Little','Great','Secret','Wandering','Rising',
        'Southern','Northern','Western','Eastern','Urban','Rural','Digital','Classic','Simple','Advanced',
        'Lost','Final','First','Second','Last','Open','Shared','Wild','Gentle','Bold'] AS adjectives,
  ARRAY['River','Database','Garden','City','Market','Journey','Kingdom','Harvest','Library','Network',
        'Mountain','Voyage','Story','Dream','Letter','House','Village','Road','Song','Festival',
        'Bridge','Island','Forest','Memory','Mirror','Season','Tower','Window','Shadow','Harbour',
        'Language','Machine','Algorithm','Theory','History','Mystery','Empire','Fortune','Valley','Kitchen',
        'Ocean','Desert','Lantern','Compass','Orchard','Railway','Council','Rhythm','Voice','Frontier',
        'Cartographer','Merchant','Teacher','Doctor','Farmer','Weaver','Fisherman','Drummer','Poet','Engineer',
        'Heritage','Legacy','Promise','Silence','Thunder','Rainfall','Sunrise','Moonlight','Horizon','Echo',
        'Notebook','Archive','Gallery','Theatre','Workshop','Laboratory','Station','Square','Gate','Crossing'] AS nouns,
  ARRAY['Handbook','Guide','Chronicles','Stories','Primer','Companion','Anthology','Collection','Notes','Essays'] AS suffixes;

-- ---------------------------------------------------------------------
-- 1. Members
-- ---------------------------------------------------------------------
INSERT INTO member (first_name, last_name, email, phone, address, type_id, home_branch_id, joined_date, status)
SELECT L.firstnames[1 + floor(random() * 60)::int],
       L.surnames  [1 + floor(random() * 60)::int],
       'member' || g || '@example.com',
       '+23480' || lpad((10000000 + g)::text, 8, '0'),
       g || ' Sample Street',
       1 + floor(random() * 3)::int,
       1 + floor(random() * 5)::int,
       date '2019-01-01' + floor(random() * 2800)::int,
       (ARRAY['active','active','active','active','active','active','active','active','suspended','expired'])
           [1 + floor(random() * 10)::int]
FROM generate_series(1, (SELECT n_members FROM _cfg)) AS g
CROSS JOIN _lists L;

-- ---------------------------------------------------------------------
-- 2. Titles, authors and the title/author links
-- ---------------------------------------------------------------------
INSERT INTO title (isbn, title_name, publisher_id, category_id, publication_year, media_type, language)
SELECT '9780' || lpad(g::text, 9, '0'),
       'The ' || L.adjectives[1 + floor(random() * 40)::int] || ' ' ||
                 L.nouns[1 + floor(random() * 80)::int] || ' ' ||
                 L.suffixes[1 + floor(random() * 10)::int] || ' #' || g,
       1 + floor(random() * 4)::int,
       1 + floor(random() * 5)::int,
       1950 + floor(random() * 77)::int,
       (ARRAY['book','book','book','book','book','book','book','book','dvd','audiobook'])
           [1 + floor(random() * 10)::int],
       'English'
FROM generate_series(1, (SELECT n_titles FROM _cfg)) AS g
CROSS JOIN _lists L;

INSERT INTO author (full_name)
SELECT 'Author ' || g FROM generate_series(1, (SELECT n_authors FROM _cfg)) AS g;

-- One main author per bulk title; about one title in ten also has a second author.
INSERT INTO title_author (title_id, author_id, author_order)
SELECT t.title_id, 10 + 1 + floor(random() * (SELECT n_authors FROM _cfg))::int, 1
FROM title t WHERE t.title_id > 10;

INSERT INTO title_author (title_id, author_id, author_order)
SELECT t.title_id, 10 + 1 + floor(random() * (SELECT n_authors FROM _cfg))::int, 2
FROM title t WHERE t.title_id > 10 AND random() < 0.10
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 3. Physical copies
-- ---------------------------------------------------------------------
INSERT INTO copy (title_id, branch_id, barcode, status, copy_condition, acquired_date, acquisition_cost)
SELECT 1 + floor(random() * (SELECT n_titles + 10 FROM _cfg))::int,
       1 + floor(random() * 5)::int,
       'UPLN-B' || lpad(g::text, 8, '0'),
       'available',
       (ARRAY['new','good','good','good','fair','poor'])[1 + floor(random() * 6)::int],
       date '2015-01-01' + floor(random() * 4000)::int,
       round((1500 + random() * 18000)::numeric, 2)
FROM generate_series(1, (SELECT n_copies FROM _cfg)) AS g;

-- ---------------------------------------------------------------------
-- 4. Loans (the big table), in chronological order
--    * The last 2,000 loans are still out (returned_at IS NULL), each on its
--      own copy and belonging to members 1..2000 (this respects rule R2).
--    * Earlier loans are returned; about 1 in 8 comes back late.
--    * Some members borrow far more than others (skewed, like real life).
-- ---------------------------------------------------------------------
INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, return_branch_id,
                  loaned_at, due_at, returned_at, renewals)
SELECT x.copy_id, x.member_id, x.staff_id, x.checkout_branch, 
       CASE WHEN x.active THEN NULL ELSE 1 + floor(random() * 5)::int END,
       x.loaned_at,
       x.loaned_at + x.lend_days * interval '1 day',
       CASE WHEN x.active THEN NULL
            ELSE x.loaned_at + (random() * 1.15 * x.lend_days) * interval '1 day' END,
       (ARRAY[0,0,0,0,0,0,1,1,2])[1 + floor(random() * 9)::int]
FROM (
    SELECT g,
           (g > c.n_loans - c.n_active)                                   AS active,
           CASE WHEN g > c.n_loans - c.n_active
                THEN 19 + (g - (c.n_loans - c.n_active))                  -- own copy for each active loan
                ELSE 19 + 1 + floor(random() * c.n_copies)::int END       AS copy_id,
           CASE WHEN g > c.n_loans - c.n_active
                THEN (g - (c.n_loans - c.n_active))                       -- members 1..2000
                ELSE 1 + floor((c.n_members + 8) * power(random(), 1.5))::int END AS member_id,
           1 + floor(random() * 8)::int                                   AS staff_id,
           1 + floor(random() * 5)::int                                   AS checkout_branch,
           timestamptz '2019-01-01 08:00+01' + (g * 235) * interval '1 second' AS loaned_at,
           (ARRAY[14, 21, 28])[1 + floor(random() * 3)::int]              AS lend_days
    FROM _cfg c, generate_series(1, (SELECT n_loans FROM _cfg)) AS g
) x
ORDER BY x.g;

-- Copies that are out on loan are marked as such (keeps the two tables consistent)
UPDATE copy SET status = 'on_loan'
WHERE copy_id IN (SELECT copy_id FROM loan WHERE returned_at IS NULL AND loan_id > 10);

-- ---------------------------------------------------------------------
-- 5. Fines for late returns, and payments for most of them
-- ---------------------------------------------------------------------
INSERT INTO fine (loan_id, amount, reason, assessed_at, waived)
SELECT l.loan_id,
       round(GREATEST(1, ceil(extract(epoch FROM (l.returned_at - l.due_at)) / 86400)) * mt.fine_per_day, 2),
       'overdue', l.returned_at, FALSE
FROM loan l
JOIN member m           ON m.member_id = l.member_id
JOIN membership_type mt ON mt.type_id  = m.type_id
WHERE l.loan_id > 10 AND l.returned_at > l.due_at;

INSERT INTO payment (fine_id, received_by_staff_id, amount, paid_at, method)
SELECT f.fine_id, 1 + floor(random() * 8)::int, f.amount, f.assessed_at + interval '2 hours',
       (ARRAY['cash','card','bank_transfer','mobile_money'])[1 + floor(random() * 4)::int]
FROM fine f
WHERE f.fine_id > 3 AND random() < 0.70;

-- ---------------------------------------------------------------------
-- 6. Refresh the optimiser's statistics and the visibility map.
--    Fresh statistics let the planner estimate costs sensibly.
-- ---------------------------------------------------------------------
VACUUM (ANALYZE);

\timing off
\echo
\echo '=== Row counts ==='
SELECT 'branch' AS table_name, count(*) AS rows FROM branch
UNION ALL SELECT 'member',        count(*) FROM member
UNION ALL SELECT 'title',         count(*) FROM title
UNION ALL SELECT 'author',        count(*) FROM author
UNION ALL SELECT 'title_author',  count(*) FROM title_author
UNION ALL SELECT 'copy',          count(*) FROM copy
UNION ALL SELECT 'loan',          count(*) FROM loan
UNION ALL SELECT 'fine',          count(*) FROM fine
UNION ALL SELECT 'payment',       count(*) FROM payment
ORDER BY rows DESC;

\echo
\echo '=== Table sizes ==='
SELECT relname AS table_name, pg_size_pretty(pg_total_relation_size(oid)) AS total_size_with_indexes
FROM pg_class
WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace
ORDER BY pg_total_relation_size(oid) DESC LIMIT 6;
