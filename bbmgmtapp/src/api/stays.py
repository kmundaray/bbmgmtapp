from flask import Blueprint, jsonify, abort, request
from ..models import db , Stays, Guests, Rooms
import sqlalchemy
from datetime import datetime, timezone

bp = Blueprint('Stays', __name__, url_prefix='/stays')

#_________________________GET____________________________#
@bp.route('', methods=['GET'])    # Decorator takes path and list of HTTP verbs
def index():
    stays = Stays.query.all()    # ORM performs SELECT query
    result = []
    for u in stays:
        result.append(u.serialize())   # Build list of Users as dictionaries
    return jsonify(result)             # Returns a JSON response

@bp.route('/<int:stay_id>', methods=['GET'])
def show(stay_id: int):
    u = Stays.query.get(stay_id)
    if u is None:
        return abort(404, 'Stay ID not found.')
    return jsonify(u.serialize())

#_________________________POST____________________________#
@bp.route('/newstay', methods=['POST'])
def create():
    # Req body must contain stay details 
    if ('room_number' not in request.json or 
        'stay_holder_guest_id' not in request.json or
        'stay_check_in' not in request.json or
        'stay_check_out' not in request.json
        ):
        return abort(400, "The request body did not include the information required.")
    # Transform string dates to datetime
    dt_stay_check_in = datetime.strptime(request.json['stay_check_in'], "%Y-%m-%d %H:%M:%S")
    dt_stay_check_out = datetime.strptime(request.json['stay_check_out'], "%Y-%m-%d %H:%M:%S")
    # Check if stay exist for room 
    find_stay = sqlalchemy.select(Stays.stay_check_in, Stays.stay_check_out
        ).where(Stays.room_number == request.json['room_number']
        ).where(Stays.stay_status.in_(['CURRENT','FUTURE'])
        ).where(Stays.stay_cancel_date.is_(None))
    result = db.session.execute(find_stay).fetchall()
    # Check if there is a stay within the stay dates sent
    if len(result) > 0:
        for row in result:
            row_check_in = row.stay_check_in
            row_check_out = row.stay_check_out
            if ((dt_stay_check_in > row_check_in or dt_stay_check_in == row_check_in) and 
                (dt_stay_check_in < row_check_out or dt_stay_check_in == row_check_out)):
                return abort(409, 'Stay check in overlaps with another stay.')
            elif ((dt_stay_check_out > row_check_in or dt_stay_check_out == row_check_in) and 
                  (dt_stay_check_out < row_check_out or dt_stay_check_out == row_check_out)):
                return abort(409, 'Stay check out overlaps with another stay.')
    # Check the stay holder is a guest
    find_stay_holder_guest_id = sqlalchemy.select(Guests.guest_id).where(
        Guests.guest_id == request.json['stay_holder_guest_id'])
    guest_id = db.session.scalar(find_stay_holder_guest_id)
    if guest_id is None:
        return abort(409, 'Guest ID provided does not exist. Please create the guest record first.')
    # Need to make sure that the room number exists.
    find_room_number = sqlalchemy.select(Rooms.room_number).where(
        Rooms.room_number == request.json['room_number'])
    room_number = db.session.scalar(find_room_number)
    if room_number is None:
        return abort(409, 'Invalid room number provided.')
    # If validation passes
    room_number = request.json['room_number']
    stay_holder_guest_id = int(request.json['stay_holder_guest_id'])
    stay_check_in = dt_stay_check_in
    stay_check_out = dt_stay_check_out
    stay_status = 'FUTURE'          
    # Assign correct values before insert
    try:
        if request.json['stay_occupant_count'] is None:
            stay_occupant_count = 1
        else:
            stay_occupant_count = request.json['stay_occupant_count']
    except KeyError:
        stay_occupant_count = 1
    # Assign correct values before insert
    stay_days = stay_check_out - stay_check_in
    stay_duration = (stay_days.days + 1)
    # Construct insert
    new_stay_insert = sqlalchemy.insert(Stays).values(
        room_number = room_number,
        stay_holder_guest_id = stay_holder_guest_id,
        stay_check_in = stay_check_in,
        stay_check_out = stay_check_out,
        stay_occupant_count = stay_occupant_count,
        stay_duration = stay_duration,
        stay_status = stay_status
        )
    db.session.execute(new_stay_insert)     # Execute INSERT statement
    db.session.commit()                     # Execute INSERT statement
    # Get the new ID
    find_created_stay = sqlalchemy.select(Stays.stay_id).where(
        Stays.room_number == room_number,
        Stays.stay_holder_guest_id == stay_holder_guest_id,
        Stays.stay_status == stay_status
        )
    stay_id = db.session.scalar(find_created_stay)
    # return the new guest ID
    return show(stay_id)

@bp.route('/cancelstay', methods=['POST']) 
def cancel():
    # Req body must contain stay details 
    if ('room_number' not in request.json or 
        'stay_holder_guest_id' not in request.json or
        'stay_check_in' not in request.json or
        'stay_check_out' not in request.json
        ):
        return abort(400, "The request body did not include the information required.")
    # Need to make sure that the room number exists.
    find_room_number = sqlalchemy.select(Rooms.room_number).where(
        Rooms.room_number == request.json['room_number'])
    room_number = db.session.scalar(find_room_number)
    if room_number is None:
        return abort(409, 'Invalid room number provided.')
    # Check the stay holder is a guest
    find_stay_holder_guest_id = sqlalchemy.select(Guests.guest_id).where(
        Guests.guest_id == request.json['stay_holder_guest_id'])
    guest_id = db.session.scalar(find_stay_holder_guest_id)
    if guest_id is None:
        return abort(409, 'Guest ID provided does not exist.')
    # Transform string dates to datetime
    dt_stay_check_in = datetime.strptime(request.json['stay_check_in'], "%Y-%m-%d %H:%M:%S")#.replace(tzinfo=timezone.utc)
    dt_stay_check_out = datetime.strptime(request.json['stay_check_out'], "%Y-%m-%d %H:%M:%S")
    # Check if there is a stay within the stay dates sent
    find_stay = sqlalchemy.select(Stays.stay_id
        ).where(Stays.room_number == request.json['room_number']
        ).where(Stays.stay_holder_guest_id == request.json['stay_holder_guest_id']
        ).where(Stays.stay_status == "FUTURE"
        ).where(Stays.stay_cancel_date.is_(None)
        ).where(Stays.stay_check_in == dt_stay_check_in
        ).where(Stays.stay_check_out == dt_stay_check_out
        )
    # Get the stay ID needed from the result
    cancelled_stay_id = 0
    result = db.session.execute(find_stay).scalars()
    for found_stay_id in result:
        cancelled_stay_id = found_stay_id
    # Abort if no stay results found
    if cancelled_stay_id == 0:
        return abort(409, 'No stays found with the details provided.')
    # If validation passes, construct insert
    cancel_stay_update = sqlalchemy.update(Stays).where(Stays.stay_id == cancelled_stay_id
                                                ).values(stay_cancel_date = datetime.now())
    # Apply insert
    db.session.execute(cancel_stay_update)     # Execute CREATE statement
    db.session.commit()          # Execute CREATE statement
    # return the cancelled stay details
    return show(cancelled_stay_id)