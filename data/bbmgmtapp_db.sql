--
-- PostgreSQL database dump
--

-- Dumped from database version 15.2 (Debian 15.2-1.pgdg110+1)
-- Dumped by pg_dump version 15.2 (Debian 15.2-1.pgdg110+1)

-- Started on 2023-03-19 20:19:39 UTC

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 255 (class 1255 OID 16927)
-- Name: add_guest_created_date(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_guest_created_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
    UPDATE guests 
	SET guest_created_date = now()
	WHERE guest_id = NEW.guest_id;
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.add_guest_created_date() OWNER TO postgres;

--
-- TOC entry 254 (class 1255 OID 16565)
-- Name: add_guest_stay_transaction(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_guest_stay_transaction() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN
	WITH room_amenity_totals AS(
				SELECT r.room_number, SUM(amenity_premium) AS amenities_total
				FROM rooms_amenities ra
				JOIN rooms r ON r.room_number = ra.room_number
				JOIN amenities a ON a.amenity_id = ra.amenity_id
				GROUP BY r.room_number
	)
	INSERT INTO guest_transactions (transaction_type_id, 
							    guest_id, 
							    guest_transaction_charge,
							    guest_transaction_payment,
							    guest_transaction_date,
								guest_transaction_description
	)	
	SELECT (
			SELECT transaction_type_id
			FROM transaction_types
			WHERE transaction_type_description = 'Room nightly rate'
			) AS transaction_type_id, 
			s.stay_holder_guest_id,
			CASE		
				WHEN rate_premium = 0 AND rate_discount = 0 THEN (room_type_base_rate + rat.amenities_total) * stay_duration
				WHEN rate_premium = 0 THEN ((room_type_base_rate + rat.amenities_total) * rate_discount) * stay_duration
				WHEN rate_discount = 0 THEN ((room_type_base_rate + rat.amenities_total) * rate_premium) * stay_duration
			END AS total_duration_rate,
			0,
			NOW(),
			'Room for '|| NEW.stay_duration||' nights'
	FROM stays s
	JOIN rooms r ON r.room_number = s.room_number
	JOIN room_types rt ON rt.room_type_id = r.room_type_id
	JOIN room_type_rates rtr ON rtr.room_type_id = rt.room_type_id
	JOIN rate_schedules rs ON rs.rate_schedule_id = rtr.rate_schedule_id
	JOIN room_amenity_totals rat ON rat.room_number = r.room_number
	WHERE s.stay_id IN (NEW.stay_id)
	AND rs.rate_schedule_id IN (
		SELECT rate_schedule_id
		FROM rate_schedules 
		WHERE rate_start_date <= s.stay_check_in
	    AND rate_end_date >= s.stay_check_out
		)
	AND s.stay_status = 'FUTURE';	
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.add_guest_stay_transaction() OWNER TO postgres;

--
-- TOC entry 238 (class 1255 OID 16561)
-- Name: add_guests_stays(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_guests_stays() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
    INSERT INTO guests_stays (guest_id, stay_id, guest_stay_active)
    VALUES (NEW.stay_holder_guest_id, NEW.stay_id, false);
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.add_guests_stays() OWNER TO postgres;

--
-- TOC entry 236 (class 1255 OID 16563)
-- Name: add_stay_balances(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_stay_balances() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
    INSERT INTO stay_balances (stay_total_charges, 
							   stay_total_payments, 
							   stay_balance,
							   stay_id) 
    VALUES (0, 0, 0, NEW.stay_id);
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.add_stay_balances() OWNER TO postgres;

--
-- TOC entry 256 (class 1255 OID 16931)
-- Name: add_stay_created_date(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_stay_created_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
    UPDATE stays 
	SET stay_created_date = now()
	WHERE stay_id = NEW.stay_id;
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.add_stay_created_date() OWNER TO postgres;

--
-- TOC entry 252 (class 1255 OID 16569)
-- Name: add_transaction_to_balances(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_transaction_to_balances() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
	WITH stay_balances_coalesce AS(
		SELECT COALESCE (
		(SELECT sb.stay_balance_id
		FROM stay_balances sb
		JOIN stays s ON s.stay_id = sb.stay_id
		WHERE s.stay_holder_guest_id = NEW.guest_id
		AND s.stay_status IN ('CURRENT')), 		
		(SELECT sb.stay_balance_id
		FROM stay_balances sb
		JOIN stays s ON s.stay_id = sb.stay_id
		WHERE s.stay_holder_guest_id = NEW.guest_id
		AND s.stay_status IN ('FUTURE'))) AS stay_balance_id	
	), guest_transaction_new AS (
		SELECT guest_transaction_id
		FROM guest_transactions
		WHERE guest_transaction_id = NEW.guest_transaction_id
	)
	INSERT INTO transactions_to_balances (guest_transaction_id, stay_balance_id) 
	SELECT gtn.guest_transaction_id, sbc.stay_balance_id AS stay_balance_id
	FROM stay_balances_coalesce sbc, guest_transaction_new gtn;
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.add_transaction_to_balances() OWNER TO postgres;

--
-- TOC entry 251 (class 1255 OID 16572)
-- Name: update_stay_balances_total(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_stay_balances_total() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
	WITH totals AS (
		SELECT SUM(gt.guest_transaction_charge) AS stay_total_charges
				,SUM(gt.guest_transaction_payment) AS stay_total_payments
		FROM guest_transactions gt
		JOIN transactions_to_balances ttb ON gt.guest_transaction_id = ttb.guest_transaction_id
		WHERE ttb.stay_balance_id = NEW.stay_balance_id
		AND gt.guest_transaction_deleted IS NULL
		GROUP BY gt.guest_transaction_charge, gt.guest_transaction_payment
	)
	UPDATE stay_balances 
	SET stay_total_charges = totals.stay_total_charges
		,stay_total_payments = totals.stay_total_payments
		,stay_balance = (totals.stay_total_charges - totals.stay_total_payments)
	FROM totals
	WHERE stay_balance_id = NEW.stay_balance_id;	 
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.update_stay_balances_total() OWNER TO postgres;

--
-- TOC entry 253 (class 1255 OID 16919)
-- Name: update_stays_cancel_date(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_stays_cancel_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
	UPDATE stays
	SET stay_status = 'CANCELLED'
	WHERE stay_id = NEW.stay_id;
	
	UPDATE guests_stays
	SET guest_stay_active = false
	WHERE stay_id = NEW.stay_id;
	
	UPDATE stay_balances
	SET stay_total_charges = 0,
	    stay_total_payments = 0,
		stay_balance = 0
	WHERE stay_id = NEW.stay_id;
	
	UPDATE guest_transactions 
	SET guest_transaction_deleted = now()
	WHERE guest_transaction_id in (
		SELECT gt.guest_transaction_id 
		FROM guest_transactions gt 
		JOIN transactions_to_balances ttb 
		ON gt.guest_transaction_id = ttb.guest_transaction_id 
		JOIN stay_balances sb
		ON ttb.stay_balance_id = sb.stay_balance_id
		WHERE sb.stay_id = NEW.stay_id
	);
	
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.update_stays_cancel_date() OWNER TO postgres;

--
-- TOC entry 250 (class 1255 OID 16574)
-- Name: update_stays_check_in_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_stays_check_in_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
	UPDATE stays
	SET stay_status = 'CURRENT'
	WHERE stay_id = NEW.stay_id;
	
	UPDATE guests_stays
	SET guest_stay_active = true
	WHERE stay_id = NEW.stay_id;
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.update_stays_check_in_status() OWNER TO postgres;

--
-- TOC entry 237 (class 1255 OID 16576)
-- Name: update_stays_check_out_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_stays_check_out_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
	UPDATE stays
	SET stay_status = 'PAST'
	WHERE stay_id = NEW.stay_id;
	
	UPDATE guests_stays
	SET guest_stay_active = false
	WHERE stay_id = NEW.stay_id;
RETURN NEW; 
END; 
$$;


ALTER FUNCTION public.update_stays_check_out_status() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 214 (class 1259 OID 16389)
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);


ALTER TABLE public.alembic_version OWNER TO postgres;

--
-- TOC entry 216 (class 1259 OID 16746)
-- Name: amenities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.amenities (
    amenity_id integer NOT NULL,
    amenity_description text NOT NULL,
    amenity_premium numeric NOT NULL,
    amenity_deleted timestamp without time zone,
    amenity_deleted_note text
);


ALTER TABLE public.amenities OWNER TO postgres;

--
-- TOC entry 215 (class 1259 OID 16745)
-- Name: amenities_amenity_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.amenities_amenity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.amenities_amenity_id_seq OWNER TO postgres;

--
-- TOC entry 3476 (class 0 OID 0)
-- Dependencies: 215
-- Name: amenities_amenity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.amenities_amenity_id_seq OWNED BY public.amenities.amenity_id;


--
-- TOC entry 226 (class 1259 OID 16793)
-- Name: guest_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.guest_transactions (
    guest_transaction_id integer NOT NULL,
    transaction_type_id integer NOT NULL,
    guest_id integer NOT NULL,
    guest_transaction_charge numeric NOT NULL,
    guest_transaction_payment numeric NOT NULL,
    guest_transaction_date timestamp without time zone NOT NULL,
    guest_transaction_deleted timestamp without time zone,
    guest_transaction_description text NOT NULL
);


ALTER TABLE public.guest_transactions OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16792)
-- Name: guest_transactions_guest_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.guest_transactions_guest_transaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.guest_transactions_guest_transaction_id_seq OWNER TO postgres;

--
-- TOC entry 3477 (class 0 OID 0)
-- Dependencies: 225
-- Name: guest_transactions_guest_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.guest_transactions_guest_transaction_id_seq OWNED BY public.guest_transactions.guest_transaction_id;


--
-- TOC entry 218 (class 1259 OID 16755)
-- Name: guests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.guests (
    guest_id integer NOT NULL,
    guest_first_name text NOT NULL,
    guest_middle_initial character varying(1),
    guest_last_name text NOT NULL,
    guest_phone_number text NOT NULL,
    guest_email text,
    guest_state character varying(2),
    guest_birthdate date NOT NULL,
    guest_created_date timestamp without time zone,
    guest_last_updated timestamp without time zone DEFAULT now()
);


ALTER TABLE public.guests OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 16754)
-- Name: guests_guest_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.guests_guest_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.guests_guest_id_seq OWNER TO postgres;

--
-- TOC entry 3478 (class 0 OID 0)
-- Dependencies: 217
-- Name: guests_guest_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.guests_guest_id_seq OWNED BY public.guests.guest_id;


--
-- TOC entry 232 (class 1259 OID 16867)
-- Name: guests_stays; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.guests_stays (
    guest_id integer NOT NULL,
    stay_id integer NOT NULL,
    guest_stay_active boolean NOT NULL
);


ALTER TABLE public.guests_stays OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 16764)
-- Name: rate_schedules; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rate_schedules (
    rate_schedule_id integer NOT NULL,
    rate_start_date timestamp without time zone,
    rate_end_date timestamp without time zone,
    rate_discount numeric,
    rate_premium numeric
);


ALTER TABLE public.rate_schedules OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 16763)
-- Name: rate_schedules_rate_schedule_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.rate_schedules_rate_schedule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.rate_schedules_rate_schedule_id_seq OWNER TO postgres;

--
-- TOC entry 3479 (class 0 OID 0)
-- Dependencies: 219
-- Name: rate_schedules_rate_schedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.rate_schedules_rate_schedule_id_seq OWNED BY public.rate_schedules.rate_schedule_id;


--
-- TOC entry 227 (class 1259 OID 16811)
-- Name: room_type_rates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.room_type_rates (
    room_type_id integer NOT NULL,
    rate_schedule_id integer NOT NULL
);


ALTER TABLE public.room_type_rates OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 16773)
-- Name: room_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.room_types (
    room_type_id integer NOT NULL,
    room_type_bed_type text NOT NULL,
    room_type_bed_count integer NOT NULL,
    room_type_max_occupants integer NOT NULL,
    room_type_base_rate numeric NOT NULL
);


ALTER TABLE public.room_types OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16772)
-- Name: room_types_room_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.room_types_room_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.room_types_room_type_id_seq OWNER TO postgres;

--
-- TOC entry 3480 (class 0 OID 0)
-- Dependencies: 221
-- Name: room_types_room_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.room_types_room_type_id_seq OWNED BY public.room_types.room_type_id;


--
-- TOC entry 228 (class 1259 OID 16826)
-- Name: rooms; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rooms (
    room_number text NOT NULL,
    room_ready boolean NOT NULL,
    room_available timestamp without time zone,
    room_type_id integer NOT NULL,
    room_fits_crib boolean NOT NULL,
    room_deleted timestamp without time zone,
    room_deleted_note text
);


ALTER TABLE public.rooms OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 16838)
-- Name: rooms_amenities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rooms_amenities (
    room_number text NOT NULL,
    amenity_id integer NOT NULL
);


