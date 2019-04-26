#!/usr/bin/python

"""
Harmony S3 log Analysis

Author: Andy Bo Wu
Date: Apr 9, 2019



==== USAGE ====

Finding `panic` ERROR entry on a DAY
$python3 LogAnalysis.py 2019/04/17

Finding `panic` ERROR entry on a month
$python3 LogAnalysis.py 2019/04

Finding `panic` ERROR entry on a year
(Ideally we should not do so, cuz the total size of the log files will be HUGE!!)
$python3 LogAnalysis.py 2019

==== VERSION ====

1. APR 9, 2019
    * Created the script

2. APR 16, 2019
    * Added an argument parameter such that this script can be invoked in cmd
    * Re-defined the S3 output folder such that all test results are stored in the

3. APR 25, 2019 by Yelin
    * Little code refactoring
    * Use python2, python3 is not installed on Jenkins.
    * Get query results if needed.
    * Output query results to local file so it can be used for notification.

"""
from __future__ import print_function

import boto3
import sys
import time

# Function for executing athena queries
def run_query(query, database, s3_output, need_results=False):
    client = boto3.client('athena', region_name='us-west-2')
    print('Executing query: ' + query)
    response = client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={
            'Database': database
        },
        ResultConfiguration={
            'OutputLocation': s3_output,
        }
    )

    results = None
    if need_results:
        while True:
            time.sleep(5)
            status = client.get_query_execution(QueryExecutionId=response['QueryExecutionId'])
            if status['QueryExecution']['Status']['State'] in ['SUCCEEDED', 'FAILED']:
                break
        results = client.get_query_results(QueryExecutionId=response['QueryExecutionId'])
    print('Execution ID: ' + response['QueryExecutionId'])

    return (response, results)

def parse_logs(database, table, keyword, pvar, s3_input, s3_output):
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

    # create table
    queries = [drop_table, create_table]
    for q in queries:
        run_query(q, database, s3_output)

    # Query definitions
    query = "SELECT %s, * FROM %s.%s where FileName LIKE %s;" % (pvar, database, table, keyword)
    (response, results) =  run_query(query, database, s3_output, True)

    ret = 0
    with open('result.txt', 'w') as f:
        if results and len(results['ResultSet']['Rows']) > 1:
            ret = len(results['ResultSet']['Rows']) - 1
            print("%d match found for keyword %s on %s" % (len(results['ResultSet']['Rows'])-1, keyword, sys.argv[1]), file=f)
            for r in results['ResultSet']['Rows'][1:]:
                print("%s in log: %s" % (keyword, r['Data'][0]['VarCharValue']), file=f)
        else:
            print("no match found for keyword %s on %s" % (keyword, sys.argv[1]), file=f)
    return ret

def main():
    # Athena configuration

    s3_input = 's3://harmony-benchmark/logs/' + sys.argv[1]
    print("s3_input path: " + s3_input)

    s3_output = 's3://athena-harmony-benchmark/logs/' + sys.argv[1]
    print("s3_output path:" + s3_output)

    # Athena database and table definition
    database = 'harmony'

    # create database if not exist
    create_database = "CREATE DATABASE IF NOT EXISTS %s;" % (database)
    run_query(create_database, database, s3_output)

    ret = 0
    # run queries: find panic
    table = 'FindingPanic4'
    keyword = "'panic%'"
    pvar = '"$path"'
    ret += parse_logs(database, table, keyword, pvar, s3_input, s3_output)

    sys.exit(ret)

if __name__ == "__main__":
    main()
