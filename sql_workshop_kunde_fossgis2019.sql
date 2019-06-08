/**********************
 * DATENBANK SETUP
 *********************/

-- Test-DB für den Workshop
CREATE DATABASE fossgis_sql;

-- Neues Schema anlegen und nicht im public-Schema arbeiten
CREATE SCHEMA parken_dd;

-- search_path aktualisieren, damit das Schema nicht immer angegeben werden muss
ALTER DATABASE fossgis_sql SET search_path TO parken_dd, public;

-- Eine Tabelle genügt
CREATE TABLE parken_dd.parkplatz (
  id INTEGER PRIMARY KEY,
  name TEXT,
  count SMALLINT,
  free SMALLINT,
  time TIMESTAMP WITH TIME ZONE
);

-- ParkenDD Datenarchiv runter laden: http://ubahn.draco.uberspace.de/opendata/dump/parken_dump.csv
-- Importieren mit COPY (unter Windows 'C:\<user>\Downloads\parken_dump.csv')
COPY parken_dd.parkplatz FROM '/home/<user>/Downloads/parken_dump.csv'
WITH CSV header DELIMITER ',' ENCODING 'latin1';

-- Prüfen, ob alle Daten eingespielt wurden und ob der search_path funktioniert
-- Bei Fehlermeldung, Verbindung zur Datenbank trennen und neu verbinden
SELECT count(1) FROM parkplatz;
-- Ergebnis: 1535037

-- Kurzer Überblick zu den Daten
SELECT * FROM parkplatz LIMIT 25;
SELECT * FROM parkplatz ORDER BY random() LIMIT 25;
SELECT * FROM parkplatz TABLESAMPLE BERNOULLI(0.01);


/**********************
 * DISTINCT Varianten
 *********************/

-- Welche Parkplätze gibt es?
SELECT DISTINCT name FROM parkplatz;

-- Wie viele Parkplätze gibt es?
SELECT count(DISTINCT name) FROM parkplatz;

-- IS DISTINCT FROM = NULL-safe Vergleich
SELECT 1 = 1;
SELECT 1 != 1;
SELECT 1 = NULL;
SELECT 1 IS DISTINCT FROM NULL;
SELECT 1 IS NOT DISTINCT FROM NULL;
SELECT NULL IS DISTINCT FROM NULL;

-- höchste Belegung pro Tag am Altmarkt
  SELECT date(time),
         min(free) AS auslastung
    FROM parkplatz
   WHERE name = 'Altmarkt'
GROUP BY date(time)
ORDER BY date(time);

-- Zu welcher Uhrzeit war das? Einfach time Spalte hinzufügen klappt nicht. min(time) liefert nicht die richtige Zeit.
  SELECT date(time),
         min(free) AS auslastung, -- wann genau war das?
         time
    FROM parkplatz
   WHERE name = 'Altmarkt'
GROUP BY date(time)
ORDER BY date(time);

-- Wir wollen die erste Zeile pro Gruppe, also Top-1k (hier: pro Tag)
-- Es geht mit Unterabfragen aber mit DISTINCT ON braucht man diese nicht
  SELECT DISTINCT ON (date(time)) -- legt die Gruppe fest (kein Komma)
         date(time), free, time
    FROM parkplatz
   WHERE name = 'Altmarkt'
ORDER BY date(time), free; -- legt den ersten Eintrag pro Gruppe fest


/**********************
 * Top-nk mit LATERAL
 *********************/

-- Für Top-nk ist eine Unterabfrage unabdingbar
-- Was wir wollen ist eine Art FOR EACH Schleife
FOR (suchdatum IN datumsliste) -- Für jedes Datum führe folgende Abfrage aus (das hier ist kein SQL):
  SELECT date(time), free, time
    FROM parkplatz
   WHERE name = 'Altmarkt'
     AND date(time) = <suchdatum>
ORDER BY free
   LIMIT 5;