ALTER TABLE public.rooms_amenities OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 16883)
-- Name: stay_balances; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stay_balances (
    stay_balance_id integer NOT NULL,
    stay_total_charges numeric NOT NULL,
    stay_total_payments numeric NOT NULL,
    stay_balance numeric NOT NULL,
    stay_id integer NOT NULL
);


ALTER TABLE public.stay_balances OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 16882)
-- Name: stay_balances_stay_balance_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.stay_balances_stay_balance_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.stay_balances_stay_balance_id_seq OWNER TO postgres;

--
-- TOC entry 3481 (class 0 OID 0)
-- Dependencies: 233
-- Name: stay_balances_stay_balance_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stay_balances_stay_balance_id_seq OWNED BY public.stay_balances.stay_balance_id;


--
-- TOC entry 231 (class 1259 OID 16854)
-- Name: stays; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stays (
    stay_id integer NOT NULL,
    room_number text NOT NULL,
    stay_holder_guest_id integer NOT NULL,
    stay_check_in timestamp without time zone NOT NULL,
    stay_actual_check_in timestamp without time zone,
    stay_check_out timestamp without time zone NOT NULL,
    stay_actual_check_out timestamp without time zone,
    stay_occupant_count integer NOT NULL,
    stay_duration integer NOT NULL,
    stay_status text NOT NULL,
    stay_cancel_date timestamp without time zone,
    stay_last_updated timestamp without time zone DEFAULT now(),
    stay_created_date timestamp without time zone DEFAULT now()
);


