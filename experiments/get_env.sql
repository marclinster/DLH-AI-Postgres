
create database testpy;


CREATE EXTENSION plpython3u;
  
create type py_environ_type as (name text, value text);

create or replace function py_environ(name varchar DEFAULT NULL)
  returns setof py_environ_type
as $$
  import os
  aev = []
  if name is None:
    for k, v in os.environ.items():
      aev.append((k, v))
  else:
    v = os.getenv(name)
    if v is not None:
      aev.append((name,v))
  return aev;
$$ language plpython3u
;

create or replace function py_environ2(name varchar DEFAULT NULL)
  returns TEXT
as $$
  import os
  return os.environ['MISTRAL_API_KEY'];
$$ language plpython3u
;


SELECT py_environ ();

SELECT py_environ2 ();