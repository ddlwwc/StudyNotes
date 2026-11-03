import mysql from "mysql2/promise";
import { drizzle } from "drizzle-orm/mysql2";
import { migrate } from "drizzle-orm/mysql2/migrator";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  throw new Error("DATABASE_URL is required");
}

const pool = mysql.createPool({
  uri: databaseUrl,
  connectionLimit: 2,
  timezone: "Z"
});

try {
  const db = drizzle(pool, { mode: "default" });
  await migrate(db, {
    migrationsFolder: new URL("../drizzle", import.meta.url).pathname
  });
  console.log("StudyNotes database migrations completed.");
} finally {
  await pool.end();
}