ALTER TABLE public.stays OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 16853)
-- Name: stays_stay_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.stays_stay_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.stays_stay_id_seq OWNER TO postgres;

--
-- TOC entry 3482 (class 0 OID 0)
-- Dependencies: 230
-- Name: stays_stay_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stays_stay_id_seq OWNED BY public.stays.stay_id;


--
-- TOC entry 224 (class 1259 OID 16784)
-- Name: transaction_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transaction_types (
    transaction_type_id integer NOT NULL,
    transaction_type_description text NOT NULL
);


ALTER TABLE public.transaction_types OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16783)
-- Name: transaction_types_transaction_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.transaction_types_transaction_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.transaction_types_transaction_type_id_seq OWNER TO postgres;

--
-- TOC entry 3483 (class 0 OID 0)
-- Dependencies: 223
-- Name: transaction_types_transaction_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.transaction_types_transaction_type_id_seq OWNED BY public.transaction_types.transaction_type_id;


--
-- TOC entry 235 (class 1259 OID 16896)
-- Name: transactions_to_balances; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transactions_to_balances (
    guest_transaction_id integer NOT NULL,
    stay_balance_id integer NOT NULL
);


ALTER TABLE public.transactions_to_balances OWNER TO postgres;

--
-- TOC entry 3245 (class 2604 OID 16749)
-- Name: amenities amenity_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.amenities ALTER COLUMN amenity_id SET DEFAULT nextval('public.amenities_amenity_id_seq'::regclass);


