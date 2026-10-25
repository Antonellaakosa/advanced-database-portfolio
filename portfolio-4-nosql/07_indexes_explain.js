// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : 07_indexes_explain.js
// Purpose : Shows what an index does in MongoDB: the same query is explained
//           and timed BEFORE and AFTER, using 100,010 titles. Also covers
//           compound, multikey, unique-sparse, partial, text and TTL indexes.
// =====================================================================
load("lib.js");
begin("07_indexes");
banner("07  Indexes and explain plans");

// Start from a clean slate: only the automatic _id index survives.
db.titles.dropIndexes();
db.search_log.drop();

const queries = [
  { id: "X1", label: "equality on isbn",
    run: function () { return db.titles.find({ isbn: "9780000050500" }).toArray(); },
    plan: function () { return explainFind("titles", { isbn: "9780000050500" }); }, index: { isbn: 1 }, opts: { name: "ix_isbn" } },
  { id: "X2", label: "category + newest first (compound, sort)",
    run: function () { return db.titles.find({ "category.name": "Computing", publicationYear: { $gte: 2020 } }).sort({ publicationYear: -1 }).limit(20).toArray(); },
    plan: function () { return explainFind("titles", { "category.name": "Computing", publicationYear: { $gte: 2020 } }, { publicationYear: -1 }, 20); },
    index: { "category.name": 1, publicationYear: -1 }, opts: { name: "ix_category_year" } },
  { id: "X3", label: "author name inside an array (multikey)",
    run: function () { return db.titles.find({ "authors.name": "Amara Okafor" }).limit(50).toArray(); },
    plan: function () { return explainFind("titles", { "authors.name": "Amara Okafor" }, null, 50); },
    index: { "authors.name": 1 }, opts: { name: "ix_author_name" } }
];

const timing = [];
queries.forEach(function (q) {
  const b = q.plan(), tb = avgMs(q.run, 5);
  db.titles.createIndex(q.index, q.opts);
  const a = q.plan(), ta = avgMs(q.run, 5);
  print("");
  print("   " + q.id + "  " + q.label);
  print("        before: " + b.stages.join(" > ") + "   examined " + b.examined + " docs, returned " + b.returned + ", " + fmt(tb) + " ms");
  print("        after : " + a.stages.join(" > ") + "   examined " + a.examined + " docs, returned " + a.returned + ", " + fmt(ta) + " ms");
  check(q.id + "a", q.label + ": before the index MongoDB scans the whole collection (COLLSCAN)", b.stages.indexOf("COLLSCAN") >= 0);
  check(q.id + "b", q.label + ": after the index it uses an index scan (IXSCAN)", a.stages.indexOf("IXSCAN") >= 0);
  check(q.id + "c", q.label + ": examined documents dropped (" + b.examined + " -> " + a.examined + ")", a.examined < b.examined);
  timing.push([q.id, tb, ta, b.examined, a.examined]);
});

print("");
print("   Summary (average of 5 runs):");
print("   query   before_ms   after_ms   docs_before   docs_after");
timing.forEach(function (t) { print("   " + t[0] + "      " + fmt(t[1]).padStart(8) + "   " + fmt(t[2]).padStart(8) + "   " + String(t[3]).padStart(11) + "   " + String(t[4]).padStart(10)); });

// Unique + sparse: a rule, not just speed (magazines may have no ISBN).
print("");
const u = attempt(function () { return db.titles.createIndex({ isbn: 1 }, { name: "ix_isbn_unique", unique: true, sparse: true }); });
// the plain isbn index has the same key; drop it so the unique one can replace it
if (!u.ok) { db.titles.dropIndex("ix_isbn"); db.titles.createIndex({ isbn: 1 }, { name: "ix_isbn_unique", unique: true, sparse: true }); }
const dup = attempt(function () { return db.titles.insertOne({ _id: 999200, title: "Dup", mediaType: "book", isbn: "9789990000011", category: { name: "Fiction" }, authors: [{ name: "X" }], availability: { total: 1, available: 1 } }); });
if (dup.ok) db.titles.deleteOne({ _id: 999200 });
check("X4", "unique sparse index on isbn refuses a duplicate ISBN", !dup.ok);

// Partial index: only index what is worth indexing.
const p = attempt(function () { return db.titles.createIndex({ "category.name": 1, title: 1 }, { name: "ix_available_only", partialFilterExpression: { "availability.available": { $gt: 0 } } }); });
check("X5", "partial index (only titles with a free copy) created", p.ok);

// Text index for words inside titles
const tx = attempt(function () {
  db.titles.createIndex({ title: "text" }, { name: "ix_title_text", language_override: "textLanguage" });
  return db.titles.find({ $text: { $search: "garden" } }).limit(5).toArray();
});
if (tx.ok) print("   X6 text search 'garden' sample: " + tx.value.map(function (t) { return t.title; }).slice(0, 3).join(" | "));
check("X6", "text index answers a word search with $text", tx.ok && tx.value.length > 0);

// TTL index: documents delete themselves (search history kept 30 days)
const ttl = attempt(function () {
  db.search_log.insertOne({ q: "garden", at: new Date() });
  db.search_log.createIndex({ at: 1 }, { name: "ttl_30_days", expireAfterSeconds: 2592000 });
  return db.search_log.getIndexes();
});
check("X7", "TTL index (30 days) created on search_log.at", ttl.ok && ttl.value.some(function (i) { return i.expireAfterSeconds === 2592000; }));

// Index cost: size on disk
const st = attempt(function () { return db.titles.stats(); });
if (st.ok && st.value.indexSizes) {
  print("");
  print("   Index sizes (KB): " + Object.keys(st.value.indexSizes).map(function (k) { return k + "=" + Math.round(st.value.indexSizes[k] / 1024); }).join(", "));
}
check("X8", "the collection has the indexes created above", db.titles.getIndexes().length >= 5);

summary();
