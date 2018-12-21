# Introduction

This document is the detailed explanation of the txgen json file format.
We use wallet application to emulate transactions to the blockchain.

## description
* string
* the description of the json file, purpose of this test setup.

## profile
* string
* the name of the json configuration, should be identical to the -suffix of the json file name.

## init
this section describes the initialization setup of the test.

### init.reset
* true/false
* reset all the accounts db in this setup.

### init.account_db
* string
* the name of the account db file.

## accounts
* list of account
* this section has a list of existing accounts

### account.name
* string
* the alias of the account

### account.address
* hash
* the 0x... hash address of the account. The address can be queried in the blockchain explorer.

### account.prikey
* string
* the private key of the account. It will be imported into the wallet app to recreate the account.

## wallet
this section describes the wallet setup.

### wallet.account
* integer 
* number of accounts generated in wallet

### wallet.faucet
* true/false
* request free tokens from faucet or not

## transactions
this section has a list of the transactions to be generated

### transaction.from
* string
* the name of the from address of the transaction
* '*' represents all/any accounts generated in wallet section
* '%' represents a random accounts generated in the wallet section

### transaction.to
* string
* the name of the to address of the transaction
* '*' represents all/any accounts generated in wallet section
* '%' represents a random accounts generated in the wallet section

### transaction.amount
* numeric value
* the amount of token in this transaction
* '0' represents a random number

### transaction.delay
* numeric value in second
* the amount of delay after each transaction

### transaction.count
* integer
* the number of the same transaction

### transaction.parallel
* integer
* the number of transaction can execute in parallel

# Sample
[Txgen Beat Configuration](https://github.com/harmony-one/experiment-deploy/blob/master/configs/txgen-beat.json)