--
-- TOC entry 3251 (class 2604 OID 16796)
-- Name: guest_transactions guest_transaction_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guest_transactions ALTER COLUMN guest_transaction_id SET DEFAULT nextval('public.guest_transactions_guest_transaction_id_seq'::regclass);


--
-- TOC entry 3246 (class 2604 OID 16758)
-- Name: guests guest_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guests ALTER COLUMN guest_id SET DEFAULT nextval('public.guests_guest_id_seq'::regclass);


--
-- TOC entry 3248 (class 2604 OID 16767)
-- Name: rate_schedules rate_schedule_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rate_schedules ALTER COLUMN rate_schedule_id SET DEFAULT nextval('public.rate_schedules_rate_schedule_id_seq'::regclass);


--
-- TOC entry 3249 (class 2604 OID 16776)
-- Name: room_types room_type_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.room_types ALTER COLUMN room_type_id SET DEFAULT nextval('public.room_types_room_type_id_seq'::regclass);


--
-- TOC entry 3255 (class 2604 OID 16886)
-- Name: stay_balances stay_balance_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stay_balances ALTER COLUMN stay_balance_id SET DEFAULT nextval('public.stay_balances_stay_balance_id_seq'::regclass);


--
-- TOC entry 3252 (class 2604 OID 16857)
-- Name: stays stay_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stays ALTER COLUMN stay_id SET DEFAULT nextval('public.stays_stay_id_seq'::regclass);


--
-- TOC entry 3250 (class 2604 OID 16787)
-- Name: transaction_types transaction_type_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transaction_types ALTER COLUMN transaction_type_id SET DEFAULT nextval('public.transaction_types_transaction_type_id_seq'::regclass);


--
-- TOC entry 3449 (class 0 OID 16389)
-- Dependencies: 214
-- Data for Name: alembic_version; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.alembic_version (version_num) FROM stdin;
5bd9a893a14e
\.


--
-- TOC entry 3451 (class 0 OID 16746)
-- Dependencies: 216
-- Data for Name: amenities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.amenities (amenity_id, amenity_description, amenity_premium, amenity_deleted, amenity_deleted_note) FROM stdin;
1	View	20	\N	\N
2	Balcony	25	\N	\N
3	Large room	40	\N	\N
4	Hair dryer	10	\N	\N
5	TV	10	\N	\N
\.


--
-- TOC entry 3461 (class 0 OID 16793)
-- Dependencies: 226
-- Data for Name: guest_transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.guest_transactions (guest_transaction_id, transaction_type_id, guest_id, guest_transaction_charge, guest_transaction_payment, guest_transaction_date, guest_transaction_deleted, guest_transaction_description) FROM stdin;
1	5	5	3180	0	2023-03-18 02:10:44.76493	\N	Room for 12 nights
2	5	8	4995	0	2023-03-18 02:10:44.76493	\N	Room for 27 nights
3	5	2	555	0	2023-03-18 02:10:44.76493	\N	Room for 3 nights
4	5	3	1800	0	2023-03-18 02:10:44.76493	\N	Room for 10 nights
5	5	4	1760	0	2023-03-18 02:10:44.76493	\N	Room for 8 nights
6	5	1	795	0	2023-03-18 02:10:44.76493	\N	Room for 3 nights
7	5	6	5940	0	2023-03-18 02:10:44.76493	\N	Room for 27 nights
8	5	9	1155	0	2023-03-18 02:10:44.76493	\N	Room for 7 nights
9	5	1	1581.75	0	2023-03-19 05:33:21.665772	2023-03-19 07:24:21.105035	Room for 9 nights
11	5	3	3021.00	0	2023-03-19 08:47:43.522838	2023-03-19 09:02:46.860918	Room for 12 nights
\.


