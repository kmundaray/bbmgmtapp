import datetime
from sqlalchemy.sql import func
from flask_sqlalchemy import SQLAlchemy 

db = SQLAlchemy()

#________________________ORM MODEL_________________________#
# Amenities table
class Amenities(db.Model):
    __tablename__ = 'amenities'
    amenity_id = db.Column(db.Integer, autoincrement=True, primary_key=True)
    amenity_description = db.Column(db.Text, nullable=False)
    amenity_premium = db.Column(db.Numeric, default=0, nullable=False) 
    amenity_deleted = db.Column(db.DateTime(timezone=False), nullable=True)
    amenity_deleted_note = db.Column(db.Text, nullable=True)

    def serialize(self):
        return {
            'amenity_id': self.amenity_id,
            'amenity_description': self.amenity_description,
            'amenity_premium': self.amenity_premium,
            'amenity_deleted': self.amenity_deleted,
            'amenity_deleted_note': self.amenity_deleted_note
        }
    
# Rooms <> Amenities table
rooms_amenities_table = db.Table('rooms_amenities', 
                        db.Column('room_number', db.Text, db.ForeignKey('rooms.room_number'), nullable=False),
                        db.Column('amenity_id', db.Integer, db.ForeignKey('amenities.amenity_id'), nullable=False)
                        )

# Rooms table
class Rooms(db.Model):
    __tablename__ = 'rooms'
    room_number = db.Column(db.Text, primary_key=True)
    room_ready = db.Column(db.Boolean, nullable=False)
    room_available = db.Column(db.DateTime(timezone=False), nullable=True)
    room_type_id = db.Column(db.Integer, db.ForeignKey('room_types.room_type_id'), nullable=False)
    room_fits_crib = db.Column(db.Boolean, nullable=False)
    room_deleted = db.Column(db.DateTime(timezone=False), nullable=True)
    room_deleted_note = db.Column(db.Text, nullable=True)

    # Many to many relationship
    rooms_amenities = db.relationship('Amenities', 
                                    secondary=rooms_amenities_table, 
                                    lazy='subquery', 
                                    backref=db.backref('amenities', lazy=True)
                                    )

    def serialize(self):
        return {
            'room_number': self.room_number,
            'room_ready': self.room_ready,
            'room_available': self.room_available,
            'room_type_id': self.room_type_id,
            'room_fits_crib': self.room_fits_crib,
            'room_deleted': self.room_deleted,
            'room_deleted_note': self.room_deleted_note
        }

# Rate schedules table
# datetime(year, month, day, hour, minute, second, microsecond)
class RateSchedules(db.Model):
    __tablename__ = 'rate_schedules'
    rate_schedule_id = db.Column(db.Integer, autoincrement=True, primary_key=True)
    rate_start_date = db.Column(db.DateTime(timezone=False), default=datetime.datetime(1970,1,1,12,0,0,0), nullable=True)
    rate_end_date = db.Column(db.DateTime(timezone=False), default=datetime.datetime(2099,12,31,11,59,0,0), nullable=True)
    rate_discount = db.Column(db.Numeric, default=0.00, nullable=True)
    rate_premium = db.Column(db.Numeric, default=0.00, nullable=True)

    def serialize(self):
        return {
            'rate_schedule_id': self.rate_schedule_id,
            'rate_start_date': self.rate_start_date,
            'rate_end_date': self.rate_end_date,
            'rate_discount': self.rate_discount,
            'rate_premium': self.rate_premium
        }
    
# Room types <> rates schedules table
room_type_rates_table = db.Table('room_type_rates', 
                        db.Column('room_type_id', db.Integer, db.ForeignKey('room_types.room_type_id'), primary_key=True),
                        db.Column('rate_schedule_id', db.Integer, db.ForeignKey('rate_schedules.rate_schedule_id'), primary_key=True)
                        )