-- Man könnte aus der Tabelle die distinkten Tage auslesen und dann gegen die Abfrage joinen
-- Aber warum, die Tabelle zwei Mal scannen, wenn es generate_series gibt
SELECT generate_series('2014-04-13', '2015-06-17', '1 day'::interval) AS day;

-- Es wäre cool, generate_series in der WHERE-Klausel einsetzen zu können
-- Das geht leider nicht.
  SELECT date(time), free, time
    FROM parkplatz
   WHERE name = 'Altmarkt'
     AND date(time) = generate_series('2014-04-13', '2015-06-17', '1 day'::interval)
ORDER BY free
   LIMIT 5;

-- Eine korrelierte Unterabfrage geht auch nicht
SELECT g.day, (
       SELECT free, time
         FROM parkplatz
        WHERE name = 'Altmarkt'
          AND date(time) = g.DAY
     ORDER BY free
        LIMIT 5
       )
  FROM generate_series('2014-04-13', '2015-06-17', '1 day'::interval) AS g(day); 

-- FEHLER: Unteranfrage darf nur eine Spalte zurückgeben
-- selbst wenn es nur eine Spalte wäre ...
-- FEHLER: als Ausdruck verwendete Unteranfrage ergab mehr als eine Zeile

-- Dann eben mit einem JOIN, oder?
SELECT g.day, free, time
  FROM generate_series('2014-04-13', '2015-06-17', '1 day'::interval) AS g(day)
  JOIN (
       SELECT free, time
         FROM parkplatz
        WHERE name = 'Altmarkt'
          AND date(time) = g.day
     ORDER BY free
        LIMIT 5
       ) t
    ON g.day = t.date;

-- Hm, geht auch nicht. Die Fehlermeldung besagt:
-- "Hinweis: Es gibt einen Eintrag für Tabelle »g«, aber auf ihn kann aus diesem Teil der Anfrage nicht verwiesen werden."
-- Die Lösung heißt: LATERAL
SELECT g.day, free, time
  FROM generate_series('2014-04-13', '2015-06-17', '1 day'::interval) AS g(day)
  JOIN LATERAL (
       SELECT free, time
         FROM parkplatz
        WHERE name = 'Altmarkt'
          AND date(time) = g.DAY
     ORDER BY free
        LIMIT 5
       ) t
    ON (true);

-- Ab hier dürfte sich der fehlende Index auf der time-Spalte bemerkbar machen
-- (Es sei denn der verwendete SQL-Client holt nicht alle Zeilen)
CREATE INDEX time_idx ON parkplatz (time);

-- Bei diesen Index sollte dann nicht mehr die time-Spalte im WHERE verändert werden
SELECT g.day, free, time
  FROM generate_series('2014-04-13', '2015-06-17', '1 day'::interval) AS g(day)
  JOIN LATERAL (
       SELECT free, time
         FROM parkplatz
        WHERE name = 'Altmarkt'
          AND time BETWEEN g.day AND g.day + INTERVAL '1 day'
     ORDER BY free
        LIMIT 5
       ) t
    ON (true);


/**********************
 * FILTER
 *********************/
  
-- Bisheriges Ergebnis: Höhere Auslastung meistens nachmittags
-- In wie vielen Messungen ist eigentlich kein Parkplatz mehr frei? 
  SELECT name,
         count(CASE WHEN free = 0 THEN 1 ELSE NULL END) AS n_voll,
         count(1) AS n_messungen
    FROM parkplatz
GROUP BY name;

-- Etwas eleganter geht es mit FILTER
  SELECT name,
         count(1) FILTER (WHERE free = 0) AS n_voll,
         count(1) AS n_messungen
    FROM parkplatz
GROUP BY name;


/**********************
 * GROUPING SETS
 *********************/

-- Wie ist das Verhältnis?
  SELECT name,
         (count(1) FILTER (WHERE free = 0) / count(1)::numeric * 100)::int AS belegt_in_prozent
    FROM parkplatz
