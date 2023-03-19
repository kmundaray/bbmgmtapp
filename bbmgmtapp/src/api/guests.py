from flask import Blueprint, jsonify, abort, request, Response
from ..models import db , Guests
import sqlalchemy

bp = Blueprint('Guests', __name__, url_prefix='/guests')

#_________________________GET____________________________#
@bp.route('', methods=['GET'])    # Decorator takes path and list of HTTP verbs
def index():
    guests = Guests.query.all()    # ORM performs SELECT query
    result = []
    for u in guests:
        result.append(u.serialize())   # Build list of Users as dictionaries
    return jsonify(result)             # Returns a JSON response

@bp.route('/<int:guest_id>', methods=['GET'])
def show(guest_id: int):
    u = Guests.query.get(guest_id)
    if u is None:
        return abort(404, 'Guest ID not found.')
    return jsonify(u.serialize())

@bp.route('/<int:guest_id>/stays', methods=['GET'])
def likes(guest_id: int):
    u = Guests.query.get(guest_id)
    if u is None:
        return abort(404, 'Guest ID not found.')
    # Check if stays exist
    if u.guests_stays is None:
        return abort(404, 'No stays found for this guest.')
    # Return stays    
    result = []
    for s in u.guests_stays:
        result.append(s.serialize())
    return jsonify(result)
    # Raw SQL
    # SELECT  g.*, s.*
    # from guests g
    # join guests_stays gs on gs.guest_id = g.guest_id
    # join stays s on s.stay_id = gs.stay_id
    # where g.guest_id = 1;

#_________________________POST____________________________#
@bp.route('/newguest', methods=['POST'])
def create():
    # Req body must contain username and password
    if ('guest_first_name' not in request.json or 
        'guest_last_name' not in request.json or
        'guest_email' not in request.json or
        'guest_birthdate' not in request.json
        ):
        return abort(400, "The request body did not include the information required.")
    # Check if guest already exists
    find_guest = sqlalchemy.select(Guests).where(
        Guests.guest_first_name == request.json['guest_first_name'],
        Guests.guest_last_name == request.json['guest_last_name'],
        Guests.guest_phone_number == request.json['guest_phone_number']
        )
    result = db.session.execute(find_guest)
    if len(result.all()) > 0:
        return abort(409, 'Guest with the same name and phone number already exists.')
    # Check for length
    if (len(request.json['guest_first_name']) < 3 or 
        len(request.json['guest_last_name']) < 3 or
        len(request.json['guest_phone_number']) < 12 or
        len(request.json['guest_birthdate']) < 10):
        return abort(409, 'Required values provided are invalid.')
    # If validation passes
    guest_first_name = request.json['guest_first_name']
    guest_last_name = request.json['guest_last_name']
    guest_phone_number = request.json['guest_phone_number']
    guest_email = request.json['guest_email']
    guest_birthdate = request.json['guest_birthdate']          # Date
    # Assign correct values before insert
    if ('guest_middle_initial' not in request.json or len(request.json['guest_middle_initial']) != 1):
        guest_middle_initial = None
    else:
        guest_middle_initial = request.json['guest_middle_initial']
    # Assign correct values before insert
    if ('guest_state' not in request.json or len(request.json['guest_state']) < 2):
        guest_state = None
    else:
        guest_state = request.json['guest_state']              # 2 chars
    # Construct insert
    new_guest_insert = sqlalchemy.insert(Guests).values(
        guest_first_name = guest_first_name,
        guest_middle_initial = guest_middle_initial,
        guest_last_name = guest_last_name,
        guest_phone_number = guest_phone_number,
        guest_email = guest_email,
        guest_state = guest_state,
        guest_birthdate = guest_birthdate
        )
    db.session.execute(new_guest_insert)     # Execute CREATE statement
    db.session.commit()          # Execute CREATE statement
    # Get the new ID
    find_created_guest = sqlalchemy.select(Guests.guest_id).where(
        Guests.guest_first_name == guest_first_name,
        Guests.guest_last_name == guest_last_name,
        Guests.guest_phone_number == guest_phone_number
        )
    guest_id = db.session.scalar(find_created_guest)
    # return the new guest ID
    return show(guest_id)

