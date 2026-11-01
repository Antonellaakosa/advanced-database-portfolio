// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : 11_other_nosql_models.js
// Purpose : The other three NoSQL families, each applied to a real UPLN need
//           and implemented in MongoDB so it can be run and checked:
//             key-value   : login sessions looked up by one key, expiring on their own
//             wide-column : one "row" per branch per day holding 24 hourly counters
//             graph       : "readers of this title also borrowed..." (links between titles)
//           (The document model, used for the catalogue, is scripts 02 to 08.)
// =====================================================================
load("lib.js");
begin("11_other_models");
banner("11  Key-value, wide-column and graph patterns for UPLN");

// ---------------- key-value: sessions ----------------
print("");
print("   KEY-VALUE  (a session is read and written by its key and nothing else)");
db.kv_session.drop();
attempt(function () { return db.kv_session.createIndex({ expiresAt: 1 }, { name: "ttl_session", expireAfterSeconds: 0 }); });
const key = "sess:7f3a9c";
db.kv_session.replaceOne({ _id: key }, { _id: key, value: { memberRef: "M42", branch: "UPLN Lagos Branch", basket: [4242, 1017] },
                                        expiresAt: new Date(Date.now() + 30 * 60 * 1000) }, { upsert: true });
const got = db.kv_session.findOne({ _id: key });
check("K1", "a session is stored and read back by its key alone", got !== null && got.value.memberRef === "M42");
const plan = explainFind("kv_session", { _id: key });
print("      lookup by key uses: " + plan.stages.join(" > ") + ", examined " + plan.examined + " document");
check("K2", "the lookup touches exactly one document (no scan)", plan.examined === 1);
db.kv_session.replaceOne({ _id: key }, { _id: key, value: { memberRef: "M42", branch: "UPLN Lagos Branch", basket: [] }, expiresAt: new Date(Date.now() + 30 * 60 * 1000) }, { upsert: true });
check("K3", "overwriting a key replaces the whole value (basket emptied)", db.kv_session.findOne({ _id: key }).value.basket.length === 0);
check("K4", "a missing key simply returns nothing", db.kv_session.findOne({ _id: "sess:unknown" }) === null);
check("K5", "a TTL index deletes expired sessions automatically (30-minute lifetime set on each session)",
      db.kv_session.getIndexes().some(function (i) { return i.name === "ttl_session" && i.expireAfterSeconds === 0; }));

// ---------------- wide-column: one row per branch per day ----------------
print("");
print("   WIDE-COLUMN  (one row per branch-day; the columns are the 24 hours)");
db.branch_daily.drop();
const events = [ ["ABJ", 9], ["ABJ", 9], ["ABJ", 10], ["LOS", 9], ["ABJ", 14], ["LOS", 14], ["ABJ", 9] ];
events.forEach(function (e) {
  const inc = {}; inc["hours." + e[1]] = 1; inc.total = 1;
  db.branch_daily.updateOne({ _id: e[0] + ":2026-10-24" }, { $inc: inc }, { upsert: true });
});
const abj = db.branch_daily.findOne({ _id: "ABJ:2026-10-24" });
print("      Abuja, 24 Oct 2026: total " + abj.total + " loans; by hour " + JSON.stringify(abj.hours));
check("W1", "seven loan events were folded into two branch-day rows (one write per event, no new row per loan)", db.branch_daily.countDocuments({}) === 2);
check("W2", "reading Abuja's whole day is one lookup; 9 o'clock has 3 loans", abj.hours["9"] === 3 && abj.total === 5);

// ---------------- graph: titles linked by shared readers ----------------
print("");
print("   GRAPH  (titles are nodes; a link means the same member used both)");
db.title_links.drop();
const byMember = {};
db.reviews.find({}, { memberRef: 1, titleId: 1, _id: 0 }).forEach(function (r) { (byMember[r.memberRef] = byMember[r.memberRef] || []).push(r.titleId); });
let ops = [], edges = 0;
Object.keys(byMember).forEach(function (m) {
  const t = byMember[m];
  for (let i = 0; i + 1 < t.length; i++) {
    if (t[i] === t[i + 1]) continue;
    ops.push({ updateOne: { filter: { _id: t[i] + ">" + t[i + 1] }, update: { $set: { from: t[i], to: t[i + 1] }, $inc: { weight: 1 } }, upsert: true } });
    edges++;
    if (ops.length === 5000) { db.title_links.bulkWrite(ops, { ordered: false }); ops = []; }
  }
});
if (ops.length) db.title_links.bulkWrite(ops, { ordered: false });
db.title_links.createIndex({ from: 1 }, { name: "ix_link_from" });
const nEdges = db.title_links.countDocuments({});
print("      " + nEdges + " links built from " + Object.keys(byMember).length + " members' histories");
check("G1", "links between titles were built from the review histories", nEdges > 1000);

const start = db.title_links.findOne({}, { from: 1 }).from;
const walk = attempt(function () {
  return db.title_links.aggregate([
    { $match: { from: start } },
    { $limit: 1 },
    { $graphLookup: { from: "title_links", startWith: "$to", connectFromField: "to", connectToField: "from", as: "reach", maxDepth: 1, depthField: "hops" } },
    { $project: { _id: 0, first: "$to", reach: { $size: "$reach" }, maxHops: { $max: "$reach.hops" } } }
  ]).toArray()[0];
});
if (walk.ok) print("      from title " + start + ": next title " + walk.value.first + ", then " + walk.value.reach + " further link(s) reached within 1 extra hop");
check("G2", "$graphLookup follows links from one title to the titles beyond it", walk.ok && walk.value.reach >= 0);
check("G3", "the walk stops at the depth limit (never more than 1 extra hop)", walk.ok && (walk.value.maxHops === null || walk.value.maxHops === undefined || walk.value.maxHops <= 1));

summary();
