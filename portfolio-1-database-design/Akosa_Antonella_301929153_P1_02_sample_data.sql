-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1
-- File    : 02_sample_data.sql
-- Purpose : Small, hand-written, internally consistent sample data.
-- Run     : psql -U library_admin -d upln -f 02_sample_data.sql
-- Requires: 01_schema.sql has just been run (IDs are assigned 1, 2, 3...
--           in the order of the INSERT statements below).
-- Note    : All people, emails and ISBNs are SYNTHETIC. Emails use the
--           reserved example.com domain. Author and title names are real
--           public works used only as realistic labels; the ISBNs are
--           placeholders, not the real ISBNs.
-- =====================================================================

-- 1. Branches (1 = headquarters) ---------------------------------------
INSERT INTO branch (branch_name, city, state, address, phone, is_headquarters, opened_date) VALUES
('UPLN Headquarters (Abuja)',   'Abuja',         'FCT',     '12 Unity Avenue, Garki',     '+2348000000001', TRUE,  '2010-01-15'),
('UPLN Lagos Branch',           'Lagos',         'Lagos',   '45 Marina Road, Lagos Island','+2348000000002', FALSE, '2012-03-10'),
('UPLN Port Harcourt Branch',   'Port Harcourt', 'Rivers',  '8 Aba Road, GRA',            '+2348000000003', FALSE, '2014-06-01'),
('UPLN Kano Branch',            'Kano',          'Kano',    '22 Ahmadu Bello Way',        '+2348000000004', FALSE, '2015-09-20'),
('UPLN Enugu Branch',           'Enugu',         'Enugu',   '5 Okpara Avenue',            '+2348000000005', FALSE, '2018-02-05');

-- 2. Membership types (naira) ------------------------------------------
INSERT INTO membership_type (type_name, max_loans, loan_days, fine_per_day, annual_fee) VALUES
('Standard',  5, 14,  50.00, 2000.00),
('Student',   8, 21,  25.00, 1000.00),
('Premium',  10, 28, 100.00, 5000.00);

-- 3. Lookup tables ------------------------------------------------------
INSERT INTO publisher (publisher_name, country) VALUES
('Penguin Books',       'United Kingdom'),
('Farafina Books',      'Nigeria'),
('Spectrum Books',      'Nigeria'),
('Pearson Education',   'United Kingdom');

INSERT INTO author (full_name) VALUES
('Chinua Achebe'),                -- 1
('Chimamanda Ngozi Adichie'),     -- 2
('Wole Soyinka'),                 -- 3
('Buchi Emecheta'),               -- 4
('Ben Okri'),                     -- 5
('Abraham Silberschatz'),         -- 6
('Henry F. Korth'),               -- 7
('S. Sudarshan'),                 -- 8
('Ramez Elmasri'),                -- 9
('Shamkant B. Navathe');          -- 10

INSERT INTO category (category_name) VALUES
('Fiction'),        -- 1
('Computing'),      -- 2
('History'),        -- 3
('Children'),       -- 4
('Documentary');    -- 5

-- 4. Staff --------------------------------------------------------------
INSERT INTO staff (branch_id, first_name, last_name, email, role, hired_date) VALUES
(1, 'Grace',    'Ibekwe',   'grace.ibekwe@example.com',    'administrator',  '2010-02-01'),  -- 1
(1, 'Samuel',   'Yusuf',    'samuel.yusuf@example.com',    'librarian',      '2016-05-12'),  -- 2
(2, 'Bola',     'Adebayo',  'bola.adebayo@example.com',    'branch_manager', '2012-04-01'),  -- 3
(2, 'Kemi',     'Ojo',      'kemi.ojo@example.com',        'librarian',      '2019-08-19'),  -- 4
(3, 'Dumebi',   'Amadi',    'dumebi.amadi@example.com',    'librarian',      '2017-01-23'),  -- 5
(4, 'Hauwa',    'Garba',    'hauwa.garba@example.com',     'branch_manager', '2015-10-01'),  -- 6
(4, 'Musa',     'Lawal',    'musa.lawal@example.com',      'librarian',      '2020-03-09'),  -- 7
(5, 'Ifeanyi',  'Ugwu',     'ifeanyi.ugwu@example.com',    'librarian',      '2018-03-01');  -- 8

