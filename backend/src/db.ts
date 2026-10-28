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
