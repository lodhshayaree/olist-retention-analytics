import os
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

load_dotenv()


def get_engine():
    url = URL.create(
        'postgresql+psycopg2',
        username=os.getenv('DB_USER', 'postgres'),
        password=os.getenv('DB_PASSWORD', ''),
        host=os.getenv('DB_HOST', 'localhost'),
        port=int(os.getenv('DB_PORT', '5432')),
        database=os.getenv('DB_NAME', 'olist'),
    )
    return create_engine(url)


def read_sql(query):
    # Run a SQL query and return the result as a pandas table (DataFrame).
    with get_engine().connect() as conn:
        return pd.read_sql(text(query), conn)
        