// Runs once, the first time the secure MongoDB is created (as the root account).
// Two further accounts, each with only the rights its job needs.
const d = db.getSiblingDB("upln_nosql");
d.createUser({ user: "catalogue_app",    pwd: process.env.APP_PW,    roles: [{ role: "readWrite", db: "upln_nosql" }] });
d.createUser({ user: "catalogue_report", pwd: process.env.REPORT_PW, roles: [{ role: "read",      db: "upln_nosql" }] });
