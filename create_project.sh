#!/usr/bin/env bash
set -e

echo "Creating project structure..."

mkdir -p backend/src
mkdir -p frontend/src

cat > docker-compose.yml <<'DOCKER'
version: '3.8'
services:
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: flightsdb
    volumes:
      - db-data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
  redis:
    image: redis:7
    ports:
      - "6379:6379"
  backend:
    build: ./backend
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/flightsdb
      REDIS_URL: redis://redis:6379
      PORT: 3000
    ports:
      - "3000:3000"
  frontend:
    build: ./frontend
    depends_on:
      - backend
    environment:
      VITE_API_BASE_URL: http://localhost:3000
    ports:
      - "5173:5173"
volumes:
  db-data:
DOCKER

cat > .env.example <<'ENV'
# Copy to .env to override defaults locally (not required for docker-compose)
DATABASE_URL=postgres://postgres:postgres@localhost:5432/flightsdb
REDIS_URL=redis://localhost:6379
PORT=3000
API_BASE_URL=http://localhost:3000
ENV

cat > README.md <<'MD'
# Online Airline Reservation — Sprint 1 (Executable build)

This project implements Sprint 1 (Flight Search) from the CS492 project document:
- Backend: Node.js + TypeScript + Express
- Database: PostgreSQL (seeded on startup)
- Cache: Redis (120s TTL for flight search)
- Frontend: React + TypeScript (Vite)
- Run with Docker Compose

Requirements
- Docker & docker-compose

Quick start
1. Build and start containers:
   docker-compose up --build

2. Open the UI:
   http://localhost:5173

3. Backend API:
   GET /api/v1/flights/search?origin=JFK&dest=LHR&date=2027-02-15&passengers=1
   Example: http://localhost:3000/api/v1/flights/search?origin=JFK&dest=LHR&date=2027-02-15

Project layout
- backend/  - Express API, DB seed, Redis caching
- frontend/ - React SPA (Vite)
- docker-compose.yml
- .env.example

Notes
- Backend creates tables and seeds sample airports & flights if not present.
- Caching TTL is 120 seconds (matches project doc).
- This deliverable targets Sprint 1 functionality (EPIC-1 / US-001, US-002).
MD

cat > backend/Dockerfile <<'DFB'
FROM node:18-alpine
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
COPY src ./src
RUN npm run build
EXPOSE 3000
CMD ["node", "dist/index.js"]
DFB

cat > backend/package.json <<'PKG'
{
  "name": "airline-backend",
  "version": "1.0.0",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "ts-node-dev --respawn --transpile-only src/index.ts"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ioredis": "^5.3.2",
    "pg": "^8.11.0",
    "dotenv": "^16.0.3",
    "cors": "^2.8.5"
  },
  "devDependencies": {
    "@types/express": "^4.17.17",
    "@types/node": "^20.2.5",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.1.6"
  }
}
PKG

cat > backend/tsconfig.json <<'TS'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  }
}
TS

cat > backend/src/index.ts <<'IDX'
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
IDX

cat > backend/src/db.ts <<'DB'
import { Pool } from "pg";

const DATABASE_URL = process.env.DATABASE_URL || "postgres://postgres:postgres@localhost:5432/flightsdb";
export const pool = new Pool({ connectionString: DATABASE_URL });

export async function initDbAndSeed(): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query(`BEGIN`);

    await client.query(`
      CREATE TABLE IF NOT EXISTS airports (
        code VARCHAR(8) PRIMARY KEY,
        name TEXT NOT NULL,
        city TEXT NOT NULL,
        country TEXT NOT NULL
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS flights (
        id SERIAL PRIMARY KEY,
        flight_number VARCHAR(16) NOT NULL,
        origin VARCHAR(8) REFERENCES airports(code),
        destination VARCHAR(8) REFERENCES airports(code),
        departure TIMESTAMP WITH TIME ZONE NOT NULL,
        arrival TIMESTAMP WITH TIME ZONE NOT NULL,
        base_price_cents INT NOT NULL
      );
    `);

    await client.query(`
      INSERT INTO airports (code, name, city, country)
      VALUES
        ('JFK','John F. Kennedy International Airport','New York','USA'),
        ('LHR','Heathrow Airport','London','UK'),
        ('SFO','San Francisco International Airport','San Francisco','USA')
      ON CONFLICT DO NOTHING;
    `);

    const { rows } = await client.query(`SELECT count(*) AS cnt FROM flights`);
    const cnt = parseInt(rows[0].cnt, 10);

    if (cnt === 0) {
      await client.query(`
        INSERT INTO flights (flight_number, origin, destination, departure, arrival, base_price_cents) VALUES
        ('AA100','JFK','LHR','2027-02-15T07:30:00Z','2027-02-15T18:30:00Z', 55000),
        ('AA101','JFK','LHR','2027-02-15T12:00:00Z','2027-02-15T23:00:00Z', 52000),
        ('UA200','SFO','LHR','2027-02-15T08:00:00Z','2027-02-15T20:00:00Z', 78000),
        ('DL300','JFK','SFO','2027-02-15T09:00:00Z','2027-02-15T15:00:00Z', 30000);
      `);
    }

    await client.query(`COMMIT`);
    console.log("Database initialized and seeded");
  } catch (err) {
    await client.query(`ROLLBACK`);
    console.error("DB init failed", err);
    throw err;
  } finally {
    client.release();
  }
}