# Room types table
class RoomTypes(db.Model):
    __tablename__ = 'room_types'
    room_type_id = db.Column(db.Integer, autoincrement=True, primary_key=True)
    room_type_bed_type = db.Column(db.Text, unique=True, nullable=False)
    room_type_bed_count = db.Column(db.Integer, nullable=False)
    room_type_max_occupants = db.Column(db.Integer, nullable=False)
    room_type_base_rate = db.Column(db.Numeric, nullable=False)

    # Many to many relationship
    room_type_rates = db.relationship('RateSchedules', 
                                            secondary=room_type_rates_table, 
                                            lazy='subquery', 
                                            backref=db.backref('rate_schedules', 
                                            lazy=True)  # Attribute that would return back all the rate schedules
                                            )

    def serialize(self):
        return {
            'room_type_id': self.room_type_id,
            'room_type_bed_type': self.room_type_bed_type,
            'room_type_bed_count': self.room_type_bed_count,
            'room_type_max_occupants': self.room_type_max_occupants,
            'room_type_base_rate': self.room_type_base_rate
        }

# Stays table
class Stays(db.Model):
    __tablename__ = 'stays'
    stay_id = db.Column(db.Integer, autoincrement=True, primary_key=True)
    room_number = db.Column(db.Text, db.ForeignKey('rooms.room_number'), nullable=False)
    stay_holder_guest_id = db.Column(db.Integer, nullable=False)
    stay_check_in = db.Column(db.DateTime(timezone=False), nullable=False)
    stay_actual_check_in = db.Column(db.DateTime(timezone=False), nullable=True)
    stay_check_out = db.Column(db.DateTime(timezone=False), nullable=False)
    stay_actual_check_out = db.Column(db.DateTime(timezone=False), nullable=True)
    stay_occupant_count = db.Column(db.Integer, default=1, nullable=False)
    stay_duration = db.Column(db.Integer, nullable=False)
    stay_status = db.Column(db.Text, nullable=False)
    stay_cancel_date = db.Column(db.DateTime(timezone=False), nullable=True)
    stay_created_date = db.Column(db.DateTime(timezone=False), server_default=func.now(), nullable=True)
    stay_last_updated = db.Column(db.DateTime(timezone=False), server_default=func.now(), onupdate=func.now(), nullable=True)

    def serialize(self):
        return {
            'stay_id': self.stay_id,
            'room_number': self.room_number,
            'stay_holder_guest_id': self.stay_holder_guest_id,
            'stay_check_in': self.stay_check_in,
            'stay_actual_check_in': self.stay_actual_check_in,
            'stay_check_out': self.stay_check_out,
            'stay_actual_check_out': self.stay_actual_check_out,
            'stay_occupant_count': self.stay_occupant_count,
            'stay_duration': self.stay_duration,
            'stay_status': self.stay_status,
            'stay_cancel_date': self.stay_cancel_date,
            'stay_created_date': self.stay_created_date,
            'stay_last_updated': self.stay_last_updated
        }

# Guests <> stays table
guests_stays_table = db.Table('guests_stays', 
                        db.Column('guest_id', db.Integer, db.ForeignKey('guests.guest_id'), primary_key=True),
                        db.Column('stay_id', db.Integer, db.ForeignKey('stays.stay_id'), primary_key=True),
                        db.Column('guest_stay_active', db.Boolean, nullable=False)
                        )

# Guests table
class Guests(db.Model):
    __tablename__ = 'guests'
    guest_id = db.Column(db.Integer, autoincrement=True, primary_key=True)
    guest_first_name = db.Column(db.Text, nullable=False)
    guest_middle_initial = db.Column(db.String(1), nullable=True) # Changed from Text on 2/27/2023
    guest_last_name = db.Column(db.Text, nullable=False)
    guest_phone_number = db.Column(db.Text, nullable=False)
    guest_email = db.Column(db.Text, nullable=True)
    guest_state = db.Column(db.String(2), nullable=True)
    guest_birthdate = db.Column(db.Date, nullable=False)
    guest_created_date = db.Column(db.DateTime(timezone=False), server_default=func.now(), nullable=True)
    guest_last_updated = db.Column(db.DateTime(timezone=False), server_default=func.now(), onupdate=func.now(), nullable=True)

    # Many to many relationship
    guests_stays = db.relationship('Stays', 
                                            secondary=guests_stays_table, 
                                            lazy='subquery', 
                                            backref=db.backref('stays', 
                                            lazy=True)
                                            )
    def serialize(self):
        return {
            'guest_id': self.guest_id,
            'guest_first_name': self.guest_first_name,
            'guest_middle_initial': self.guest_middle_initial,
            'guest_last_name': self.guest_last_name,
            'guest_phone_number': self.guest_phone_number,
            'guest_email': self.guest_email,
            'guest_state': self.guest_state,
            'guest_birthdate': self.guest_birthdate,
            'guest_created_date': self.guest_created_date,
            'guest_last_updated': self.guest_last_updated
        }