--
-- TOC entry 3453 (class 0 OID 16755)
-- Dependencies: 218
-- Data for Name: guests; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.guests (guest_id, guest_first_name, guest_middle_initial, guest_last_name, guest_phone_number, guest_email, guest_state, guest_birthdate, guest_created_date, guest_last_updated) FROM stdin;
2	Person1	N	Last1	704-919-9297	person1@email.com	IL	1988-01-01	\N	2023-03-19 08:00:10.049546
3	Person2	I	Last2	304-919-9297	person2@email.com	IL	1992-01-01	\N	2023-03-19 08:00:10.049546
5	Person4	G	Last4	504-919-9297	person4@email.com	IL	1994-01-01	\N	2023-03-19 08:00:10.049546
6	Person5		Last5	404-919-9297	person5@email.com	TX	1981-01-01	\N	2023-03-19 08:00:10.049546
7	Person6		Last6	704-919-9297	person6@email.com	GA	1987-01-01	\N	2023-03-19 08:00:10.049546
8	Person7	G	Last7	604-919-9297	person7@email.com	WA	1991-01-01	\N	2023-03-19 08:00:10.049546
9	Person8	K	Last8	904-919-9297	person8@email.com	WA	1992-01-01	\N	2023-03-19 08:00:10.049546
10	Person9		Last9	804-919-9297	person9@email.com	IL	1975-01-01	\N	2023-03-19 08:00:10.049546
11	POST firstguest	A	POST lastguest	404-565-1001	post@guest1.com	GA	1993-02-01	2023-03-19 08:20:00.74252	2023-03-19 08:15:13.288485
12	POST secondguest	A	POST lastguest	404-565-1001	post@guest2.com	IL	1989-02-01	2023-03-19 08:22:32.815754	2023-03-19 08:22:32.815754
4	PUT secondguest	P	PUT secondguest	111-565-1001	put@secondupdate.com	NY	1994-01-01	\N	2023-03-19 08:23:03.966984
13	TEST firstname	A	TEST lastguest	123-222-1001	post@guest3.com	IL	1991-12-01	2023-03-19 08:59:31.853068	2023-03-19 08:59:31.853068
1	PUT thirdguest	P	PUT thirdguest	101-930-1022	put@thirdupdate.com	NY	1990-01-01	2023-03-19 08:01:24.296123	2023-03-19 09:01:24.327097
\.


--
-- TOC entry 3467 (class 0 OID 16867)
-- Dependencies: 232
-- Data for Name: guests_stays; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.guests_stays (guest_id, stay_id, guest_stay_active) FROM stdin;
3	22	f
9	27	f
5	19	f
8	20	f
2	21	f
4	24	f
1	25	f
6	26	f
10	23	f
1	28	f
3	30	f
\.


--
-- TOC entry 3455 (class 0 OID 16764)
-- Dependencies: 220
-- Data for Name: rate_schedules; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rate_schedules (rate_schedule_id, rate_start_date, rate_end_date, rate_discount, rate_premium) FROM stdin;
1	2023-01-01 00:00:00	2023-05-25 00:00:00	0	0
2	2023-01-01 00:00:00	2023-05-25 00:00:00	0	0
3	2023-01-01 00:00:00	2023-05-25 00:00:00	0	0
4	2023-05-26 00:00:00	2023-05-30 00:00:00	0	1.15
5	2023-05-26 00:00:00	2023-05-30 00:00:00	0	1.15
6	2023-05-26 00:00:00	2023-05-30 00:00:00	0	1.15
7	2023-05-31 00:00:00	2099-12-31 00:00:00	0.95	0
8	2023-05-31 00:00:00	2099-12-31 00:00:00	0.95	0
9	2023-05-31 00:00:00	2099-12-31 00:00:00	0.95	0
\.


--
-- TOC entry 3462 (class 0 OID 16811)
-- Dependencies: 227
-- Data for Name: room_type_rates; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.room_type_rates (room_type_id, rate_schedule_id) FROM stdin;
1	1
2	2
3	3
1	4
2	5
3	6
1	7
2	8
3	9
\.


--
-- TOC entry 3457 (class 0 OID 16773)
-- Dependencies: 222
-- Data for Name: room_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.room_types (room_type_id, room_type_bed_type, room_type_bed_count, room_type_max_occupants, room_type_base_rate) FROM stdin;
1	Single Queen	1	3	145
2	Single King	1	3	160
3	Double Queen	2	5	180
\.


--
-- TOC entry 3463 (class 0 OID 16826)
-- Dependencies: 228
-- Data for Name: rooms; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rooms (room_number, room_ready, room_available, room_type_id, room_fits_crib, room_deleted, room_deleted_note) FROM stdin;
001	t	2023-01-01 06:00:00	1	t	\N	\N
002	t	2023-01-01 06:00:00	2	t	\N	\N
003	t	2023-01-01 06:00:00	3	t	\N	\N
004	t	2023-01-01 06:00:00	3	t	\N	\N
005	t	2023-01-01 06:00:00	2	f	\N	\N
006	t	2023-01-01 06:00:00	1	t	\N	\N
\.


