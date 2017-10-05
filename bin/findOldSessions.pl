#!/bin/sh
mysql -u navaid navaid <<EOF
SELECT      *
FROM        sess_main
WHERE       updatedate < date_sub(CURRENT_DATE, interval '365' day);

SELECT      sp.*
FROM	    sess_province sp
LEFT JOIN   sess_main sm
ON          sp.session_id = sm.session_id
WHERE       sm.session_id IS NULL;

SELECT      ss.*
FROM	    sess_state ss
LEFT JOIN   sess_main sm
ON          ss.session_id = sm.session_id
WHERE       sm.session_id IS NULL;

SELECT      st.*
FROM	    sess_type st
LEFT JOIN   sess_main sm
ON          st.session_id = sm.session_id
WHERE       sm.session_id IS NULL;

EOF