# Transaction types table
class TransactionTypes(db.Model):
    __tablename__ = 'transaction_types'
    transaction_type_id = db.Column(db.Integer, autoincrement=True, primary_key=True)
    transaction_type_description = db.Column(db.Text, nullable=False)

    def serialize(self):
        return {
            'transaction_type_id': self.transaction_type_id,
            'transaction_type_description': self.transaction_type_description,
        }

# Guest transactions table
class GuestTransactions(db.Model):
    __tablename__ = 'guest_transactions'
    guest_transaction_id = db.Column(db.Integer, autoincrement=True, primary_key=True)
    transaction_type_id = db.Column(db.Integer, db.ForeignKey('transaction_types.transaction_type_id'), nullable=False)
    guest_id = db.Column(db.Integer, db.ForeignKey('guests.guest_id'), nullable=False)
    guest_transaction_charge = db.Column(db.Numeric, default=0.00, nullable=False)
    guest_transaction_payment = db.Column(db.Numeric, default=0.00, nullable=False)
    guest_transaction_date = db.Column(db.DateTime(timezone=False), default=func.now(), nullable=False)
    guest_transaction_description = db.Column(db.Text, nullable=False)
    guest_transaction_deleted = db.Column(db.DateTime(timezone=False), default=None, nullable=True)

    def serialize(self):
        return {
            'guest_transaction_id': self.guest_transaction_id,
            'transaction_type_id': self.transaction_type_id,
            'guest_id': self.guest_id,
            'guest_transaction_charge': self.guest_transaction_charge,
            'guest_transaction_payment': self.guest_transaction_payment,
            'guest_transaction_date': self.guest_transaction_date,
            'guest_transaction_description': self.guest_transaction_description,
            'guest_transaction_deleted': self.guest_transaction_deleted
        }

# Transaction <> Balances table
transactions_to_balances_table = db.Table('transactions_to_balances', 
                        db.Column('guest_transaction_id', db.Integer, db.ForeignKey('guest_transactions.guest_transaction_id'), primary_key=True),
                        db.Column('stay_balance_id', db.Integer, db.ForeignKey('stay_balances.stay_balance_id'), primary_key=True),
                        )

# Stay balances table
class StayBalances(db.Model):
    __tablename__ = 'stay_balances'
    stay_balance_id = db.Column(db.Integer, autoincrement=True, primary_key=True)
    stay_total_charges = db.Column(db.Numeric, default=0.00, nullable=False)
    stay_total_payments = db.Column(db.Numeric, default=0.00, nullable=False)
    stay_balance = db.Column(db.Numeric, default=0.00, nullable=False)
    stay_id = db.Column(db.Integer, db.ForeignKey('stays.stay_id'), nullable=False)

    def serialize(self):
        return {
            'stay_balance_id': self.stay_balance_id,
            'stay_total_charges': self.stay_total_charges,
            'stay_total_payments': self.stay_total_payments,
            'stay_balance': self.stay_balance,
            'stay_id': self.stay_id
        }

    # Many to many relationship
    transactions_to_balances = db.relationship('GuestTransactions', 
                                            secondary=transactions_to_balances_table, 
                                            lazy='subquery', 
                                            backref=db.backref('guests_transactions', lazy=True)
                                            )
    
#________________TRIGGERS THAT COULDNT ADD IN ORM MODEL_____________________#
# The triggers were added directly into the PostgreSQL database

