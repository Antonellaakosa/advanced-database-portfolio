// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : 08_modelling_patterns.js
// Purpose : Three design decisions, each shown with a working example:
//           (1) embed vs reference, (2) computed pattern, (3) subset pattern.
// =====================================================================
load("lib.js");
begin("08_patterns");
banner("08  Modelling patterns: embed, reference, computed, subset");

const T = db.reviews.findOne({}, { titleId: 1 }).titleId;   // a title that already has reviews
db.reviews.deleteOne({ _id: 900001 });   // make the script safe to re-run
const base = db.titles.findOne({ _id: T });
check("P0", "demo title " + T + " exists", base !== null);

// (1) EMBED vs REFERENCE
// Authors and branch availability are embedded: they are read with the title every time and are small.
// Reviews are REFERENCED (own collection): they grow without limit, and 16 MB is the hard size of one document.
const nRev = db.reviews.countDocuments({ titleId: T });
print("   (1) title " + T + " embeds " + base.authors.length + " author(s) and " + base.availability.byBranch.length + " branch rows; its " + nRev + " reviews live in their own collection");
check("P1", "reviews are referenced by titleId, not embedded", base.reviews === undefined);

// (2) COMPUTED pattern: keep rating {sum, count} on the title so the average never needs a scan of reviews.
const r0 = base.rating;
db.reviews.insertOne({ _id: 900001, titleId: T, memberRef: "M-demo", stars: 5, comment: "pattern demo", createdAt: new Date() });
db.titles.updateOne({ _id: T }, { $inc: { "rating.sum": 5, "rating.count": 1 } });
const r1 = db.titles.findOne({ _id: T }).rating;
print("   (2) rating before " + r0.sum + "/" + r0.count + "  after " + r1.sum + "/" + r1.count + "  average now " + (r1.sum / r1.count).toFixed(2));
check("P2", "adding a review updates sum and count in one atomic $inc", r1.sum === r0.sum + 5 && r1.count === r0.count + 1);

// (3) SUBSET pattern: keep only the 3 newest reviews inside the title page document.
db.titles.updateOne({ _id: T }, { $set: { recentReviews: db.reviews.find({ titleId: T }).sort({ createdAt: -1, _id: -1 }).limit(3).toArray()
                                          .map(function (r) { return { stars: r.stars, comment: r.comment, at: r.createdAt }; }) } });
const withSubset = db.titles.findOne({ _id: T });
print("   (3) recentReviews embedded: " + withSubset.recentReviews.length + " of " + db.reviews.countDocuments({ titleId: T }) + " reviews");
check("P3", "at most 3 recent reviews embedded (the rest stay in reviews)", withSubset.recentReviews.length >= 1 && withSubset.recentReviews.length <= 3);

// Document size stays small
const size = (typeof bsonsize === "function") ? bsonsize(withSubset) : JSON.stringify(withSubset).length;
print("      document size: " + size + " bytes (limit 16,777,216)");
check("P4", "the title document is far below the 16 MB limit", size < 16 * 1024);

// clean up the demonstration changes
db.reviews.deleteOne({ _id: 900001 });
db.titles.updateOne({ _id: T }, { $set: { rating: r0 }, $unset: { recentReviews: "" } });
check("P5", "demo changes undone, data back to its original state", db.titles.findOne({ _id: T }).rating.count === r0.count);

summary();
