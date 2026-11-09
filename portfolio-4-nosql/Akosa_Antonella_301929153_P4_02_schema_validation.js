// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : Akosa_Antonella_301929153_P4_02_schema_validation.js
// Purpose : Creates the `titles` collection WITH a validation rule
//           ($jsonSchema). MongoDB is "schema-flexible", not "schema-less":
//           we fix the core fields and still allow optional extras.
// =====================================================================
load("Akosa_Antonella_301929153_P4_lib.js");
begin("02_validation");
banner("02  Schema validation: rules on the titles collection");

db.titles.drop();
db.createCollection("titles", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["title", "mediaType", "category", "authors", "availability"],
    properties: {
      title:     { bsonType: "string", minLength: 1, maxLength: 300 },
      mediaType: { enum: ["book", "ebook", "audiobook", "dvd", "magazine"] },
      isbn:      { bsonType: "string", pattern: "^[0-9]{10,13}$" },
      publicationYear: { bsonType: "int", minimum: 1400, maximum: 2100 },
      category:  { bsonType: "object", required: ["name"], properties: { name: { bsonType: "string" } } },
      authors:   { bsonType: "array", items: { bsonType: "object", required: ["name"],
                   properties: { name: { bsonType: "string" } } } },
      availability: { bsonType: "object", required: ["total", "available"], properties: {
                   total:     { bsonType: ["int", "long", "double"], minimum: 0 },
                   available: { bsonType: ["int", "long", "double"], minimum: 0 } } }
    }
  } },
  validationLevel: "strict",
  validationAction: "error"
});
print("   collection 'titles' created with a $jsonSchema validator");

const good = { title: "Validation Test Title", mediaType: "book", isbn: "9780000000001",
  publicationYear: NumberInt(2020), category: { name: "Computing" },
  authors: [{ name: "Test Author", order: 1 }], availability: { total: 2, available: 2 } };

const r1 = attempt(function () { return db.titles.insertOne(Object.assign({ _id: 999001 }, good)); });
check("V1", "a correct document is accepted", r1.ok);
db.titles.deleteOne({ _id: 999001 });

function rejected(id, doc) {
  const r = attempt(function () { return db.titles.insertOne(Object.assign({ _id: id }, doc)); });
  if (r.ok) db.titles.deleteOne({ _id: id });
  return !r.ok && isValidationError(r.error);
}
function without(f) { const d = Object.assign({}, good); delete d[f]; return d; }

check("V2", "rejected: title missing",                 rejected(999002, without("title")));
check("V3", "rejected: mediaType 'vinyl' not allowed", rejected(999003, Object.assign({}, good, { mediaType: "vinyl" })));
check("V4", "rejected: publicationYear stored as text", rejected(999004, Object.assign({}, good, { publicationYear: "2020" })));
check("V5", "rejected: negative number of copies",     rejected(999005, Object.assign({}, good, { availability: { total: -1, available: 0 } })));
check("V6", "rejected: ISBN with letters",             rejected(999006, Object.assign({}, good, { isbn: "ABC-123" })));
check("V7", "rejected: an author without a name",      rejected(999007, Object.assign({}, good, { authors: [{ order: 1 }] })));

// Flexible side: an audiobook may carry fields a book does not have.
const audio = Object.assign({ _id: 999008 }, good, { mediaType: "audiobook", durationMinutes: 540, narrator: "Test Narrator" });
const r8 = attempt(function () { return db.titles.insertOne(audio); });
check("V8", "flexible: audiobook with extra fields (durationMinutes, narrator) accepted", r8.ok);
db.titles.deleteOne({ _id: 999008 });

summary();
