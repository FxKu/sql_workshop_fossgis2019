# Advanced SQL Workshop FOSSGIS 2019

In this workshop you will analyze time series data about free parking places with some advanced SQL recipes.
It covers the following SQL features:

* [DISTINCT ON](https://medium.com/statuscode/the-many-faces-of-distinct-in-postgresql-c52490de5954)
* [IS DISTINCT FROM](https://wiki.postgresql.org/wiki/Is_distinct_from)
* [LATERAL JOIN](https://carto.com/blog/lateral-joins/)
* [FILTER](https://modern-sql.com/feature/filter)
* [GROUPING SETS/ROLLUP/CUBE](https://www.postgresql.org/docs/11/queries-table-expressions.html#QUERIES-GROUPING-SETS)
* [BOOL_OR/BOOL_AND](https://www.postgresonline.com/journal/archives/241-True-or-False-every-which-way.html)
* [WINDOW Functions](https://momjian.us/main/writings/pgsql/window.pdf)

## Background

This workshop has been held at the [FOSSGIS](https://pretalx.com/fossgis2019/talk/VKEUPL/)
conference 2019 in Dresden. The initial idea was to present some advanced geo queries that can be done
with [PostGIS](https://postgis.net/). But judging from my own experience I realized that it weren't the
hundreds of PostGIS' functions that lifted my spatial SQL skills to another level. It was SQL itself.
It took me a while to fully understand more advanced concepts such as window functions. You certainly
don't need them everywhere. But the more options you know the faster you will solve complex tasks with SQL.

I decided to leave out geomerty-related queries. So that the participants can better focus on SQL itself.
I prepared some examples, nevertheless, but only as an encore (to be found in the [SQL file](sql_workshop_kunde_fossgis2019.sql)). I believe that most of the PostGIS users know the basic tricks anyway.
Spatial JOINs, GiST indexes, kNN-queries with `<->`, ST_Dump, ST_MakeValid ect. I hope that after this
workshop they will be able to combine it with [modern SQL](https://modern-sql.com/) to create new exciting
forms of data analysis. It doesn't have to be R or Python all the time when it comes to DataScience.

## Data

Data is provided by the Open Data initiative [ParkenDD](https://parkendd.de/) in Dresden. A data dump can be downloaded [here](http://ubahn.draco.uberspace.de/opendata/dump/parken_dump.csv).

## Prerequisites

PostgreSQL min. v9.6, better 11. PostGIS extension is not a must (only for the mentioned encore queries)

## How to start

I have uploaded the original workshop material, but it contains german comments.
For the english version, I tried something else: a SQL notebook.
I found that this can be done with [franchise](https://franchise.cloud/).

1. Simply download franchise and open the provided [HTML file](sql_notebook_fossgis2019.html)
2. Create a Postgres database and connect to it from franchise
3. The DB setup and data import is explained in the notebook