#_________________________PATCH/PUT____________________________#
@bp.route('/updateguest', methods=['PUT'])
def update():
    # Req body must contain username and password
    if (len(request.json) < 1 or 'guest_id' not in request.json or len(str(request.json['guest_id'])) < 1):
        return abort(400, "The request body did not include the ID to be updated.")
    guest_id = int(request.json['guest_id'])
    # Check if guest ID exists
    find_guest = db.session.query(Guests).where(Guests.guest_id == guest_id).all()
    if len(find_guest) == 0:
        return abort(409, 'No guest found with that ID.')
    # Assign queried values before update
    for row in find_guest:
        guest_first_name = row.__dict__['guest_first_name']
        guest_middle_initial = row.__dict__['guest_middle_initial']
        guest_last_name = row.__dict__['guest_last_name']
        guest_phone_number = row.__dict__['guest_phone_number']
        guest_email = row.__dict__['guest_email']
        guest_state = row.__dict__['guest_state']
        guest_birthdate = row.__dict__['guest_birthdate']
    # Update values if they are being changed
    if 'guest_first_name' in request.json:
        if len(request.json['guest_first_name']) < 3:
            return abort(409, 'Lenght requirement not met in first name provided.')
        guest_first_name = request.json['guest_first_name']
    if 'guest_middle_initial' in request.json:
        if len(request.json['guest_middle_initial']) != 1:
            return abort(409, 'Length requirement not met in middle initial provided.')
        guest_middle_initial = request.json['guest_middle_initial']
    if 'guest_last_name' in request.json:
        if len(request.json['guest_last_name']) < 3:
            return abort(409, 'Lenght requirement not met in last name provided.')
        guest_last_name = request.json['guest_last_name']
    if 'guest_phone_number' in request.json:
        if len(request.json['guest_phone_number']) < 12:
            return abort(409, 'Lenght requirement not met in phone number provided.')
        guest_phone_number = request.json['guest_phone_number']
    if 'guest_email' in request.json:
        if '@' not in request.json['guest_email'] or '.' not in request.json['guest_email']:
            return abort(409, 'Incorrect email format provided.')
        guest_email = request.json['guest_email']
    if 'guest_state' in request.json:
        if len(request.json['guest_state']) != 2:
            return abort(409, 'Length requirement not met in state provided.')
        guest_state = request.json['guest_state']
    if 'guest_birthdate' in request.json:
        if len(request.json['guest_birthdate']) < 10:
            return abort(409, 'Lenght requirement not met in birthdate provided.')
    # Construct update
    update_guest_insert = sqlalchemy.update(Guests).where(Guests.guest_id == guest_id).values(
        guest_first_name = guest_first_name,
        guest_middle_initial = guest_middle_initial,
        guest_last_name = guest_last_name,
        guest_phone_number = guest_phone_number,
        guest_email = guest_email,
        guest_state = guest_state,
        guest_birthdate = guest_birthdate
        )
    db.session.execute(update_guest_insert)     # Execute UPDATE statement
    db.session.commit()                         # Execute UPDATE statement
    # return the new guest ID
    return show(guest_id)

#_________________________DELETE____________________________#
# Will not use. If guests are deleted, there will be orphan stays and transactions.
@bp.route('/deleteguest/<int:guest_id>', methods=['DELETE'])
def delete(guest_id:int):
    find_guest = db.session.query(Guests).where(Guests.guest_id == guest_id).all()
    if len(find_guest) == 0:
        return abort(409, 'No guest found with that ID.')
    # Pull vales to report in message
    full_name = ""
    for row in find_guest:
        full_name = row.__dict__['guest_first_name'] + " " + row.__dict__['guest_last_name']
    # Construct delete
    delete_guest = sqlalchemy.delete(Guests).where(Guests.guest_id == guest_id)
    db.session.execute(delete_guest)            # Execute DELETE statement
    db.session.commit()                         # Execute DELETE statement
    # return the new guest ID
    return Response(f"{full_name} (Guest ID {guest_id}) was successfully deleted.", 200)