import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const apiKey = Deno.env.get("OPENWEATHERMAP_API_KEY")?.trim();
  if (!apiKey) {
    return jsonResponse(
      { error: "OPENWEATHERMAP_API_KEY is not configured." },
      500,
    );
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }

  const lat = Number(payload.lat ?? payload.latitude);
  const lon = Number(payload.lon ?? payload.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return jsonResponse({ error: "lat and lon are required." }, 400);
  }

  const params = new URLSearchParams({
    lat: String(lat),
    lon: String(lon),
    appid: apiKey,
    units: "metric",
  });
  const weatherUrl = `https://api.openweathermap.org/data/2.5/weather?${params}`;
  const forecastUrl = `https://api.openweathermap.org/data/2.5/forecast?${params}`;

  const [weatherRes, forecastRes] = await Promise.all([
    fetch(weatherUrl),
    fetch(forecastUrl),
  ]);

  if (!weatherRes.ok || !forecastRes.ok) {
    const weatherText = weatherRes.ok ? "" : await weatherRes.text();
    const forecastText = forecastRes.ok ? "" : await forecastRes.text();
    return jsonResponse(
      {
        error: "OpenWeather request failed.",
        weatherStatus: weatherRes.status,
        forecastStatus: forecastRes.status,
        details: weatherText || forecastText,
      },
      502,
    );
  }

  return jsonResponse({
    weather: await weatherRes.json(),
    forecast: await forecastRes.json(),
  });
});
