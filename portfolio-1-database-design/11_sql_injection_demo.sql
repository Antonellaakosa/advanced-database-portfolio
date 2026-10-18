-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1 (security)
-- File    : 11_sql_injection_demo.sql
-- Purpose : SQL INJECTION, the attack where user input is glued into a SQL
--           command and the input itself contains SQL.
--           Part A shows an UNSAFE search (text concatenation) being attacked.
--           Part B shows the SAFE search (bound parameter) resisting it.
--           Part C shows DEFENCE IN DEPTH: even when the unsafe code is
--           attacked, the member-app role is stopped by least privilege.
-- Run     : psql -U library_admin -d upln -f 11_sql_injection_demo.sql
-- Safe    : The vulnerable function exists only for this session (pg_temp)
--           and disappears when the script ends. Nothing is changed.
-- Requires: 01 .. 05
-- =====================================================================
SET client_min_messages = warning;
\pset format aligned
\pset border 2

-- UNSAFE: builds the command by gluing the user's text into it.
CREATE FUNCTION pg_temp.find_member_unsafe(search_text TEXT)
RETURNS TABLE (col1 TEXT, col2 TEXT) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT first_name::text, last_name::text FROM member WHERE last_name = ''' || search_text || '''';
END $$;

-- SAFE: the user's text is passed as a parameter ($1). It can only ever be data.
CREATE FUNCTION pg_temp.find_member_safe(search_text TEXT)
RETURNS TABLE (col1 TEXT, col2 TEXT) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT first_name::text, last_name::text FROM member WHERE last_name = $1' USING search_text;
END $$;

-- Test inputs: a normal search, a "match everything" attack, and a data-theft attack.
CREATE TEMP TABLE attack_input (n INT, label TEXT, input TEXT);
INSERT INTO attack_input VALUES
  (1, 'Normal search',        'Okafor'),
  (2, 'Attack: match all',    $$x' OR '1'='1$$),
  (3, 'Attack: steal staff',  $$x' UNION SELECT email, role FROM staff --$$);

\echo
\echo '=== A. UNSAFE search: what the database is really asked to run ==='
SELECT n, label, input AS "text typed into the search box",
       'SELECT ... FROM member WHERE last_name = ''' || input || '''' AS "command the database receives"
FROM attack_input ORDER BY n;

\echo
\echo '=== A. UNSAFE search: rows returned (running as the administrator) ==='
SELECT a.n, a.label,
       (SELECT count(*) FROM pg_temp.find_member_unsafe(a.input)) AS rows_returned
FROM attack_input a ORDER BY a.n;
\echo 'Attack 2 returns EVERY member. Attack 3 returns staff e-mail addresses from a different table.'
\echo '--- the stolen staff data (attack 3):'
SELECT col1 AS stolen_email, col2 AS stolen_role FROM pg_temp.find_member_unsafe($$x' UNION SELECT email, role FROM staff --$$) LIMIT 4;

\echo
\echo '=== B. SAFE search (bound parameter): the same three inputs ==='
SELECT a.n, a.label, (SELECT count(*) FROM pg_temp.find_member_safe(a.input)) AS rows_returned
FROM attack_input a ORDER BY a.n;
\echo 'Only the normal search finds a member. The attacks are treated as a (non-existent) surname, so they find nothing.'

\echo
\echo '=== C. Defence in depth: the SAME unsafe code, attacked while acting as the member app ==='
CREATE FUNCTION pg_temp.try_as(as_role TEXT, sql_text TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE c BIGINT;
BEGIN
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', as_role);
        PERFORM set_config('app.current_member_id', '1', true);   -- the member app is logged in as member 1
        EXECUTE sql_text;
        GET DIAGNOSTICS c = ROW_COUNT;
        RESET ROLE;
        RETURN 'allowed, ' || c || ' row(s) visible';
    EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        RETURN 'REFUSED by the database: ' || SQLERRM;
    END;
END $$;
SELECT a.label,
       pg_temp.try_as('upln_member_self',
          'SELECT first_name::text, last_name::text FROM member WHERE last_name = ''' || a.input || '''') AS "result as upln_member_self"
FROM attack_input a ORDER BY a.n;
\echo 'Member 1 is logged in. The "match all" attack returns only HER OWN row (row-level security), and the data-theft attack is'
\echo 'refused outright because the member-app role has no right to read the staff table. The code was unsafe, yet the damage was contained.'
\echo 'Lesson: use bound parameters (the cure) AND least privilege (the safety net).'
