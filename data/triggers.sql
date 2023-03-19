-- TRIGGER WHEN A NEW RATE SCHEDULE IS ADDED
-- Update last rate schedule to end before the new starts



-- TRIGGER FOR STAY CREATED DATE
-- Update created date when stay is created
CREATE OR REPLACE FUNCTION add_stay_created_date()
RETURNS TRIGGER
AS $$
BEGIN
    UPDATE stays
	SET stay_created_date = now()
	WHERE stay_id = NEW.stay_id;
RETURN NEW;
END;
$$ LANGUAGE PLPGSQL

CREATE TRIGGER populate_stay_created_date
AFTER INSERT ON stays
FOR EACH ROW EXECUTE PROCEDURE add_stay_created_date();


-- TRIGGER FOR GUEST CREATED DATE
-- Update created date when record is created
CREATE OR REPLACE FUNCTION add_guest_created_date()
RETURNS TRIGGER
AS $$
BEGIN
    UPDATE guests
	SET guest_created_date = now()
	WHERE guest_id = NEW.guest_id;
RETURN NEW;
END;
$$ LANGUAGE PLPGSQL

CREATE TRIGGER populate_guest_created_date
AFTER INSERT ON guests
FOR EACH ROW EXECUTE PROCEDURE add_guest_created_date();


-- TRIGGER WHEN A STAY RECORD IS INSERTED
-- Create a guests_stays row for the guest ID and stay ID.
-- Active stay flag is set to False
CREATE OR REPLACE FUNCTION add_guests_stays()
RETURNS TRIGGER
AS $$
BEGIN
    INSERT INTO guests_stays (guest_id, stay_id, guest_stay_active)
    VALUES (NEW.stay_holder_guest_id, NEW.stay_id, false);
RETURN NEW;
END;
$$ LANGUAGE PLPGSQL

CREATE TRIGGER populate_guests_stays
AFTER INSERT ON stays
FOR EACH ROW EXECUTE PROCEDURE add_guests_stays();

-- Create a stay_balances row for the stay_id
CREATE OR REPLACE FUNCTION add_stay_balances()
RETURNS TRIGGER
AS $$
BEGIN
    INSERT INTO stay_balances (stay_total_charges,
							   stay_total_payments,
							   stay_balance,
							   stay_id)
    VALUES (0, 0, 0, NEW.stay_id);
RETURN NEW;
END;
$$ LANGUAGE PLPGSQL

CREATE TRIGGER populate_stay_balances
AFTER INSERT ON stays
FOR EACH ROW EXECUTE PROCEDURE add_stay_balances();

-- Create a guest_transactions row for the guest
-- Uses room types and rate schedule pricing to calculate charge
CREATE OR REPLACE FUNCTION add_guest_stay_transaction()
RETURNS TRIGGER
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
$$ LANGUAGE PLPGSQL

CREATE TRIGGER populate_guest_transactions
AFTER INSERT ON stays
FOR EACH ROW EXECUTE PROCEDURE add_guest_stay_transaction();


-- TRIGGER WHEN A TRANSACTION IS INSERTED
-- Create transactions_to_balances row linking the stay balances ID to guest transaction ID
CREATE OR REPLACE FUNCTION add_transaction_to_balances()
RETURNS TRIGGER
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
$$ LANGUAGE PLPGSQL

CREATE TRIGGER populate_transaction_to_balances
AFTER INSERT ON guest_transactions
FOR EACH ROW EXECUTE PROCEDURE add_transaction_to_balances();

-- 2. Update stay_balances to reflect the total from the new transaction.
CREATE OR REPLACE FUNCTION update_stay_balances_total()
RETURNS TRIGGER
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
$$ LANGUAGE PLPGSQL

CREATE TRIGGER update_stay_balances
AFTER INSERT ON transactions_to_balances
FOR EACH ROW EXECUTE PROCEDURE update_stay_balances_total();

-- TRIGGER WHEN stay actual check in is updated
-- Update stay_status to CURRENT

CREATE OR REPLACE FUNCTION update_stays_check_in_status()
RETURNS TRIGGER
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
$$ LANGUAGE PLPGSQL

CREATE TRIGGER update_stays_check_in
AFTER UPDATE OF stay_actual_check_in ON stays
FOR EACH ROW EXECUTE PROCEDURE update_stays_check_in_status();

-- TRIGGER WHEN actual check out date is updated
-- Update stay_status to PAST

CREATE OR REPLACE FUNCTION update_stays_check_out_status()
RETURNS TRIGGER
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
$$ LANGUAGE PLPGSQL

CREATE TRIGGER update_stays_check_out
AFTER UPDATE OF stay_actual_check_out ON stays
FOR EACH ROW EXECUTE PROCEDURE update_stays_check_out_status();

-- TRIGGER WHEN cancel date is added
-- Update stay_status to CANCELLED
-- Marks as deleted the guest transactions
-- Sets Stay Balances to 0 again

CREATE OR REPLACE FUNCTION update_stays_cancel_date()
RETURNS TRIGGER
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
$$ LANGUAGE PLPGSQL

CREATE TRIGGER update_stays_cancel_date
AFTER UPDATE OF stay_cancel_date ON stays
FOR EACH ROW EXECUTE PROCEDURE update_stays_cancel_date(); 
