// Backend mínimo: expone /health y verifica la conexión a la base de datos.
// Usa solo módulos nativos de Node (http) + el driver pg.
const http = require("http");
const { Client } = require("pg");

const PORT = 3000;
const dbConfig = {
  host: process.env.DB_HOST || "db",
  port: parseInt(process.env.DB_PORT || "5432", 10),
  user: process.env.DB_USER || "app",
  password: process.env.DB_PASSWORD || "app_secret",
  database: process.env.DB_NAME || "appdb",
  connectionTimeoutMillis: 3000,
};

async function checkDb() {
  const client = new Client(dbConfig);
  await client.connect();
  const res = await client.query("SELECT 1 AS ok");
  await client.end();
  return res.rows[0].ok === 1;
}

const server = http.createServer(async (req, res) => {
  if (req.url === "/health") {
    try {
      await checkDb();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok", db: "reachable" }));
    } catch (err) {
      res.writeHead(503, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "error", db: "unreachable", detail: err.message }));
    }
    return;
  }
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ service: "backend", endpoints: ["/health"] }));
});

server.listen(PORT, () => {
  console.log(`backend escuchando en :${PORT}`);
});