GROUP BY name
ORDER BY belegt_in_prozent DESC;

-- Wie ist das Verhältnis an den Parkplätzen über das Jahr verteilt?
-- Beim GROUP BY und ORDER BY sind wir jetzt mal schreibfaul und schreiben 1 = Erste Spalte des Ergebnis
  SELECT extract(month from time)::int AS monat,
         (count(1) FILTER (WHERE free = 0) / count(1)::numeric * 100)::int AS belegt_in_prozent
    FROM parkplatz
GROUP BY 1
ORDER BY 1;

-- Können wir beide Ergebnis mit einer Abfrage ermitteln?
  SELECT name, extract(month FROM time)::int AS monat,
         (count(1) FILTER (WHERE free = 0) / count(1)::numeric * 100)::int AS belegt_in_prozent
    FROM parkplatz
GROUP BY 1, 2
ORDER BY 1, 2;

-- Nein, das ist nicht das gleiche wie die beiden Abfragen davor
-- Man könnte die vorherigen Abfragen mit UNION ALL verbinden
SELECT * FROM (
       SELECT name AS kategorie,
              (count(1) FILTER (WHERE free = 0) / count(1)::numeric * 100)::int AS belegt_in_prozent
         FROM parkplatz
     GROUP BY name
     ORDER BY belegt_in_prozent DESC
     ) p
UNION ALL (
       SELECT extract(month from time)::text AS kategorie,
              (count(1) FILTER (WHERE free = 0) / count(1)::numeric * 100)::int AS belegt_in_prozent
         FROM parkplatz
     GROUP BY 1
     ORDER BY 1
);

-- ... oder man verwendet GROUPING SETS
  SELECT name, extract(month from time)::int AS monat,
         (count(1) FILTER (WHERE free = 0) / count(1)::numeric * 100)::int AS belegt_in_prozent
    FROM parkplatz
GROUP BY GROUPING SETS (name, extract(month from time), ()) -- leerer Klammernblock steht für Gesamtwert
ORDER BY name, monat, belegt_in_prozent DESC;

-- Falls man doch noch an einer Kombination aus Monat und Parkplatz interessiert ist, gibt es noch ROLLUP
  SELECT name, extract(month from time)::int AS monat,
         (count(1) FILTER (WHERE free = 0) / count(1)::numeric * 100)::int AS belegt_in_prozent
    FROM parkplatz
GROUP BY ROLLUP (name, extract(month from time))
ORDER BY name, monat, belegt_in_prozent DESC;

-- ROLLUP zeigt auch die Gesamtauslastung an dem Parkplatz, aber nicht pro Monat
-- Die Gruppierung geht hierarchisch nach den Spalten im Klammernblock vor
-- Möchte man alle Kombis, verwendet man CUBE
  SELECT name, extract(month from time)::int AS monat,
         (count(1) FILTER (WHERE free = 0) / count(1)::numeric * 100)::int AS belegt_in_prozent
    FROM parkplatz
GROUP BY CUBE (name, extract(month from time))
ORDER BY name, monat, belegt_in_prozent DESC;


/**********************
 * BOOL_OR & BOOL_AND
 *********************/

-- Gibt es Zeiten zu denen alle Plätze in der Altstadt belegt sind?
-- bool_or = min. 1 ist belegt, bool_and = alle belegt
  SELECT time, bool_or(free = 0), bool_and(free = 0)
    FROM parkplatz
   WHERE name IN (
         'Altmarkt', 'Altmarkt - Galerie', 'An der Frauenkirche', 'Frauenkirche Neumarkt',
         'Haus am Zwinger', 'Pirnaischer Platz', 'Schießgasse', 'Taschenbergpalais', 'Terrassenufer'
         )
GROUP BY time;

