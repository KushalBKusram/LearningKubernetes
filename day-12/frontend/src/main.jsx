import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

function App() {
  const [notes, setNotes] = useState([]);
  const [text, setText] = useState("");
  const [error, setError] = useState("");

  async function load() {
    const res = await fetch("/api/notes");
    if (!res.ok) throw new Error(`the API answered ${res.status}`);
    setNotes(await res.json());
  }

  useEffect(() => {
    load().catch((e) => setError(e.message));
  }, []);

  async function add(event) {
    event.preventDefault();
    setError("");
    const res = await fetch("/api/notes", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });
    if (!res.ok) {
      setError(`the API answered ${res.status}`);
      return;
    }
    setText("");
    await load();
  }

  return (
    <main>
      <h1>Day 12: full-stack notes</h1>
      <p>
        This page is a React build stored in an S3-compatible bucket. The notes come from a Node.js API
        and are stored in MongoDB. Both are reached through the same address.
      </p>
      <form onSubmit={add}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder="Write a note" maxLength={200} />
        <button type="submit" disabled={!text.trim()}>Add</button>
      </form>
      {error && <p role="alert">Something went wrong: {error}</p>}
      <ul>
        {notes.map((n) => (
          <li key={n.id}>{n.text}</li>
        ))}
      </ul>
    </main>
  );
}

createRoot(document.getElementById("root")).render(<App />);
