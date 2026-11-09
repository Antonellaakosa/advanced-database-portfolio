// =====================================================================
// Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
// File    : Akosa_Antonella_301929153_P4_04_generate_data.js
// Purpose : Adds 100,000 synthetic titles and 50,000 reviews so that
//           indexes and explain plans mean something. Fixed random seed,
//           so every run produces the same data. All data is fictional.
// =====================================================================
load("Akosa_Antonella_301929153_P4_lib.js");
begin("04_data");
banner("04  Generate 100,000 synthetic titles and 50,000 reviews");

let seed = 20261024;
function rnd() { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; }
function pick(a) { return a[Math.floor(rnd() * a.length)]; }
function between(lo, hi) { return lo + Math.floor(rnd() * (hi - lo + 1)); }

const adjectives = ["Silent","Golden","Hidden","Broken","Distant","Rising","Forgotten","Burning","Gentle","Last","First","Crimson","Quiet","Endless","Lost"];
const nouns = ["River","Harvest","Kingdom","Market","Garden","Archive","Journey","Signal","Harbour","Mirror","Compass","Season","Bridge","Language","Machine"];
const topics = ["Databases","Networks","Algorithms","Security","Statistics","Economics","Health","Farming","Music","Politics"];
const firsts = ["Amara","Chidi","Ngozi","Tunde","Fatima","Emeka","Zainab","Ifeanyi","Bola","Halima","Segun","Aisha","Obinna","Kemi","Yusuf","Ada","Femi","Hauwa","Uche","Sade"];
const lasts  = ["Okafor","Bello","Adeyemi","Nwosu","Ibrahim","Eze","Balogun","Musa","Okonkwo","Lawal","Abubakar","Chukwu","Ojo","Danjuma","Obi"];
const categories = ["Children","Computing","Documentary","Fiction","History"];
const media = ["book","book","book","ebook","audiobook","dvd","magazine"];
const langs = ["English","English","English","Hausa","Yoruba","Igbo"];
const publishers = [["Penguin Books","United Kingdom"],["Farafina Books","Nigeria"],["Spectrum Books","Nigeria"],["Pearson Education","United Kingdom"],["Kachifo Press","Nigeria"],["Cassava Republic","Nigeria"]];
const branches = ["UPLN Headquarters (Abuja)","UPLN Lagos Branch","UPLN Port Harcourt Branch","UPLN Kano Branch","UPLN Enugu Branch"];

const N = 100000, START = 1001, BATCH = 5000;
db.titles.deleteMany({ generated: true });
let t0 = Date.now();
for (let s = 0; s < N; s += BATCH) {
  const docs = [];
  for (let i = s; i < s + BATCH; i++) {
    const id = START + i, cat = pick(categories), type = pick(media);
    const nAuth = rnd() < 0.8 ? 1 : (rnd() < 0.8 ? 2 : 3);
    const authors = [];
    for (let a = 1; a <= nAuth; a++) authors.push({ name: pick(firsts) + " " + pick(lasts), order: a });
    const pub = pick(publishers);
    const nb = between(1, 4), brs = [], used = {};
    let total = 0, avail = 0;
    while (brs.length < nb) {
      const b = pick(branches); if (used[b]) continue; used[b] = true;
      const c = between(1, 3), av = between(0, c);
      brs.push({ branch: b, copies: c, available: av }); total += c; avail += av;
    }
    const cnt = between(0, 40);
    const d = {
      _id: id,
      title: pick(adjectives) + " " + pick(nouns) + (rnd() < 0.3 ? ": " + pick(topics) : "") + " " + (id % 97),
      mediaType: type,
      isbn: String(9780000000000 + id),
      publicationYear: NumberInt(between(1950, 2026)),
      language: pick(langs),
      category: { name: cat },
      publisher: { name: pub[0], country: pub[1] },
      authors: authors,
      subjects: [cat.toLowerCase(), pick(topics).toLowerCase()],
      availability: { total: total, available: avail, byBranch: brs },
      rating: { sum: cnt * between(2, 5), count: cnt },
      generated: true
    };
    if (type === "audiobook") d.durationMinutes = between(120, 900);
    if (type === "book") d.pages = between(80, 900);
    if (type === "ebook") d.fileSizeMb = between(1, 40);
    docs.push(d);
  }
  db.titles.insertMany(docs, { ordered: false });
}
print("   titles inserted in " + ((Date.now() - t0) / 1000).toFixed(1) + " s");

db.reviews.drop();
t0 = Date.now();
for (let s = 0; s < 50000; s += BATCH) {
  const docs = [];
  for (let i = s; i < s + BATCH; i++) {
    docs.push({ _id: i + 1, titleId: START + between(0, N - 1), memberRef: "M" + between(1, 5000),
                stars: between(1, 5), comment: pick(["Loved it","Slow start","Worth borrowing","Not for me","Great for students","Well written"]),
                createdAt: new Date(Date.UTC(2025, 0, 1) + between(0, 600) * 86400000) });
  }
  db.reviews.insertMany(docs, { ordered: false });
}
print("   reviews inserted in " + ((Date.now() - t0) / 1000).toFixed(1) + " s");

const nt = db.titles.countDocuments({ generated: true });
check("G1", "100,000 generated titles stored (all passed validation)", nt === N);
check("G2", "50,000 reviews stored", db.reviews.countDocuments({}) === 50000);
check("G3", "titles total = 10 migrated + 100,000 generated", db.titles.countDocuments({}) === N + 10);
summary();
