-- Reference only. No passwords are embedded here.
-- For automatic existing-volume upgrades, run: docker compose run --build --rm db-setup
-- Below is the equivalent GRANT logic for the demo schema.
-- Run as an administrator and replace role names if changed.
GRANT CONNECT ON DATABASE labdb TO flask_app, report_reader;
GRANT USAGE ON SCHEMA public TO flask_app, report_reader;
GRANT SELECT, INSERT ON TABLE public.visits TO flask_app;
GRANT USAGE ON SEQUENCE public.visits_id_seq TO flask_app;
GRANT SELECT ON TABLE public.visits TO report_reader;
-- Omitted on purpose: UPDATE, DELETE, CREATE, TRUNCATE, superuser privileges.
-- Only existing demo table is granted; future tables require separate review.
