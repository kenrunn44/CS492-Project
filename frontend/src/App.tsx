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
