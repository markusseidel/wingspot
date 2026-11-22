# KML test files

Every file here is **made up**. The flights, airlines, aircraft types and registrations are invented, and the files were
written by hand from the structure described in issue #236 to #239. None is a copy of a file from any flight-tracking
service. **Do not add a real export to this folder**: the repository is public, so a committed file is republished to
everyone (see "FR24 terms of service" in [docs/KML-IMPORT-PLAN.md](../../../docs/KML-IMPORT-PLAN.md)).

What the parser must find in each file is in [`../kml-flights.json`](../kml-flights.json). Both apps read it:
`KmlFlightTests` on iOS (WingspotCore) and on Android (core).

| File | What it tests |
|---|---|
| `new-template.kml` | The newer description layout (airport links, `<h3>` IATA, city, ATD and ETA), a CDATA description, a one-point placemark next to the line |
| `old-template.kml` | The older layout ("From:", "To:", "Departure:"), an entity-escaped description, a straight two-point line next to the real track |
| `date-line.kml` | A track across the 180° meridian, with raw longitudes kept |
| `placemarks-only.kml` | No line: the track comes from single position reports, given out of order, and the route from the title |
| `only-a-straight-line.kml` | Only a two-point line: no track, but the file is still a KML |
| `not-a-kml.txt` | Not a KML: an error |
