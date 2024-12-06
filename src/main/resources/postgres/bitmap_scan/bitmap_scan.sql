DROP TABLE IF EXISTS movies;
create table movies(name text, release_date date, genre text, rating float, director text);

insert into movies select
    substr(md5(random()::text), 1, 5),
    current_date - (random() * interval '40 years'),
    case when random() < 0.5 then 'comedy' else 'action' end,
    random() * random() * 10,
    substr(md5(random()::text), 1, 4) from generate_series(1, 1000000);

create index on movies(release_date ASC) include (name);
create index on movies(rating ASC) include (name);
create index on movies(director, genre) include (name);

-- list highest rated movies
select name from movies where rating > 9.9;

-- list highest rated movies in june
select name from movies where (release_date between date 'june 1, 2024' and date 'june 30, 2024') and rating > 9;

-- highest rated movies in june or highly rated movies
select name from movies where (rating > 9 and release_date between date 'june 1, 2024' and date 'june 30, 2024') or rating > 9.9;


-- turn off the bitmap scap
SET enable_bitmapscan = off;

-- check the explain output and see how much it has improved on the perf

