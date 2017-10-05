#!/bin/sh
psql -U navaid navaid <<EOF
BEGIN;

DELETE
FROM    sess_main
WHERE   updatedate < NOW() - interval '365 day';

COMMIT;
EOF
