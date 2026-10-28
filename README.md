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
