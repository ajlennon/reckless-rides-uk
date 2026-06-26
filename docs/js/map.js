(function () {
  const DATA_URL = "data/incidents.geojson";
  const YOUTUBE_CHANNEL_URL = "https://www.youtube.com/@Reckless-Rides-UK";
  const UK_CENTER = [54.5, -3.5];
  const UK_ZOOM = 6;

  const PERIODS = {
    all: { label: "All", days: null },
    "7d": { label: "7 days", days: 7 },
    "30d": { label: "30 days", days: 30 },
    "365d": { label: "1 year", days: 365 },
  };
  const DEFAULT_PERIOD = "30d";

  let allFeatures = [];
  let clusterLayer = null;
  let map = null;

  function escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  function parsePeriodFromUrl() {
    const p = new URLSearchParams(window.location.search).get("period");
    return p && PERIODS[p] ? p : null;
  }

  function getActivePeriod() {
    return parsePeriodFromUrl() || sessionStorage.getItem("rruk-period") || DEFAULT_PERIOD;
  }

  function setActivePeriod(period) {
    sessionStorage.setItem("rruk-period", period);
    const url = new URL(window.location.href);
    if (period === DEFAULT_PERIOD) {
      url.searchParams.delete("period");
    } else {
      url.searchParams.set("period", period);
    }
    history.replaceState({}, "", url);
    document.querySelectorAll("[data-period]").forEach((btn) => {
      const active = btn.getAttribute("data-period") === period;
      btn.classList.toggle("active", active);
      btn.setAttribute("aria-pressed", active ? "true" : "false");
    });
  }

  function featureRecordedMs(feature) {
    const raw = feature.properties?.recorded_utc || "";
    const ms = Date.parse(raw);
    return Number.isFinite(ms) ? ms : 0;
  }

  function filterFeatures(periodKey) {
    const cfg = PERIODS[periodKey];
    if (!cfg || cfg.days === null) {
      return allFeatures.slice();
    }
    const cutoff = Date.now() - cfg.days * 24 * 60 * 60 * 1000;
    return allFeatures.filter((f) => featureRecordedMs(f) >= cutoff);
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

  function updateCount(shown, total, periodKey) {
    const el = document.getElementById("incident-count");
    if (!el) return;
    const label = PERIODS[periodKey]?.label || periodKey;
    if (total === 0) {
      el.textContent = "No public incidents on map yet";
      return;
    }
    if (shown === total) {
      el.textContent =
        total === 1 ? `1 incident · ${label}` : `${total} incidents · ${label}`;
    } else {
      el.textContent = `${shown} of ${total} incidents · ${label}`;
    }
  }

  function renderList(features) {
    const list = document.getElementById("incident-list");
    if (!list) return;
    if (features.length === 0) {
      list.innerHTML = "<p class=\"list-empty\">No incidents in this period.</p>";
      return;
    }
    const sorted = features.slice().sort((a, b) => featureRecordedMs(b) - featureRecordedMs(a));
    list.innerHTML = sorted
      .map((f) => {
        const p = f.properties || {};
        const when = escapeHtml(p.recorded_bst || p.recorded_utc || "");
        const title = escapeHtml(p.title || "Incident");
        const yt = p.youtube_url
          ? `<a href="${escapeHtml(p.youtube_url)}" target="_blank" rel="noopener noreferrer">Watch on YouTube</a>`
          : "";
        return `<li class="incident-item">
          <span class="incident-when">${when}</span>
          <span class="incident-title">${title}</span>
          ${yt}
        </li>`;
      })
      .join("");
  }

  function renderMap(features) {
    if (clusterLayer) {
      map.removeLayer(clusterLayer);
      clusterLayer = null;
    }
    if (features.length === 0) {
      map.setView(UK_CENTER, UK_ZOOM);
      return;
    }
    clusterLayer = L.markerClusterGroup({
      showCoverageOnHover: false,
      maxClusterRadius: 50,
      spiderfyOnMaxZoom: true,
    });
    L.geoJSON(
      { type: "FeatureCollection", features },
      {
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
      }
    ).eachLayer((layer) => clusterLayer.addLayer(layer));
    map.addLayer(clusterLayer);

    const bounds = clusterLayer.getBounds();
    if (bounds.isValid()) {
      const ne = bounds.getNorthEast();
      const sw = bounds.getSouthWest();
      const latSpan = Math.abs(ne.lat - sw.lat);
      const lonSpan = Math.abs(ne.lng - sw.lng);
      if (latSpan < 0.5 && lonSpan < 0.5) {
        map.fitBounds(bounds.pad(0.12));
      } else {
        map.setView(UK_CENTER, UK_ZOOM);
      }
    }
  }

  function applyPeriod(periodKey) {
    setActivePeriod(periodKey);
    const filtered = filterFeatures(periodKey);
    updateCount(filtered.length, allFeatures.length, periodKey);
    renderMap(filtered);
    renderList(filtered);
  }

  function initFilters() {
    document.querySelectorAll("[data-period]").forEach((btn) => {
      btn.addEventListener("click", () => {
        applyPeriod(btn.getAttribute("data-period"));
      });
    });
  }

  map = L.map("map", { scrollWheelZoom: true }).setView(UK_CENTER, UK_ZOOM);
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(map);

  initFilters();

  fetch(DATA_URL)
    .then((r) => {
      if (!r.ok) throw new Error(`Failed to load ${DATA_URL} (${r.status})`);
      return r.json();
    })
    .then((geojson) => {
      allFeatures = geojson.features || [];
      applyPeriod(getActivePeriod());
    })
    .catch((err) => {
      console.error(err);
      const el = document.getElementById("incident-count");
      if (el) el.textContent = "Could not load incident data";
      renderList([]);
    });
})();