-- Gefilterte Ausgabe
  SELECT time
    FROM (
         SELECT time, bool_and(free = 0)
           FROM parkplatz
          WHERE name IN (
                'Altmarkt', 'Altmarkt - Galerie', 'An der Frauenkirche', 'Frauenkirche Neumarkt',
                'Haus am Zwinger', 'Pirnaischer Platz', 'Schießgasse', 'Taschenbergpalais', 'Terrassenufer'
                )
       GROUP BY time
         ) t
   WHERE bool_and
ORDER BY time;

-- Am 05.02. ist 2014 und 2015 alles belegt. Was ist mit den restlichen Parkplätzen?
SELECT * FROM parkplatz WHERE time = '2014-05-02 13:00:04';


/**********************
 * WINDOW FUNCTIONS
 *********************/

-- Ziel: Jede Zeile mit dem Gesamtdurchschnitt aller Parkplätze vergleichen
-- Variante mit Common Table Expression (CTE)
WITH avg_total AS (
  SELECT avg(free)::int
    FROM parkplatz
)
SELECT name, time, free, avg
  FROM parkplatz, avg_total;

-- Window Function Variante mit kompletten Fenster OVER ()
SELECT name, time, free, 
       avg(free) OVER ()::int
  FROM parkplatz;

-- Vergleich zu Gesamtdurchschnitt an einem Parkplatz
-- Wieder CTE-Variante
WITH avg_total AS (
  SELECT name AS pp_name, avg(free)::int
    FROM parkplatz
GROUP BY name
)
SELECT name, time, free, avg
  FROM parkplatz, avg_total
 WHERE name = pp_name;

-- Window Function Variante mit partitioniertem Fenster OVER (PARTITION BY ...)
SELECT name, time, free, 
       avg(free) OVER (PARTITION BY name)::int
  FROM parkplatz;

-- Idee: Vorhersage von freien Parkplätzen
-- Algorithmus erwartet pro Parkplatz Messwerte der letzten zwei Stunden geglättet mit gleitendem Durchschnitt pro 15 Minuten
-- Vergleich zu Durchschnitt an einem Parkplatz der letzten 2 Stunden
SELECT name, avg(free) OVER (PARTITION BY name)::int
  FROM parkplatz
 WHERE time >= '2015-06-17 18:15:09+02'::timestamptz - interval '2 hours';

-- Ergibt (im Idealfall) 24 Messungen pro Parkplatz
-- Aber: Durchschnitt wurde nur für das 2-Stunden-Fenster bestimmt
-- Jede Zeile soll Durchschnitt der vorangegangen 15 Min. enthalten
-- Fenster muss einserseits sortiert werden: OVER (... ORDER BY ...)
-- Eingrenzung auf 3 Vorgängerwerte mit einer Frame Clause 
SELECT name, time, avg(free) OVER (PARTITION BY name ORDER BY time)::int
  FROM parkplatz
 WHERE time >= '2015-06-17 18:15:09+02'::timestamptz - interval '2 hours';

-- Mit ORDER BY wird schon ein Framing aktiviert -> Durchschnitt aller Vorgängerzeilen bis zur CURRENT ROW
SELECT name, time,
       avg(free) OVER (
         PARTITION BY name ORDER BY time
         RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       )::int
  FROM parkplatz
 WHERE time >= '2015-06-17 18:15:09+02'::timestamptz - interval '2 hours';

-- Wir grenzen das Frame nun auf drei Vorgängermesswerte ein
SELECT name, time,
       avg(free) OVER (
         PARTITION BY name ORDER BY time
         ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
       )::int
  FROM parkplatz
 WHERE time >= '2015-06-17 18:15:09+02'::timestamptz - interval '2 hours';

-- Es können auch die nachfolgenden Zeilen berücksichtigt werden
-- z.B. gleitender Durchschnitt 10 Minuten vor und danach ohne Wert in der Mitte (letzteres seit PostgreSQL 11)
SELECT name, time,
       avg(free) OVER (
         PARTITION BY name
         ORDER BY time
         ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
         EXCLUDE CURRENT ROW
       )::int
  FROM parkplatz
 WHERE time >= '2015-06-17 18:15:09+02'::timestamptz - interval '2 hours';

