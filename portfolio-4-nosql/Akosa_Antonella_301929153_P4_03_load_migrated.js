// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : Akosa_Antonella_301929153_P4_03_load_migrated.js
// Purpose : Loads the 10 titles exported from PostgreSQL (data/Akosa_Antonella_301929153_P4_migrated_titles.js)
//           into MongoDB. The validation rules from step 02 apply to every one.
// =====================================================================
load("Akosa_Antonella_301929153_P4_lib.js");
load("data/Akosa_Antonella_301929153_P4_migrated_titles.js");          // defines migratedTitles
begin("03_migration");
banner("03  Load the titles migrated from PostgreSQL");

db.titles.deleteMany({ migratedFrom: "postgresql:upln.title" });
migratedTitles.forEach(function (d) {      // JSON numbers arrive as doubles; store years as int to satisfy the rule
  if (d.publicationYear !== undefined) d.publicationYear = NumberInt(d.publicationYear);
});
const r = attempt(function () { return db.titles.insertMany(migratedTitles); });
check("M1", "all migrated documents passed validation and were inserted", r.ok);
if (!r.ok) print("   error: " + r.error.message);

const n = db.titles.countDocuments({ migratedFrom: "postgresql:upln.title" });
check("M2", "document count in MongoDB equals the export (" + migratedTitles.length + ")", n === migratedTitles.length);

const one = db.titles.findOne({ _id: migratedTitles[0]._id });
print("");
print("   One migrated document (relational rows joined into one):");
print("   title        : " + one.title);
print("   authors      : " + one.authors.map(function (a) { return a.name; }).join(", "));
print("   publisher    : " + (one.publisher ? one.publisher.name : "-"));
print("   copies total : " + one.availability.total + " across " + one.availability.byBranch.length + " branches");
check("M3", "a migrated title carries its authors and branch availability inside it",
      one.authors.length >= 1 && one.availability.byBranch.length >= 1);

summary();