--
-- TOC entry 3464 (class 0 OID 16838)
-- Dependencies: 229
-- Data for Name: rooms_amenities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rooms_amenities (room_number, amenity_id) FROM stdin;
001	5
002	5
003	5
001	4
002	4
003	4
004	5
005	5
006	5
004	4
005	4
006	4
001	1
005	2
003	1
004	1
005	3
005	1
\.


--
-- TOC entry 3469 (class 0 OID 16883)
-- Dependencies: 234
-- Data for Name: stay_balances; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stay_balances (stay_balance_id, stay_total_charges, stay_total_payments, stay_balance, stay_id) FROM stdin;
1	0	0	0	19
2	0	0	0	20
3	0	0	0	21
4	0	0	0	22
5	0	0	0	23
6	0	0	0	24
7	0	0	0	25
8	0	0	0	26
9	0	0	0	27
10	0	0	0	28
11	0	0	0	30
\.


--
-- TOC entry 3466 (class 0 OID 16854)
-- Dependencies: 231
-- Data for Name: stays; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stays (stay_id, room_number, stay_holder_guest_id, stay_check_in, stay_actual_check_in, stay_check_out, stay_actual_check_out, stay_occupant_count, stay_duration, stay_status, stay_cancel_date, stay_last_updated, stay_created_date) FROM stdin;
23	002	10	2023-02-12 00:00:00	\N	2023-02-13 00:00:00	\N	1	1	CANCELLED	2023-02-12 00:00:00	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
28	001	1	2023-06-01 15:00:00	\N	2023-06-10 11:00:00	\N	1	9	CANCELLED	2023-03-19 07:24:21.212281	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
30	005	3	2023-06-03 15:00:00	\N	2023-06-15 11:00:00	\N	1	12	CANCELLED	2023-03-19 04:02:46.883239	2023-03-19 09:02:46.860918	2023-03-19 08:51:38.633677
22	002	3	2023-02-01 00:00:00	2023-02-01 00:00:00	2023-02-11 00:00:00	2023-02-11 00:00:00	1	10	PAST	\N	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
27	006	9	2023-02-01 00:00:00	2023-02-01 00:00:00	2023-02-08 00:00:00	2023-02-08 00:00:00	1	7	PAST	\N	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
19	005	5	2023-02-01 00:00:00	\N	2023-02-13 00:00:00	2023-02-13 00:00:00	1	12	PAST	\N	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
20	001	8	2023-02-01 00:00:00	2023-02-01 00:00:00	2023-02-28 00:00:00	2023-02-28 00:00:00	2	27	PAST	\N	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
21	001	2	2023-03-03 00:00:00	\N	2023-03-06 00:00:00	2023-03-06 00:00:00	1	3	PAST	\N	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
24	003	4	2023-02-10 00:00:00	2023-02-10 00:00:00	2023-02-19 00:00:00	2023-02-19 00:00:00	1	8	PAST	\N	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
25	005	1	2023-02-14 00:00:00	\N	2023-02-17 00:00:00	2023-02-17 00:00:00	1	3	PAST	\N	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
26	004	6	2023-02-01 00:00:00	2023-02-01 00:00:00	2023-02-28 00:00:00	2023-02-28 00:00:00	1	27	PAST	\N	2023-03-19 08:11:16.410732	2023-03-19 08:51:38.633677
\.


--
-- TOC entry 3459 (class 0 OID 16784)
-- Dependencies: 224
-- Data for Name: transaction_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.transaction_types (transaction_type_id, transaction_type_description) FROM stdin;
1	Early check in fee
2	Late check out fee
3	Additional person fee
4	Parking fee
5	Room nightly rate
6	Breakfast included 1 person
\.


--
-- TOC entry 3470 (class 0 OID 16896)
-- Dependencies: 235
-- Data for Name: transactions_to_balances; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.transactions_to_balances (guest_transaction_id, stay_balance_id) FROM stdin;
9	10
11	11
\.


--
-- TOC entry 3484 (class 0 OID 0)
-- Dependencies: 215
-- Name: amenities_amenity_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.amenities_amenity_id_seq', 5, true);


--
-- TOC entry 3485 (class 0 OID 0)
-- Dependencies: 225
-- Name: guest_transactions_guest_transaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.guest_transactions_guest_transaction_id_seq', 11, true);


--
-- TOC entry 3486 (class 0 OID 0)
-- Dependencies: 217
-- Name: guests_guest_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.guests_guest_id_seq', 13, true);


--
-- TOC entry 3487 (class 0 OID 0)
-- Dependencies: 219
-- Name: rate_schedules_rate_schedule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.rate_schedules_rate_schedule_id_seq', 9, true);


--
-- TOC entry 3488 (class 0 OID 0)
-- Dependencies: 221
-- Name: room_types_room_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.room_types_room_type_id_seq', 3, true);


