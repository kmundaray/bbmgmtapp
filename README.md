# Bed and Breakfast Management App
This app allows you to manage a small B&B business.
It records guests information, stay details, and the charges incurred.
The APIs described below allow for searching, entering, or deleting data.

### Notes
- ERD in /documents/
- Docker compose includes a pg_admin container to review the database.
- Trigger functions were applied directly into the database.
- See trigger SQL script in /data/
- See test db pg_dump in /data/

## Tables
- amenities: lists the amenities available for each room.
  - SELECT * FROM amenities;
- guest_transactions: transaction table for each stay.
  - SELECT * FROM guest_transactions;
- guests: list of guests.
  - SELECT * FROM guests;
- guests_stays: mapping of guest to stay.
  - SELECT * FROM guests_stays;
- rate_schedules: schedule premium or discount.
  - SELECT * FROM rate_schedules;
- room_type_rates: mapping of room type to rate schedule.
  - SELECT * FROM room_type_rates;
- room_types: available types of rooms.
  - SELECT * FROM room_types;
- rooms: each room available.
  - SELECT * FROM rooms;
- rooms_amenities: mapping of room to amenities.
  - SELECT * FROM rooms_amenities;
- stay_balances: total balance for each stay.
  - SELECT * FROM stay_balances;
- stays: contains all stay records.
  - SELECT * FROM stays;
- transaction_types: list of available types of transactions.
  - SELECT * FROM transaction_types;
- transactions_to_balances: mapping of transactions to total balance.
  - SELECT * FROM transactions_to_balances;

## Future Tables
- Table with metrics from all stay records.

## App Endpoints/Methods
| Blueprint    | Paths                                               | Methods  | Parameters      | Description                                   |
| :----:       | :---                                                | :---     | :--             | :---                                          |
| Guests       | /guests                                             | GET      |                 | Returns all guest records                     |
|              | /guests/<guest_id>                                  | GET      | guest_id        | Returns specific guest record                 |
|              | /guests/<guest_id>/stays                            | GET      | guest_id        | Returns all stay records for specific guest   |
|              | /guests/newguest                                    | POST     | guest_first_name, [guest_middle_initial], guest_last_name, guest_phone_number, guest_email, [guest_state], guest_birthdate | Creates a new guest record |
|              | /guests/updateguest                                 | PUT      | guest_id, [guest_first_name], [guest_middle_initial], [guest_last_name], [guest_phone_number], [guest_email], [guest_state], [guest_birthdate]| Updates a specific guest record |
|              | /guests/deleteguest/<guest_id>                      | DELETE   | guest_id        | Deletes a specific guest record               |
| Transactions | /transactionbalances/                               | GET      |                 | Returns all balances for all stay records     |
|              | /transactionbalances/<stay_balance_id>              | GET      | stay_balance_id | Returns the balance for a stay record         |
|              | /transactionbalances/<stay_balance_id>/transactions | GET      | stay_balance_id | Returns all transactions for specific balance |
| Stays        | /stays                                              | GET      |                 | Returns all stay records                      |
|              | /stays/<stay_id>                                    | GET      | stay_id         | Returns a specific stay record                |
|              | /stays/newstay                                      | POST     | room_number, stay_holder_guest_id, stay_check_in, stay_check_out | Creates a new stay record |
|              | /stays/cancelstay                                   | POST     | room_number, stay_holder_guest_id, stay_check_in, stay_check_out | Returns a specific stay record |
| Rooms        | /rooms                                              | GET      |                 | Returns all room records                      |
|              | /rooms/<room_number>                                | GET      |                 | Returns a specific room record                |
|              | /rooms/<room_number>/amenities                      | GET      |                 | Returns all amenities for the room number     |
|              | /roomtypes                                          | GET      |                 | Returns all room type records                 |
|              | /roomtypes/<room_type_id>                           | GET      |                 | Returns a specific room type record           |
|              | /roomtypes/<room_type_id>/rateschedules             | GET      |                 | Returns all room type rate schedules          |


## Future APIs
- API TO PAY FOR A BALANCE
- API TO VIEW TOTAL BALANCE
- API TO GET TRANSACTION TYPES
- API TO UPDATE ROOM TYPES BASE RATES
- API TO ADD RATE SCHEDULE
  - Trigger will end last schedule where new starts
- API TO CHECK GUEST IN
  - Trigger will update stay status to current
- API TO CHECK GUEST OUT
  - Trigger will update stay status to past
  - Need to check if length of stay changed and adjust length!
  - If length of stay increased, add additional nights and charge additional amount
  - NEED TRIGGER FOR THIS or decide if create a new stay
- API TO CANCEL A STAY
  - Must mark as deleted the guest transactions
  - Must update stay balance to not consider deleted rows in calculation
  - Must set Stay Balances to 0 again
- API TO PULL TABLE WITH METRICS ON STAY TABLE

## Pending Triggers
- TRIGGER WHEN A NEW RATE SCHEDULE IS ADDED
  - Update last rate schedule to end before the new starts

## Optimization
- Index on guests first names in guests table.

## Future Stored Procedures
- Automatically review the stays table every day to calculate metrics.

## Retrospective (3/2023)
- How did the project's design evolve over time?
  - It became much more complex than initially thought out.
  - Tried to use triggers to reduce the number of APIs needed to enter data.
  - Attempted to

- Did you choose to use an ORM or raw SQL? Why?
  - Chose the ORM approach after I had built most tables in raw SQL to learn.
  - I was unable to get triggers to work in ORM this time so these were applied in pgAdmin.

- What future improvements are in store, if any?
  - More endpoints and stored procedures that update and validate the data.
