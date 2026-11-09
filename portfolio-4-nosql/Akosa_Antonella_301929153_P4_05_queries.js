// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : Akosa_Antonella_301929153_P4_05_queries.js
// Purpose : Everyday MongoDB operations (CRUD) on the titles collection,
//           each paired with the SQL idea it replaces.
// =====================================================================
load("Akosa_Antonella_301929153_P4_lib.js");
begin("05_queries");
banner("05  Queries and updates (CRUD)");

// Q1 equality on a nested field   (SQL: WHERE category_name = 'Computing')
const q1 = db.titles.find({ "category.name": "Computing", generated: { $ne: true } }).toArray();
print("   Q1 migrated Computing titles: " + q1.map(function (t) { return t.title; }).join(" | "));
check("Q1", "find by nested field category.name returns only Computing titles",
      q1.length > 0 && q1.every(function (t) { return t.category.name === "Computing"; }));

// Q2 array element match   (SQL: JOIN title_author ... WHERE author = ...)
const q2 = db.titles.find({ "authors.name": "Chinua Achebe" }).toArray();
check("Q2", "find by an author name inside the authors array", q2.length >= 1);

// Q3 operators $in, $gte, projection, sort, limit
const q3 = db.titles.find(
  { mediaType: { $in: ["audiobook", "ebook"] }, publicationYear: { $gte: 2020 } },
  { _id: 0, title: 1, mediaType: 1, publicationYear: 1 }
).sort({ publicationYear: -1, title: 1 }).limit(5).toArray();
print("   Q3 newest audio/e-books (top 5): " + q3.map(function (t) { return t.title + " (" + t.publicationYear + ")"; }).join(" | "));
check("Q3", "$in + $gte with projection, sort and limit returns 5 rows in year order",
      q3.length === 5 && q3[0].publicationYear >= q3[4].publicationYear && q3[0].isbn === undefined);

// Q4 $or / $and   (SQL: WHERE (a OR b) AND c)
const q4 = db.titles.countDocuments({ $and: [ { $or: [ { "category.name": "History" }, { "category.name": "Documentary" } ] },
                                              { "availability.available": { $gt: 0 } } ] });
check("Q4", "$and / $or combination counts titles with at least one free copy", q4 > 0);

// Q5 regular expression   (SQL: ILIKE)
const q5 = db.titles.countDocuments({ title: { $regex: "^silent", $options: "i" } });
check("Q5", "case-insensitive prefix search with $regex", q5 > 0);

// Q6 update with operators: borrow one copy of title 1 at the first branch with stock, then return it
const before = db.titles.findOne({ _id: 1 }).availability.available;
db.titles.updateOne({ _id: 1, "availability.available": { $gt: 0 } }, { $inc: { "availability.available": -1 } });
const mid = db.titles.findOne({ _id: 1 }).availability.available;
db.titles.updateOne({ _id: 1 }, { $inc: { "availability.available": 1 } });
const after = db.titles.findOne({ _id: 1 }).availability.available;
print("   Q6 availability of title 1: " + before + " -> " + mid + " -> " + after);
check("Q6", "$inc changes one number atomically and the return restores it", mid === before - 1 && after === before);

// Q7 array update operators ($push / $pull)
db.titles.updateOne({ _id: 1 }, { $push: { subjects: "african literature" } });
const s1 = db.titles.findOne({ _id: 1 }).subjects.indexOf("african literature") >= 0;
db.titles.updateOne({ _id: 1 }, { $pull: { subjects: "african literature" } });
const s2 = db.titles.findOne({ _id: 1 }).subjects.indexOf("african literature") < 0;
check("Q7", "$push adds and $pull removes an array element", s1 && s2);

// Q8 upsert   (SQL: INSERT ... ON CONFLICT DO UPDATE)
db.titles.deleteOne({ _id: 999100 });
const up = db.titles.updateOne({ _id: 999100 },
  { $set: { title: "Upsert Demo", mediaType: "book", category: { name: "Computing" }, authors: [{ name: "Demo Author" }],
            availability: { total: 1, available: 1 }, scratch: true } }, { upsert: true });
check("Q8", "upsert inserts a missing document", up.upsertedCount === 1 || up.upsertedId !== undefined);

// Q9 delete and bulkWrite
const bw = db.titles.bulkWrite([
  { updateOne: { filter: { _id: 999100 }, update: { $set: { title: "Upsert Demo (edited)" } } } },
  { deleteOne: { filter: { _id: 999100 } } }
]);
check("Q9", "bulkWrite runs an update and a delete in one round trip", bw.modifiedCount === 1 && bw.deletedCount === 1);
check("Q10", "the demo document is gone afterwards", db.titles.countDocuments({ scratch: true }) === 0);

summary();
