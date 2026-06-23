(function () {
  const DATA_URL = "data/incidents.geojson";
  const YOUTUBE_CHANNEL_URL = "https://www.youtube.com/@Reckless-Rides-UK";
  const DEFAULT_CENTER = [54.5, -3.5];
  const DEFAULT_ZOOM = 6;

  const map = L.map("map", { scrollWheelZoom: true }).setView(DEFAULT_CENTER, DEFAULT_ZOOM);

  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(map);

  function escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  function popupHtml(props) {
    const title = escapeHtml(props.title || "Incident");
    const when = escapeHtml(props.recorded_bst || props.recorded_utc || "");
    const yt = props.youtube_url
      ? `<a href="${escapeHtml(props.youtube_url)}" target="_blank" rel="noopener noreferrer">Watch clip</a>`
      : "";
    const channel = `<a href="${YOUTUBE_CHANNEL_URL}" target="_blank" rel="noopener noreferrer">Channel (@Reckless-Rides-UK)</a>`;
    const maps = props.map_url
      ? `<a href="${escapeHtml(props.map_url)}" target="_blank" rel="noopener noreferrer">Open in Google Maps</a>`
      : "";
    const linkParts = [yt, channel, maps].filter(Boolean);
    return `
      <div class="popup-body">
        <p class="popup-title">${title}</p>
        ${when ? `<p class="popup-time">${when}</p>` : ""}
        <div class="popup-links">${linkParts.join("<br>")}</div>
      </div>`;
  }

  function setCount(n) {
    const el = document.getElementById("incident-count");
    if (el) {
      el.textContent = n === 1 ? "1 incident on map" : `${n} incidents on map`;
    }
  }

  fetch(DATA_URL)
    .then((r) => {
      if (!r.ok) throw new Error(`Failed to load ${DATA_URL} (${r.status})`);
      return r.json();
    })
    .then((geojson) => {
      const features = geojson.features || [];
      setCount(features.length);

      if (features.length === 0) {
        return;
      }

      const layer = L.geoJSON(geojson, {
        pointToLayer: (_feature, latlng) =>
          L.circleMarker(latlng, {
            radius: 8,
            fillColor: "#e53e3e",
            color: "#742a2a",
            weight: 2,
            opacity: 1,
            fillOpacity: 0.85,
          }),
        onEachFeature: (feature, marker) => {
          marker.bindPopup(popupHtml(feature.properties || {}));
        },
      }).addTo(map);

      map.fitBounds(layer.getBounds().pad(0.15));
    })
    .catch((err) => {
      console.error(err);
      setCount(0);
      const el = document.getElementById("incident-count");
      if (el) el.textContent = "Could not load incident data";
    });
})();