-- Mit ROWS werden nicht zwangläufig die letzten 15 Minuten gewählt
-- Wenn es Lücken in den Messungen gibt, dann werden auch ältere Zeitpunkte berücksichtigt
-- Die Frame Clause kann seit PostgreSQL 11 auch zeitliche Intervalle berücksichten
SELECT name, time,
       avg(free) OVER (
         PARTITION BY name
         ORDER BY time
         RANGE BETWEEN interval '15 minutes' PRECEDING
                   AND CURRENT ROW
       )::int
  FROM parkplatz
WHERE time >= '2015-06-17 18:15:09+02'::timestamptz - interval '2 hours';

-- Prüfen wir mal, ob RANGE funktioniert. Mit der first_value Funktion kann der erste Wert des Fenster bestimmt werden
-- Wenn das gleiche Fenster zwei Mal eingesetzt wird, macht es Sinn, die WINDOW Syntax zu verwenden
SELECT name, time, FREE,
       first_value(free) OVER w,
       avg(free) OVER w::int
  FROM parkplatz
 WHERE time >= '2015-06-17 18:15:09+02'::timestamptz -
       interval '2 hours'
WINDOW w AS (
         PARTITION BY name ORDER BY time
         RANGE BETWEEN interval '15 minutes' PRECEDING
                   AND CURRENT ROW
       );

-- Es gibt einige weitere interessante Window Functions, z.B. lag und lead
-- Damit kann man eine Zeile mit einer anderen nachfolgenden oder vorangegangenen Spalte vergleichen
SELECT name, time, free,
       lag(free, 1) OVER w,
       lead(free, 1) OVER w
  FROM parkplatz
WINDOW w AS (
          PARTITION BY name ORDER BY time
        )
 LIMIT 100;

-- Mit row_number() können Zeilen gezählt werden
-- rank() vergibt eine Rangfolge (sinnvoll für nachfolgende ORDER BYs)
-- dense_rank() ist wie rank() ohne Lücken im Zähler
SELECT name, time, free,
       row_number() OVER w,
       rank() OVER w,
       dense_rank() OVER w
  FROM parkplatz
WINDOW w AS (
          ORDER BY time
        )
 LIMIT 100;


/**********************
 * Sonstiges
 *********************/

-- array_agg → unnest(arr) WITH ORDINALITY
WITH create_array AS (
  SELECT array_agg(g.fossgis_tag) AS arr
    FROM generate_series('2019-03-13', '2019-03-16', '1 day'::interval) AS g(fossgis_tag)
)
SELECT ordering, fossgis_tag
  FROM create_array,
       unnest(arr) WITH ORDINALITY a(fossgis_tag, ordering);

-- Inlined CTEs ab Postgres 12 ([NOT] MATERIALIZED)     
WITH create_array MATERIALIZED AS (
  SELECT array_agg(g.fossgis_tag) AS arr
    FROM generate_series('2019-03-13', '2019-03-16', '1 day'::interval) AS g(fossgis_tag)
)
SELECT ordering, fossgis_tag
  FROM create_array,
       unnest(arr) WITH ORDINALITY a(fossgis_tag, ordering);

-- Schleifen mit generate_series Funktion, z.B. bei ST_PointN (erfordert PostGIS Extension)
SELECT ST_PointN(
         'LINESTRING(1 1,2 2,3 3,4 4,5 5)'::geometry,
         generate_series(1, ST_NumPoints('LINESTRING(1 1,2 2,3 3,4 4,5 5)'::geometry))
       );