--
-- TOC entry 3489 (class 0 OID 0)
-- Dependencies: 233
-- Name: stay_balances_stay_balance_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stay_balances_stay_balance_id_seq', 11, true);


--
-- TOC entry 3490 (class 0 OID 0)
-- Dependencies: 230
-- Name: stays_stay_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stays_stay_id_seq', 30, true);


--
-- TOC entry 3491 (class 0 OID 0)
-- Dependencies: 223
-- Name: transaction_types_transaction_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.transaction_types_transaction_type_id_seq', 6, true);


--
-- TOC entry 3257 (class 2606 OID 16393)
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- TOC entry 3259 (class 2606 OID 16753)
-- Name: amenities amenities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.amenities
    ADD CONSTRAINT amenities_pkey PRIMARY KEY (amenity_id);


--
-- TOC entry 3271 (class 2606 OID 16800)
-- Name: guest_transactions guest_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guest_transactions
    ADD CONSTRAINT guest_transactions_pkey PRIMARY KEY (guest_transaction_id);


--
-- TOC entry 3261 (class 2606 OID 16762)
-- Name: guests guests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guests
    ADD CONSTRAINT guests_pkey PRIMARY KEY (guest_id);


--
-- TOC entry 3279 (class 2606 OID 16871)
-- Name: guests_stays guests_stays_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guests_stays
    ADD CONSTRAINT guests_stays_pkey PRIMARY KEY (guest_id, stay_id);


--
-- TOC entry 3263 (class 2606 OID 16771)
-- Name: rate_schedules rate_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rate_schedules
    ADD CONSTRAINT rate_schedules_pkey PRIMARY KEY (rate_schedule_id);


--
-- TOC entry 3273 (class 2606 OID 16815)
-- Name: room_type_rates room_type_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.room_type_rates
    ADD CONSTRAINT room_type_rates_pkey PRIMARY KEY (room_type_id, rate_schedule_id);


--
-- TOC entry 3265 (class 2606 OID 16780)
-- Name: room_types room_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.room_types
    ADD CONSTRAINT room_types_pkey PRIMARY KEY (room_type_id);


--
-- TOC entry 3267 (class 2606 OID 16782)
-- Name: room_types room_types_room_type_bed_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.room_types
    ADD CONSTRAINT room_types_room_type_bed_type_key UNIQUE (room_type_bed_type);


--
-- TOC entry 3275 (class 2606 OID 16832)
-- Name: rooms rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_pkey PRIMARY KEY (room_number);


--
-- TOC entry 3281 (class 2606 OID 16890)
-- Name: stay_balances stay_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stay_balances
    ADD CONSTRAINT stay_balances_pkey PRIMARY KEY (stay_balance_id);


--
-- TOC entry 3277 (class 2606 OID 16861)
-- Name: stays stays_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stays
    ADD CONSTRAINT stays_pkey PRIMARY KEY (stay_id);


--
-- TOC entry 3269 (class 2606 OID 16791)
-- Name: transaction_types transaction_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transaction_types
    ADD CONSTRAINT transaction_types_pkey PRIMARY KEY (transaction_type_id);


--
-- TOC entry 3283 (class 2606 OID 16900)
-- Name: transactions_to_balances transactions_to_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions_to_balances
    ADD CONSTRAINT transactions_to_balances_pkey PRIMARY KEY (guest_transaction_id, stay_balance_id);


--
-- TOC entry 3297 (class 2620 OID 16928)
-- Name: guests populate_guest_created_date; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER populate_guest_created_date AFTER INSERT ON public.guests FOR EACH ROW EXECUTE FUNCTION public.add_guest_created_date();


--
-- TOC entry 3299 (class 2620 OID 16930)
-- Name: stays populate_guest_stay_balances; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER populate_guest_stay_balances AFTER INSERT ON public.stays FOR EACH ROW EXECUTE FUNCTION public.add_stay_balances();


--
-- TOC entry 3300 (class 2620 OID 16914)
-- Name: stays populate_guest_transactions; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER populate_guest_transactions AFTER INSERT ON public.stays FOR EACH ROW EXECUTE FUNCTION public.add_guest_stay_transaction();


--
-- TOC entry 3301 (class 2620 OID 16912)
-- Name: stays populate_guests_stays; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER populate_guests_stays AFTER INSERT ON public.stays FOR EACH ROW EXECUTE FUNCTION public.add_guests_stays();


--
-- TOC entry 3302 (class 2620 OID 16932)
-- Name: stays populate_stay_created_date; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER populate_stay_created_date AFTER INSERT ON public.stays FOR EACH ROW EXECUTE FUNCTION public.add_stay_created_date();


--
-- TOC entry 3298 (class 2620 OID 16915)
-- Name: guest_transactions populate_transaction_to_balances; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER populate_transaction_to_balances AFTER INSERT ON public.guest_transactions FOR EACH ROW EXECUTE FUNCTION public.add_transaction_to_balances();