-- 5. Members ------------------------------------------------------------
INSERT INTO member (first_name, last_name, email, phone, address, type_id, home_branch_id, joined_date, status) VALUES
('Adaeze',   'Okafor',   'adaeze.okafor@example.com',   '+2348010000001', '3 Allen Avenue, Ikeja',   1, 2, '2024-02-10', 'active'),     -- 1
('Tunde',    'Bakare',   'tunde.bakare@example.com',    '+2348010000002', 'UNILAG Hall 4, Akoka',    2, 2, '2025-09-15', 'active'),     -- 2
('Aisha',    'Bello',    'aisha.bello@example.com',     '+2348010000003', '14 Zaria Road, Kano',     3, 4, '2023-06-01', 'active'),     -- 3
('Emeka',    'Nwosu',    'emeka.nwosu@example.com',     '+2348010000004', '9 Trans-Amadi, PH',       1, 3, '2022-11-20', 'active'),     -- 4
('Ngozi',    'Eze',      'ngozi.eze@example.com',       '+2348010000005', 'UNN Hostel B, Nsukka',    2, 5, '2025-10-01', 'active'),     -- 5
('Ibrahim',  'Danjuma',  'ibrahim.danjuma@example.com', '+2348010000006', '6 Wuse II, Abuja',        1, 1, '2021-04-18', 'active'),     -- 6
('Funke',    'Adeyemi',  'funke.adeyemi@example.com',   '+2348010000007', '27 Opebi Road, Ikeja',    3, 2, '2020-01-30', 'active'),     -- 7
('Chidi',    'Obi',      'chidi.obi@example.com',       '+2348010000008', '2 Ogui Road, Enugu',      2, 5, '2024-09-09', 'suspended');  -- 8

-- 6. Catalogue: titles --------------------------------------------------
INSERT INTO title (isbn, title_name, publisher_id, category_id, publication_year, media_type, language) VALUES
('9789990000011', 'Things Fall Apart',                      1, 1, 1958, 'book',      'English'),  -- 1
('9789990000028', 'Half of a Yellow Sun',                   2, 1, 2006, 'book',      'English'),  -- 2
('9789990000035', 'Death and the King''s Horseman',         3, 1, 1975, 'book',      'English'),  -- 3
('9789990000042', 'The Joys of Motherhood',                 1, 1, 1979, 'book',      'English'),  -- 4
('9789990000059', 'The Famished Road',                      1, 1, 1991, 'book',      'English'),  -- 5
('9789990000066', 'Database System Concepts',              4, 2, 2019, 'book',      'English'),  -- 6
('9789990000073', 'Fundamentals of Database Systems',      4, 2, 2015, 'book',      'English'),  -- 7
('9789990000080', 'Things Fall Apart (Audiobook)',         1, 1, 2010, 'audiobook', 'English'),  -- 8
(NULL,            'Nigeria: A People United (Documentary)', NULL, 5, 2012, 'dvd',    'English'),  -- 9
(NULL,            'Africa Today (Monthly Magazine)',       NULL, 3, 2026, 'magazine','English');  -- 10

-- Many-to-many links between titles and authors
INSERT INTO title_author (title_id, author_id, author_order) VALUES
(1, 1, 1), (2, 2, 1), (3, 3, 1), (4, 4, 1), (5, 5, 1),
(6, 6, 1), (6, 7, 2), (6, 8, 3),          -- three authors on one title
(7, 9, 1), (7, 10, 2),
(8, 1, 1);

-- 7. Physical copies (copy_id 1..19). branch_id = branch where it is held,
--    or the origin branch while it is in transit.
INSERT INTO copy (title_id, branch_id, barcode, status, copy_condition, acquired_date, acquisition_cost) VALUES
(1, 4, 'UPLN-000001', 'available', 'good', '2019-01-10', 3500.00),   -- 1   returned in Kano (loan 6)
(1, 2, 'UPLN-000002', 'on_loan',   'good', '2019-01-10', 3500.00),   -- 2   loan 1
(1, 3, 'UPLN-000003', 'available', 'fair', '2018-05-02', 3200.00),   -- 3
(2, 1, 'UPLN-000004', 'on_loan',   'new',  '2024-03-15', 5200.00),   -- 4   loan 2
(2, 2, 'UPLN-000005', 'available', 'good', '2022-07-21', 5000.00),   -- 5
(2, 4, 'UPLN-000006', 'in_transit','good', '2022-07-21', 5000.00),   -- 6   transfer 1
(3, 1, 'UPLN-000007', 'available', 'good', '2017-09-09', 2800.00),   -- 7
(3, 5, 'UPLN-000008', 'available', 'fair', '2018-03-11', 2800.00),   -- 8
(4, 2, 'UPLN-000009', 'on_loan',   'good', '2020-02-02', 3000.00),   -- 9   loan 3 (overdue)
(5, 1, 'UPLN-000010', 'available', 'good', '2021-11-30', 3900.00),   -- 10  arrived by transfer 2
(6, 1, 'UPLN-000011', 'on_loan',   'new',  '2025-01-20', 18500.00),  -- 11  loan 4
(6, 2, 'UPLN-000012', 'available', 'good', '2025-01-20', 18500.00),  -- 12
(6, 4, 'UPLN-000013', 'available', 'good', '2025-01-20', 18500.00),  -- 13
(7, 1, 'UPLN-000014', 'available', 'good', '2023-04-14', 16000.00),  -- 14
(7, 5, 'UPLN-000015', 'reserved',  'good', '2023-04-14', 16000.00),  -- 15  held for reservation 1
(8, 3, 'UPLN-000016', 'available', 'new',  '2024-08-08', 4500.00),   -- 16
(9, 2, 'UPLN-000017', 'on_loan',   'good', '2016-12-01', 2500.00),   -- 17  loan 5
(10,4, 'UPLN-000018', 'available', 'good', '2026-10-01', 1500.00),   -- 18
(1, 5, 'UPLN-000019', 'withdrawn', 'poor', '2015-06-30', 3000.00);   -- 19  damaged, removed

