from flask import Blueprint, jsonify, abort 
from ..models import db , StayBalances

bp = Blueprint('StayBalances', __name__, url_prefix='/transactionbalances')

#_________________________GET____________________________#
@bp.route('', methods=['GET'])    # Decorator takes path and list of HTTP verbs
def index():
    stay_balances = StayBalances.query.all()    # ORM performs SELECT query
    result = []
    for u in stay_balances:
        result.append(u.serialize())   # Build list of Users as dictionaries
    return jsonify(result)             # Returns a JSON response

@bp.route('/<int:stay_balance_id>', methods=['GET'])
def show(stay_balance_id: int):
    u = StayBalances.query.get(stay_balance_id)
    if u is None:
        return abort(404, 'Balance ID not found.')
    return jsonify(u.serialize())

@bp.route('/<int:stay_balance_id>/transactions', methods=['GET'])
def likes(stay_balance_id: int):
    u = StayBalances.query.get(stay_balance_id)
    if u is None:
        return abort(404, 'Balance ID not found.')
    # Check if stays exist
    if u.transactions_to_balances is None:
        return abort(404, 'No transactions found for this balance ID.')
    # Return stays    
    result = []
    for s in u.transactions_to_balances:
        result.append(s.serialize())
    return jsonify(result)
