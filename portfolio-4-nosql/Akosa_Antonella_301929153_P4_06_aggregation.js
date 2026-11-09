// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : 06_aggregation.js
// Purpose : The aggregation framework: group, unwind, bucket, lookup,
//           facet and writing a result collection. Each pipeline is the
//           MongoDB counterpart of a SQL GROUP BY / JOIN report.
// =====================================================================
load("lib.js");
begin("06_aggregation");
banner("06  Aggregation pipelines");

// A1 titles per category   (GROUP BY)
const a1 = db.titles.aggregate([
  { $group: { _id: "$category.name", titles: { $sum: 1 } } },
  { $sort: { titles: -1, _id: 1 } }
]).toArray();
print("   A1 titles per category: " + a1.map(function (r) { return r._id + "=" + r.titles; }).join(", "));
check("A1", "$group counts titles per category (5 categories, total 100,010)",
      a1.length === 5 && a1.reduce(function (s, r) { return s + r.titles; }, 0) === 100010);

// A2 busiest authors   ($unwind turns an array into rows)
const a2 = db.titles.aggregate([
  { $match: { generated: true } },
  { $unwind: "$authors" },
  { $group: { _id: "$authors.name", books: { $sum: 1 } } },
  { $sort: { books: -1, _id: 1 } },
  { $limit: 3 }
]).toArray();
print("   A2 top 3 authors: " + a2.map(function (r) { return r._id + " (" + r.books + ")"; }).join(", "));
check("A2", "$unwind + $group ranks authors, top 3 returned", a2.length === 3 && a2[0].books >= a2[2].books);

// A3 copies per branch (unwind the embedded byBranch array)
const a3 = db.titles.aggregate([
  { $unwind: "$availability.byBranch" },
  { $group: { _id: "$availability.byBranch.branch",
              copies: { $sum: "$availability.byBranch.copies" },
              available: { $sum: "$availability.byBranch.available" } } },
  { $sort: { _id: 1 } }
]).toArray();
print("   A3 copies per branch: " + a3.map(function (r) { return String(r._id).replace("UPLN ", "") + "=" + r.copies; }).join(", "));
check("A3", "copies per branch computed from the embedded availability (5 branches)", a3.length === 5);

// A4 average rating per category ($avg of a computed value)
const r4 = attempt(function () {
  return db.titles.aggregate([
    { $match: { "rating.count": { $gt: 0 } } },
    { $group: { _id: "$category.name", ratedTitles: { $sum: 1 }, avgStars: { $avg: { $divide: ["$rating.sum", "$rating.count"] } } } },
    { $sort: { _id: 1 } }
  ]).toArray();
});
if (r4.ok) print("   A4 average stars: " + r4.value.map(function (r) { return r._id + "=" + r.avgStars.toFixed(2); }).join(", "));
check("A4", "$avg of (sum / count) gives average stars per category", r4.ok && r4.value.length === 5 && r4.value.every(function (r) { return r.avgStars >= 1 && r.avgStars <= 5; }));

// A5 decades with $bucket
const r5 = attempt(function () {
  return db.titles.aggregate([
    { $bucket: { groupBy: "$publicationYear", boundaries: [1950, 1980, 2000, 2020, 2030], default: "other",
                 output: { titles: { $sum: 1 } } } }
  ]).toArray();
});
if (r5.ok) print("   A5 by period: " + r5.value.map(function (r) { return r._id + "=" + r.titles; }).join(", "));
check("A5", "$bucket groups publication years into periods; counts add up to 100,010",
      r5.ok && r5.value.reduce(function (s, r) { return s + r.titles; }, 0) === 100010);

// A6 join with $lookup (reviews live in their own collection, referenced by titleId)
const r6 = attempt(function () {
  return db.reviews.aggregate([
    { $group: { _id: "$titleId", reviews: { $sum: 1 }, avgStars: { $avg: "$stars" } } },
    { $match: { reviews: { $gte: 3 } } },
    { $sort: { reviews: -1, _id: 1 } },
    { $limit: 3 },
    { $lookup: { from: "titles", localField: "_id", foreignField: "_id", as: "title" } },
    { $unwind: "$title" },
    { $project: { _id: 0, titleId: "$_id", name: "$title.title", reviews: 1, avgStars: { $round: ["$avgStars", 2] } } }
  ]).toArray();
});
if (r6.ok) print("   A6 most reviewed: " + r6.value.map(function (r) { return r.name + " (" + r.reviews + " reviews, " + r.avgStars + " stars)"; }).join(" | "));
check("A6", "$lookup joins reviews to titles (the MongoDB version of a JOIN)", r6.ok && r6.value.length === 3 && r6.value[0].name !== undefined);

// A7 several reports in one pass with $facet
const r7 = attempt(function () {
  return db.titles.aggregate([
    { $facet: {
        byMedia:  [ { $group: { _id: "$mediaType", n: { $sum: 1 } } }, { $sort: { n: -1 } } ],
        freeCopies: [ { $group: { _id: null, free: { $sum: "$availability.available" } } } ]
    } }
  ]).toArray()[0];
});
if (r7.ok) print("   A7 media types: " + r7.value.byMedia.map(function (r) { return r._id + "=" + r.n; }).join(", "));
check("A7", "$facet returns two reports from one scan", r7.ok && r7.value.byMedia.length >= 4 && r7.value.freeCopies[0].free > 0);

// A8 store a result collection ($merge) so dashboards need not recompute
const r8 = attempt(function () {
  db.category_summary.drop();
  db.titles.aggregate([
    { $group: { _id: "$category.name", titles: { $sum: 1 }, freeCopies: { $sum: "$availability.available" } } },
    { $merge: { into: "category_summary" } }
  ]).toArray();
  return db.category_summary.countDocuments({});
});
check("A8", "$merge writes the per-category summary into its own collection (5 documents)", r8.ok && r8.value === 5);

summary();
