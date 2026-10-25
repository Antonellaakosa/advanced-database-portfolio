// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : lib.js    (loaded by every other script with load("lib.js"))
// Purpose : Small helpers: banners, PASS/FAIL lines (also saved in the
//           p4_results collection), error catching, timing, and a function
//           that reads the stage names out of an explain plan.
// =====================================================================
var P4 = { scenario: "p4" };

function begin(name) {
  P4.scenario = name;
  db.p4_results.deleteMany({ scenario: name });
}

function banner(text) {
  print("");
  print("=".repeat(72));
  print(" " + text);
  print("=".repeat(72));
}

function check(code, label, ok) {
  ok = (ok === true);
  print("   " + (ok ? "PASS" : "FAIL") + "  " + code + "  " + label);
  db.p4_results.insertOne({ scenario: P4.scenario, code: code, label: label, ok: ok, at: new Date() });
}

// Run something that may fail. Returns { ok, value } or { ok:false, error }.
function attempt(fn) {
  try { return { ok: true, value: fn() }; } catch (e) { return { ok: false, error: e }; }
}

function summary() {
  const pass = db.p4_results.countDocuments({ scenario: P4.scenario, ok: true });
  const fail = db.p4_results.countDocuments({ scenario: P4.scenario, ok: false });
  print("");
  print("=== " + P4.scenario + ": " + pass + " PASS, " + fail + " FAIL ===");
}

// Was this error a "document failed validation" refusal?
function isValidationError(e) {
  return !!e && (e.code === 121 || /validation/i.test(String(e.message)));
}

// Every "stage" name found anywhere inside a query plan (COLLSCAN, IXSCAN, FETCH, ...).
function stagesOf(plan) {
  const found = [];
  (function walk(o) {
    if (o && typeof o === "object") {
      if (typeof o.stage === "string") found.push(o.stage);
      Object.keys(o).forEach(function (k) { walk(o[k]); });
    }
  })(plan);
  return found;
}

// Explain a find() and return { stages, examined, returned }.
function explainFind(coll, filter, sort, limit) {
  let cur = db.getCollection(coll).find(filter);
  if (sort) cur = cur.sort(sort);
  if (limit) cur = cur.limit(limit);
  const e = cur.explain("executionStats");
  const winning = e.queryPlanner ? e.queryPlanner.winningPlan : null;
  return {
    stages: stagesOf(winning),
    examined: e.executionStats ? e.executionStats.totalDocsExamined : null,
    returned: e.executionStats ? e.executionStats.nReturned : null
  };
}

// Average milliseconds of fn() over reps runs (after one warm-up run).
function avgMs(fn, reps) {
  fn();
  const t0 = Date.now();
  for (let i = 0; i < reps; i++) fn();
  return (Date.now() - t0) / reps;
}

function fmt(n) { return Number(n).toFixed(2); }
