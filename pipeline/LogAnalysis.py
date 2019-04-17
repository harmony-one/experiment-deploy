"""
Harmony S3 log Analysis

Author: Andy Bo Wu
Date: Apr 9, 2019

VERSION:
APR 9, 2019     Created the script

"""

# !/usr/bin/env python3
import boto3


# Function for executing athena queries

def run_query(query, database, s3_output):
    client = boto3.client('athena')
    response = client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={
            'Database': database
        },
        ResultConfiguration={
            'OutputLocation': s3_output,
        }
    )
    print('Execution ID: ' + response['QueryExecutionId'])
    return response


# Athena configuration
s3_input = 's3://harmony-benchmark/logs/20190402.042758/validator/ForAndyTest/'
# https://stackoverflow.com/questions/45313763/athena-query-fails-with-boto3-s3-location-invalid?rq=1
s3_ouput = 's3://athena-harmony-benchmark/logs/20190402.042758/validator/ForAndyTest/'
database = 'harmony'
table = 'FindingPanic4'
keyword = "'panic%'"
pvar = '"$path"'

# Athena database and table definition
create_database = "CREATE DATABASE IF NOT EXISTS %s;" % (database)
create_table = \
    """CREATE EXTERNAL TABLE IF NOT EXISTS %s.%s (
    `FileName` string,
    `col2` string,    
    `col3` string,
    `col4` string,
    `col5` string,
    `col6` string        
     )
     ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe'
     WITH SERDEPROPERTIES (
       'serialization.format' = ' ',
        'field.delim' = ' ',
        'collection.delim' = 'undefined',
        'mapkey.delim' = 'undefined'
     ) LOCATION '%s'
     TBLPROPERTIES ('has_encrypted_data'='false');""" % (database, table, s3_input)

# Query definitions
query_1 = "SELECT %s, * FROM %s.%s where FileName LIKE %s;" % (pvar, database, table, keyword)
print(create_database)
print(create_table)
print(query_1)
# query_2 = "SELECT * FROM %s.%s where age > 30;" % (database, table)
# Execute all queries
queries = [create_database, create_table, query_1]
for q in queries:
    print("Executing query: %s" % (q))
    res = run_query(q, database, s3_ouput)