export async function queryFlights(origin: string, dest: string, date: string, passengers: number) {
  const start = `${date}T00:00:00Z`;
  const end = `${date}T23:59:59Z`;

  const q = `
    SELECT f.id, flight_number, origin, destination, departure, arrival, base_price_cents
    FROM flights f
    WHERE origin = $1 AND destination = $2
      AND departure >= $3 AND departure <= $4
    ORDER BY departure ASC
    LIMIT 100
  `;

  const values = [origin, dest, start, end];
  const { rows } = await pool.query(q, values);

  return rows.map((r: any) => ({
    id: r.id,
    flightNumber: r.flight_number,
    origin: r.origin,
    destination: r.destination,
    departure: r.departure,
    arrival: r.arrival,
    basePrice: (r.base_price_cents / 100).toFixed(2),
    totalPrice: ((r.base_price_cents * passengers) / 100).toFixed(2)
  }));
}
DB

cat > frontend/Dockerfile <<'FDF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json tsconfig.json vite.config.ts ./
RUN npm ci
COPY src ./src
RUN npm run build
EXPOSE 5173
CMD ["npm", "run", "preview"]
FDF

cat > frontend/package.json <<'FPKG'
{
  "name": "airline-frontend",
  "version": "1.0.0",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview --port 5173 --strictPort"
  },
  "dependencies": {
    "axios": "^1.4.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.14",
    "@types/react-dom": "^18.2.7",
    "typescript": "^5.1.6",
    "vite": "^5.2.0",
    "@vitejs/plugin-react": "^4.0.0"
  }
}
FPKG

cat > frontend/vite.config.ts <<'VITE'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: true
  }
})
VITE

cat > frontend/tsconfig.json <<'FTS'
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020","DOM"],
    "jsx": "react-jsx",
    "module": "ESNext",
    "moduleResolution": "Node",
    "strict": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src"]
}
FTS

cat > frontend/src/main.tsx <<'MAIN'
import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./styles.css";

createRoot(document.getElementById("root")!).render(<App />);
MAIN

cat > frontend/src/App.tsx <<'APP'
import React, { useState } from "react";
import axios from "axios";

type Flight = {
  id: number;
  flightNumber: string;
  origin: string;
  destination: string;
  departure: string;
  arrival: string;
  basePrice: string;
  totalPrice: string;
};

const apiBase = import.meta.env.VITE_API_BASE_URL || "http://localhost:3000";

export default function App() {
  const [origin, setOrigin] = useState("JFK");
  const [dest, setDest] = useState("LHR");
  const [date, setDate] = useState("2027-02-15");
  const [passengers, setPassengers] = useState(1);
  const [results, setResults] = useState<Flight[]>([]);
  const [loading, setLoading] = useState(false);
  const [sortBy, setSortBy] = useState<"departure" | "price">("departure");

  async function search() {
    setLoading(true);
    try {
      const url = `${apiBase}/api/v1/flights/search`;
      const resp = await axios.get(url, {
        params: { origin, dest, date, passengers }
      });
      setResults(resp.data);
    } catch (err) {
      alert("Search failed. Check backend logs.");
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  const sorted = [...results].sort((a, b) => {
    if (sortBy === "departure") return new Date(a.departure).getTime() - new Date(b.departure).getTime();
    return parseFloat(a.totalPrice) - parseFloat(b.totalPrice);
  });

  return (
    <div className="container">
      <h1>Online Airline Reservation — Flight Search (Sprint 1)</h1>

      <div className="form">
        <label>Origin (IATA): <input value={origin} onChange={e => setOrigin(e.target.value.toUpperCase())} /></label>
        <label>Destination (IATA): <input value={dest} onChange={e => setDest(e.target.value.toUpperCase())} /></label>
        <label>Date: <input type="date" value={date} onChange={e => setDate(e.target.value)} /></label>
        <label>Passengers: <input type="number" min={1} value={passengers} onChange={e => setPassengers(Number(e.target.value))} /></label>
        <button onClick={search} disabled={loading}>{loading ? "Searching…" : "Search"}</button>
      </div>

      <div className="controls">
        <label>Sort by:
          <select value={sortBy} onChange={e => setSortBy(e.target.value as any)}>
            <option value="departure">Departure time</option>
            <option value="price">Total price</option>
          </select>
        </label>
      </div>

      <div className="results">
        {sorted.length === 0 ? <p>No results yet.</p> : (
          sorted.map(f => (
            <div key={f.id} className="card">
              <div><strong>{f.flightNumber}</strong> {f.origin} → {f.destination}</div>
              <div>Departs: {new Date(f.departure).toUTCString()}</div>
              <div>Arrives: {new Date(f.arrival).toUTCString()}</div>
              <div>Price per pax: ${f.basePrice} — Total: ${f.totalPrice}</div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
APP

cat > frontend/src/styles.css <<'CSS'
body { font-family: Arial, Helvetica, sans-serif; margin: 20px; }
.container { max-width: 900px; margin: 0 auto; }
.form { display:flex; gap: 8px; flex-wrap:wrap; align-items:center; margin-bottom: 12px; }
.form label { display:flex; gap:6px; align-items:center; }
.form input { padding:4px 6px; }
button { padding:6px 10px; }
.controls { margin-bottom:12px; }
.results .card { border: 1px solid #ddd; padding:8px; margin-bottom:8px; border-radius:4px; }
CSS

cat > frontend/index.html <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1.0" />
    <title>Flight Search</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
HTML

cat > .gitignore <<'GIT'
node_modules
dist
.env
.env.local
.vscode
GIT

echo "Files created."
echo "Next steps:"
echo "1) chmod +x create_project.sh"
echo "2) ./create_project.sh"
echo "3) docker-compose up --build"