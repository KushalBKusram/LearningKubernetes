// A small backend: a notes API on top of MongoDB. Stateless; the data lives in the database.
const http = require("node:http");
const { MongoClient } = require("mongodb");

const PORT = Number(process.env.PORT || 3000);
const MONGO_URL = process.env.MONGO_URL || "mongodb://localhost:27017";

const client = new MongoClient(MONGO_URL, { serverSelectionTimeoutMS: 3000 });
const notes = () => client.db("notes").collection("notes");

function send(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > 10_000) reject(new Error("body too large"));
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  const { pathname } = new URL(req.url, "http://localhost");
  try {
    if (req.method === "GET" && pathname === "/api/health") {
      await client.db("admin").command({ ping: 1 });
      return send(res, 200, { status: "ok", database: "connected" });
    }
    if (req.method === "GET" && pathname === "/api/notes") {
      const list = await notes().find().sort({ createdAt: -1 }).limit(50).toArray();
      return send(res, 200, list.map((n) => ({ id: String(n._id), text: n.text, createdAt: n.createdAt })));
    }
    if (req.method === "POST" && pathname === "/api/notes") {
      const body = JSON.parse((await readBody(req)) || "{}");
      const text = typeof body.text === "string" ? body.text.trim() : "";
      if (!text || text.length > 200) return send(res, 400, { error: "text must be 1 to 200 characters" });
      const doc = { text, createdAt: new Date().toISOString() };
      const { insertedId } = await notes().insertOne(doc);
      return send(res, 201, { id: String(insertedId), text: doc.text, createdAt: doc.createdAt });
    }
    return send(res, 404, { error: "not found" });
  } catch (err) {
    console.error(err.message);
    return send(res, 500, { error: "internal error" });
  }
});

client.connect().then(
  () => console.log("connected to MongoDB"),
  (err) => console.error("MongoDB not reachable yet:", err.message),
);
server.listen(PORT, () => console.log(`api listening on ${PORT}`));