-- 8. Loans (loan_id 1..10). Loans 1-5 are ACTIVE (returned_at NULL).
INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, return_branch_id,
                  loaned_at, due_at, returned_at, renewals) VALUES
( 2, 2, 4, 2, NULL, '2026-10-05 10:15+01', '2026-10-26 10:15+01', NULL, 0),                       -- 1 student, 21 days
( 4, 1, 2, 1, NULL, '2026-10-10 09:40+01', '2026-10-24 09:40+01', NULL, 0),                       -- 2 standard, 14 days
( 9, 7, 4, 2, NULL, '2026-09-01 11:00+01', '2026-09-29 11:00+01', NULL, 1),                       -- 3 premium, OVERDUE
(11, 6, 2, 1, NULL, '2026-10-12 14:20+01', '2026-10-26 14:20+01', NULL, 0),                       -- 4 standard
(17, 1, 3, 2, NULL, '2026-10-14 16:05+01', '2026-10-28 16:05+01', NULL, 0),                       -- 5 standard
( 1, 3, 2, 1, 4,    '2026-08-10 12:30+01', '2026-09-07 12:30+01', '2026-09-05 15:10+01', 0),      -- 6 borrowed in Abuja, returned in Kano
(19, 5, 8, 5, 5,    '2026-08-20 10:00+01', '2026-09-10 10:00+01', '2026-09-09 11:45+01', 0),      -- 7 returned damaged
( 3, 4, 5, 3, 3,    '2026-08-01 13:10+01', '2026-08-15 13:10+01', '2026-08-30 10:20+01', 0),      -- 8 returned 15 days late
(12, 2, 4, 2, 2,    '2026-09-10 09:00+01', '2026-10-01 09:00+01', '2026-09-28 17:30+01', 0),      -- 9 on time
( 5, 7, 4, 2, 2,    '2026-09-15 15:45+01', '2026-10-13 15:45+01', '2026-10-17 12:00+01', 0);      -- 10 returned 4 days late

-- 9. Reservations -------------------------------------------------------
INSERT INTO reservation (title_id, member_id, pickup_branch_id, reserved_at, expires_at, status) VALUES
(7, 5, 5, '2026-10-12 08:30+01', '2026-10-20 08:30+01', 'ready'),       -- 1 copy 15 is held for her
(2, 6, 1, '2026-10-16 10:00+01', NULL,                  'pending'),     -- 2 waiting for a copy
(6, 2, 2, '2026-09-30 09:15+01', '2026-10-07 09:15+01', 'cancelled');   -- 3

-- 10. Copy transfers between cities ---------------------------------------
INSERT INTO copy_transfer (copy_id, from_branch_id, to_branch_id, requested_by_staff_id,
                           requested_at, shipped_at, received_at, status) VALUES
( 6, 4, 5, 6, '2026-10-14 09:00+01', '2026-10-15 10:00+01', NULL,                  'in_transit'),   -- 1
(10, 3, 1, 5, '2026-09-20 11:00+01', '2026-09-21 09:30+01', '2026-09-25 14:00+01', 'received');     -- 2

-- 11. Fines and payments (amounts in naira) -----------------------------
-- overdue fine = days late x member's fine_per_day
INSERT INTO fine (loan_id, amount, reason, assessed_at, waived) VALUES
( 8,  750.00, 'overdue', '2026-08-30 10:25+01', FALSE),   -- 15 days x 50   -> fully paid
( 7, 1500.00, 'damaged', '2026-09-09 11:50+01', FALSE),   -- partly paid
(10,  400.00, 'overdue', '2026-10-17 12:05+01', FALSE);   -- 4 days x 100   -> unpaid

INSERT INTO payment (fine_id, received_by_staff_id, amount, paid_at, method) VALUES
(1, 5,  750.00, '2026-08-30 10:30+01', 'cash'),
(2, 8,  500.00, '2026-09-10 09:00+01', 'mobile_money');
