import express from "express";
import dotenv from "dotenv";
import cors from "cors";
import { initDbAndSeed, queryFlights } from "./db";
import Redis from "ioredis";

dotenv.config();
const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;
const REDIS_URL = process.env.REDIS_URL || "redis://localhost:6379";
const CACHE_TTL_SEC = 120;

const redis = new Redis(REDIS_URL);

const app = express();
app.use(cors());
app.use(express.json());

app.get("/api/health", (_, res) => res.json({ status: "ok" }));

app.get("/api/v1/flights/search", async (req, res) => {
  try {
    const origin = (req.query.origin as string || "").toUpperCase();
    const dest = (req.query.dest as string || "").toUpperCase();
    const date = req.query.date as string;
    const passengers = parseInt((req.query.passengers as string) || "1", 10);

    if (!origin || !dest || !date) {
      return res.status(400).json({ error: "origin, dest and date are required" });
    }

    const cacheKey = `search:${origin}:${dest}:${date}:${passengers}`;
    const cached = await redis.get(cacheKey);
    if (cached) {
      return res.header("X-Cache", "HIT").json(JSON.parse(cached));
    }

    const results = await queryFlights(origin, dest, date, passengers);
    await redis.set(cacheKey, JSON.stringify(results), "EX", CACHE_TTL_SEC);
    res.header("X-Cache", "MISS").json(results);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "internal_error" });
  }
});

async function start() {
  await initDbAndSeed();
  app.listen(PORT, () => {
    console.log(`Backend listening on port ${PORT}`);
  });
}

start().catch((err) => {
  console.error("Failed to start:", err);
  process.exit(1);
});
