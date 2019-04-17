"""
Harmony S3 log Analysis

Author: Andy Bo Wu
Date: Apr 9, 2019



==== USAGE ====

Finding `panic` ERROR entry on a DAY 
$python3 LogAnalysis.py 2019/04/17

Finding `panic` ERROR entry on a month
$python3 LogAnalysis.py 2019/04

Fing `panic` ERROR entry on a year 
(Ideally we should not do so, cuz the total size of the log files will be HUGE!!)
$python3 LogAnalysis.py 2019

==== VERSION ====

1. APR 9, 2019     
    * Created the script

2. APR 16, 2019    
    * Added an argument parameter such that this script can be invoked in cmd
    * Re-defined the S3 output folder such that all test results are stored in the




"""

# !/usr/bin/env python3
import boto3
import sys


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

#s3_input = 's3://harmony-benchmark/logs/20190402.042758/validator/ForAndyTest/'
#s3_input = 's3://harmony-benchmark/logs/20190417.030315/validator/'
s3_input = 's3://harmony-benchmark/logs/' + sys.argv[1]
print("s3_input path: ", s3_input)

# https://stackoverflow.com/questions/45313763/athena-query-fails-with-boto3-s3-location-invalid?rq=1
s3_output = 's3://athena-harmony-benchmark/logs/' + sys.argv[1]
#s3_output = 's3://athena-harmony-benchmark/logs/2019/04/17'
print("s3_output path:", s3_output)


database = 'harmony'
table = 'FindingPanic4'
keyword = "'panic%'"
pvar = '"$path"'

# Athena database and table definition
create_database = "CREATE DATABASE IF NOT EXISTS %s;" % (database)
drop_table = "DROP TABLE IF EXISTS %s.%s;" %(database, table)
create_table = \
    """
    CREATE EXTERNAL TABLE IF NOT EXISTS %s.%s (
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
queries = [create_database, drop_table, create_table, query_1]
for q in queries:
    print("Executing query: %s" % (q))
    res = run_query(q, database, s3_output)