--
-- TOC entry 3306 (class 2620 OID 16916)
-- Name: transactions_to_balances update_stay_balances; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_stay_balances AFTER INSERT ON public.transactions_to_balances FOR EACH ROW EXECUTE FUNCTION public.update_stay_balances_total();


--
-- TOC entry 3303 (class 2620 OID 16923)
-- Name: stays update_stays_cancel_date; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_stays_cancel_date AFTER UPDATE OF stay_cancel_date ON public.stays FOR EACH ROW EXECUTE FUNCTION public.update_stays_cancel_date();


--
-- TOC entry 3304 (class 2620 OID 16921)
-- Name: stays update_stays_check_in; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_stays_check_in AFTER UPDATE OF stay_actual_check_in ON public.stays FOR EACH ROW EXECUTE FUNCTION public.update_stays_check_in_status();


--
-- TOC entry 3305 (class 2620 OID 16922)
-- Name: stays update_stays_check_out; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_stays_check_out AFTER UPDATE OF stay_actual_check_out ON public.stays FOR EACH ROW EXECUTE FUNCTION public.update_stays_check_out_status();


--
-- TOC entry 3284 (class 2606 OID 16801)
-- Name: guest_transactions guest_transactions_guest_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guest_transactions
    ADD CONSTRAINT guest_transactions_guest_id_fkey FOREIGN KEY (guest_id) REFERENCES public.guests(guest_id);


--
-- TOC entry 3285 (class 2606 OID 16806)
-- Name: guest_transactions guest_transactions_transaction_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guest_transactions
    ADD CONSTRAINT guest_transactions_transaction_type_id_fkey FOREIGN KEY (transaction_type_id) REFERENCES public.transaction_types(transaction_type_id);


--
-- TOC entry 3292 (class 2606 OID 16872)
-- Name: guests_stays guests_stays_guest_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guests_stays
    ADD CONSTRAINT guests_stays_guest_id_fkey FOREIGN KEY (guest_id) REFERENCES public.guests(guest_id);


--
-- TOC entry 3293 (class 2606 OID 16877)
-- Name: guests_stays guests_stays_stay_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.guests_stays
    ADD CONSTRAINT guests_stays_stay_id_fkey FOREIGN KEY (stay_id) REFERENCES public.stays(stay_id);


--
-- TOC entry 3286 (class 2606 OID 16816)
-- Name: room_type_rates room_type_rates_rate_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.room_type_rates
    ADD CONSTRAINT room_type_rates_rate_schedule_id_fkey FOREIGN KEY (rate_schedule_id) REFERENCES public.rate_schedules(rate_schedule_id);


--
-- TOC entry 3287 (class 2606 OID 16821)
-- Name: room_type_rates room_type_rates_room_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.room_type_rates
    ADD CONSTRAINT room_type_rates_room_type_id_fkey FOREIGN KEY (room_type_id) REFERENCES public.room_types(room_type_id);


--
-- TOC entry 3289 (class 2606 OID 16843)
-- Name: rooms_amenities rooms_amenities_amenity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rooms_amenities
    ADD CONSTRAINT rooms_amenities_amenity_id_fkey FOREIGN KEY (amenity_id) REFERENCES public.amenities(amenity_id);


--
-- TOC entry 3290 (class 2606 OID 16848)
-- Name: rooms_amenities rooms_amenities_room_number_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rooms_amenities
    ADD CONSTRAINT rooms_amenities_room_number_fkey FOREIGN KEY (room_number) REFERENCES public.rooms(room_number);


--
-- TOC entry 3288 (class 2606 OID 16833)
-- Name: rooms rooms_room_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_room_type_id_fkey FOREIGN KEY (room_type_id) REFERENCES public.room_types(room_type_id);


--
-- TOC entry 3294 (class 2606 OID 16891)
-- Name: stay_balances stay_balances_stay_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stay_balances
    ADD CONSTRAINT stay_balances_stay_id_fkey FOREIGN KEY (stay_id) REFERENCES public.stays(stay_id);


--
-- TOC entry 3291 (class 2606 OID 16862)
-- Name: stays stays_room_number_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stays
    ADD CONSTRAINT stays_room_number_fkey FOREIGN KEY (room_number) REFERENCES public.rooms(room_number);


--
-- TOC entry 3295 (class 2606 OID 16901)
-- Name: transactions_to_balances transactions_to_balances_guest_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions_to_balances
    ADD CONSTRAINT transactions_to_balances_guest_transaction_id_fkey FOREIGN KEY (guest_transaction_id) REFERENCES public.guest_transactions(guest_transaction_id);


--
-- TOC entry 3296 (class 2606 OID 16906)
-- Name: transactions_to_balances transactions_to_balances_stay_balance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions_to_balances
    ADD CONSTRAINT transactions_to_balances_stay_balance_id_fkey FOREIGN KEY (stay_balance_id) REFERENCES public.stay_balances(stay_balance_id);


-- Completed on 2023-03-19 20:19:40 UTC

--
-- PostgreSQL database dump complete
--