-- Rekursive Schleifen mit WITH RECURSIVE (Graph Query)
WITH RECURSIVE points AS (
  SELECT ST_PointN(
           'LINESTRING(1 1,2 2,3 3,4 4,5 5)'::geometry,
           generate_series(1, ST_NumPoints('LINESTRING(1 1,2 2,3 3,4 4,5 5)'::geometry))
         ) AS pt_geom
), line_segments AS (
  SELECT row_number() OVER () AS lid,
         ST_MakeLine(pt_geom, lead(pt_geom, 1) OVER ()) AS line_geom
    FROM points
), line_iterator (lids, hook, traversals) AS (
  SELECT ARRAY[lid] AS lids,
         ST_EndPoint(line_geom) AS hook,
         1 AS traversals
    FROM line_segments
   WHERE ST_Intersects(line_geom, 'POINT(1 1)'::geometry)
  UNION ALL
    SELECT i.lids || l.lid AS lids,
           ST_EndPoint(l.line_geom) AS hook,
           i.traversals + 1 AS traversals
      FROM line_segments l
      JOIN line_iterator i
        ON ST_Intersects(i.hook, ST_StartPoint(l.line_geom))
     WHERE NOT (l.lid = ANY (i.lids))
)
SELECT * FROM line_iterator;

-- Das ganze jetzt nochmal mit einer Abschlussquery, welche die Segmente zusammenfügt
WITH RECURSIVE points AS (
  SELECT ST_PointN(
           'LINESTRING(1 1,2 2,3 3,4 4,5 5)'::geometry,
           generate_series(1, ST_NumPoints('LINESTRING(1 1,2 2,3 3,4 4,5 5)'::geometry))
         ) AS pt_geom
), line_segments AS (
  SELECT row_number() OVER () AS lid,
         ST_MakeLine(pt_geom, lead(pt_geom, 1) OVER ()) AS line_geom
    FROM points
), line_iterator (lids, hook, traversals) AS (
  SELECT ARRAY[lid] AS lids,
         ST_EndPoint(line_geom) AS hook,
         1 AS traversals
    FROM line_segments
   WHERE ST_Intersects(line_geom, 'POINT(1 1)'::geometry)
  UNION ALL
    SELECT i.lids || l.lid AS lids,
           ST_EndPoint(l.line_geom) AS hook,
           i.traversals + 1 AS traversals
      FROM line_segments l
      JOIN line_iterator i
        ON ST_Intersects(i.hook, ST_StartPoint(l.line_geom))
     WHERE NOT (l.lid = ANY (i.lids))
)
SELECT
  ST_LineMerge(ST_Collect(l.line_geom ORDER BY t.lid_order)) AS geom
FROM (
  -- nur die Zeilen von line_iterator wählen, die mit dem letzten Punkt der Eingabegeometrie übereinstimmen
  -- die lids Arrays geben vor, welche Linie zu einer Route aggregiert werden müssen
  SELECT
    row_number() OVER () AS agg_lid,
    lids
  FROM
    line_iterator
  WHERE 
    _ST_DWithin('POINT(5 5)'::geometry, hook, 0.001)
  ) a,
  LATERAL unnest(a.lids) WITH ORDINALITY AS t(lid, lid_order),
  line_segments l
WHERE
  l.lid = t.lid
GROUP BY
  a.agg_lid;

-- Median mit PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ...)
SELECT name, avg(free), percentile_cont(0.50) WITHIN GROUP (ORDER BY free)
  FROM parkplatz
GROUP BY name;

-- IF Abfrage1 = 0 rows THEN Abfrage2 → UNION ALL
SELECT time
  FROM parkplatz
 WHERE time >= '2013-01-01 00:00:00' AND time < '2014-01-01 00:00:00'
UNION ALL
SELECT time
  FROM parkplatz
 WHERE time >= '2014-01-01 00:00:00' AND time < '2015-01-01 00:00:00';

-- Session Variablen: set_config und current_setting
SELECT set_config('parken_dd.temp_variable', 'Danke für die Teilname', FALSE); -- mit TRUE gilt es nur während der Transaktion
SELECT current_setting('parken_dd.temp_variable');
