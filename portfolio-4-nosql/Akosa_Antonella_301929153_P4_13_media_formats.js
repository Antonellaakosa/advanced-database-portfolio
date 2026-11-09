// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : Akosa_Antonella_301929153_P4_13_media_formats.js
// Purpose : A library does not only lend books. This script adds one title of
//           EACH format (book, e-book, audiobook, DVD, magazine), each carrying
//           the fields only that format has, extends the validation rules to
//           cover those fields, and queries them by format-specific fields.
//           In PostgreSQL this would mean either many empty columns or one table
//           per format; here each document simply carries what it needs.
// =====================================================================
load("Akosa_Antonella_301929153_P4_lib.js");
begin("13_media_formats");
banner("13  Different media formats in one collection");

const num = ["int", "long", "double", "decimal"];
// Extend the existing validation rule (kept from script 02) with the format-specific fields.
const info = db.getCollectionInfos({ name: "titles" })[0];
let extended = false;
if (info && info.options && info.options.validator) {
  const v = info.options.validator;
  Object.assign(v.$jsonSchema.properties, {
    pages:           { bsonType: num, minimum: 1 },
    fileFormat:      { enum: ["epub", "pdf", "mobi"] },
    fileSizeMb:      { bsonType: num, minimum: 0 },
    durationMinutes: { bsonType: num, minimum: 1 },
    narrator:        { bsonType: "string" },
    runtimeMinutes:  { bsonType: num, minimum: 1 },
    director:        { bsonType: "string" },
    ageRating:       { enum: ["G", "PG", "12", "15", "18"] },
    issueNumber:     { bsonType: num, minimum: 1 },
    issueDate:       { bsonType: "date" },
    frequency:       { enum: ["weekly", "monthly", "quarterly"] }
  });
  extended = attempt(function () { return db.runCommand({ collMod: "titles", validator: v }); }).ok;
}
check("N0", "the validation rule was extended with the format-specific fields (collMod)", extended);

const base = { category: { name: "Fiction" }, authors: [{ name: "Demo Author", order: 1 }], availability: { total: 1, available: 1 }, scratchFormat: true };
const docs = [
  Object.assign({ _id: 999301, title: "Format Demo: Printed Book", mediaType: "book", isbn: "9780000993011", pages: 320 }, base),
  Object.assign({ _id: 999302, title: "Format Demo: E-book", mediaType: "ebook", isbn: "9780000993028", fileFormat: "epub", fileSizeMb: 4.2 }, base),
  Object.assign({ _id: 999303, title: "Format Demo: Audiobook", mediaType: "audiobook", isbn: "9780000993035", durationMinutes: 540, narrator: "Demo Narrator" }, base),
  Object.assign({ _id: 999304, title: "Format Demo: DVD Documentary", mediaType: "dvd", runtimeMinutes: 135, director: "Demo Director", ageRating: "PG" }, base, { authors: [], category: { name: "Documentary" } }),
  Object.assign({ _id: 999305, title: "Format Demo: Monthly Magazine", mediaType: "magazine", issueNumber: 42, issueDate: new Date("2026-10-01"), frequency: "monthly" }, base, { authors: [] })
];
db.titles.deleteMany({ scratchFormat: true });
const ins = attempt(function () { return db.titles.insertMany(docs); });
check("N1", "one title of each of the five formats is accepted, each with its own fields", ins.ok);
if (!ins.ok) print("   error: " + ins.error.message);

// Queries on fields that exist only for one format
const longDvd = db.titles.find({ mediaType: "dvd", runtimeMinutes: { $gte: 120 }, scratchFormat: true }).toArray();
check("N2", "DVDs: filter by runtime (>= 120 minutes) finds the documentary", longDvd.length === 1 && longDvd[0].director === "Demo Director");
const mag = db.titles.find({ mediaType: "magazine", issueDate: { $gte: new Date("2026-10-01") }, scratchFormat: true }).toArray();
check("N3", "magazines: filter by issue date finds issue 42 (no ISBN, no author needed)", mag.length === 1 && mag[0].issueNumber === 42 && mag[0].isbn === undefined);
const ebk = db.titles.find({ mediaType: "ebook", fileFormat: "epub", scratchFormat: true }).toArray();
check("N4", "e-books: filter by file format finds the EPUB", ebk.length === 1);
const aud = db.titles.find({ mediaType: "audiobook", durationMinutes: { $gt: 500 }, scratchFormat: true }).toArray();
check("N5", "audiobooks: filter by duration finds the 9-hour recording", aud.length === 1 && aud[0].narrator === "Demo Narrator");

// The same collection also answers "everything we hold" across formats
const byType = db.titles.aggregate([{ $match: { scratchFormat: true } }, { $group: { _id: "$mediaType", n: { $sum: 1 } } }, { $sort: { _id: 1 } }]).toArray();
print("   one of each format in the collection: " + byType.map(function (r) { return r._id + "=" + r.n; }).join(", "));
check("N6", "a single query counts titles across all five formats", byType.length === 5);

// Validation still protects format-specific fields
function rejected(doc) { const r = attempt(function () { return db.titles.insertOne(doc); }); if (r.ok) db.titles.deleteOne({ _id: doc._id }); return !r.ok && isValidationError(r.error); }
check("N7", "rejected: a DVD with a negative runtime", rejected(Object.assign({ _id: 999311, title: "Bad DVD", mediaType: "dvd", runtimeMinutes: -5 }, base, { authors: [] })));
check("N8", "rejected: an e-book in an unknown file format (docx)", rejected(Object.assign({ _id: 999312, title: "Bad e-book", mediaType: "ebook", fileFormat: "docx" }, base)));

db.titles.deleteMany({ scratchFormat: true });
check("N9", "demonstration titles removed again", db.titles.countDocuments({ scratchFormat: true }) === 0);
summary();
