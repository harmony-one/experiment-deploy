import json
import random
import argparse

from pyhmy import cli
import pyhmy
import requests

# From: https://docs.google.com/spreadsheets/d/1AQ3XoP4exPd1cYyqw-EBe5O-lM-Tm54so4ATyFGOaf4/edit#gid=0
accounts = [
    "one13v7kgpvc5f36yyglurrzv29rjlw9frqpfg4rcx",
    "one17lty3l9zdy47kjvycxvlw94ja83kxfak943pgy",
    "one17gjaqdeavntcz8jcv4lwe49n3cct28j2z8sasn",
    "one1qulnnz3z4r8ky2vw2sfqryzeh2vqjtllhhrkee",
    "one1rshlrwwq0n2ha6cf7wwpy8460sy2l7f945jwd6",
    "one16uq0nxq7kz9pyw304fhpskj6zggerfx5nqjavv",
    "one1s7fp0jrmd97estwye3mhkp7xsqf42vn5x2sfqy",
    "one17880eyyzxayejkvdmzlpupprqln8xd2vrl40nn",
    "one1675d7adqu9egn0ehd9fx4f6jmdjfynw3gkr48q",
    "one170xqsfzm4xdmuyax54t5pvtp5l5yt66u50ctrp",
    "one1zmtegpk65ghgwxzhq9q6hc6tjyj5z0ey8ge6zd",
    "one1jcxwu3hhkyqrmhx8erx0ys6d7l4fw83kgnd2l7",
    "one1k50mh9hyrdhc68d0m6jkxe509va3r9aaym2l4k",
    "one1qsl2ae672x2npukfqeg48j2ez2wpsar9knp457",
    "one1u4qlg5zupefpnx8f3h6t4lh3a063287mnk2q6c",
    "one1fx0kufq4v7v5dp5qlmec9tx0gun3m7g3xywy7n",
    "one18zd6ms8gwxq2hdu635kkhwyctq8qz2vwfcs4pe",
    "one1es3cl39sat3ma4ug5csdz5mqhx4x6lkjddyeen",
    "one1u6c4wer2dkm767hmjeehnwu6tqqur62gx9vqsd",
    "one10ph98cj7nveklqyr5ha5l3uk4as2mgy0fek6vm",
    "one1pmqdaw3s29g56333zkmnq03e9mfltfyrn8ggs5",
    "one18xx3f4gq6n94re4mulkfv97cza9g6vymx0v97t",
    "one14hd35aj7xvuq3vg4grnv2umkxkazcmjq68hpwh",
    "one1v8a7fcvd9kw3csl8w5p7nghr9fwddz2lcneq50",
    "one1yym297x9elfeqj0ru8pk3qcnhm60e0sgxgc7zd",
    "one1gjsxmewzws9mt3fn65jmdhr3e4hel9xza8wd6t",
    "one12y9uu2dvwee0vr3gv6xuqvw3scrw92g9krznq0",
    "one1ugkhsnhvj7dzx7tkk5nuhv0904kslzmqjyvqlq",
    "one1nnpxu3ttrv9lla8zc86prl0sdgngg7aguyx6tw",
    "one1aqy90q6y52uyexrtw9025052phx6x4qwf558kt",
    "one16ugr8apt45js6yfuyknet433fuylf6kkuwfq24",
    "one1lf80na267aapczqd52nr3u4mdm5vut3w8nt8p6",
    "one10e9nezqfcq6tkydmfnthq7zdffpclv24ezcy9l",
    "one10jvjrtwpz2sux2ngktg3kq7m3sdz5p5au5l8c8",
    "one1p89hf0zc594jckj3twz6hdxnth2vlhkfpwe6f0",
    "one17lkc9skd75r9splsrpkx7zqgl8dqmpcmnj03wu",
    "one1hzzydupatdqzsarj7gurfct7chr9kvdr4txql4",
    "one1anad0sar6vplr57lpm5uf9kmzgyg6mflmm2fjg",
    "one1pjusejwj3xug79tag35jxyrvl4zj0xma0dpemq",
    "one1c9h3u72czs6sk755tjyse7x5t70m38ppnkx922",
    "one1nf3cvq2asxrpwjsfpyldexuj38n0cpnezlpd5g",
    "one1fp63lh5s00tz6k88qsyzufya8nvg29j5eu9up7",
    "one104qvdfdfy9x7l3cskqwpxsgc3rpwlkhumqd7v6",
    "one1x8vm8v9ggnzuynca8ua340vl3f4xl3u4839wj4",
    "one1x7xh0mn08lc9t47znpf0cwpzjklpdz9n68hdvr",
    "one15uwuu2kwth75xxspzn7r4ja2cnhtpgqkvnpgh0",
    "one1v83yuvgdzrj9xgx69uwqmmxzhp5ngrczdcn0rf",
    "one1e7nppdku83jwp9jsuv8x3sehzcus7qpkrdgzw9",
    "one1tezah03evrl5yvld0spe2tmthwt0cfjejyanzm",
    "one1n35wphjp65wzzjljjtn5ewzm05ad7wlt6yd5nt"
]
endpoints = [
    "https://api.s0.b.hmny.io/",
    "https://api.s1.b.hmny.io/",
    "https://api.s2.b.hmny.io/",
]
chain_id = "testnet"
timeout = 120


def parse_args():
    parser = argparse.ArgumentParser(description='fund')
    parser.add_argument("key", help="Private key for faucet account", type=str)
    parser.add_argument("addr", help="Address of account of private key", type=str)
    parser.add_argument("--timeout", dest="timeout", default=120)
    parser.add_argument("--amount", dest="amount", default="1000", type=str, help="Amount to fund each account")
    parser.add_argument("--endpoints", dest="endpoints", default=None)
    parser.add_argument("--chain_id", dest="chain_id", default=None)
    parser.add_argument("--accounts", dest="accounts", default=None)
    return parser.parse_args()


def get_nonce(endpoint, address):
    """
    Internal get nonce to bypass subprocess latency of calling CLI.
    """
    url = endpoint
    payload = "{\"jsonrpc\": \"2.0\", \"method\": \"hmy_getTransactionCount\"," \
              "\"params\": [\"" + address + "\", \"latest\"],\"id\": 1}"
    headers = {
        'Content-Type': 'application/json'
    }
    response = requests.request('POST', url, headers=headers, data=payload, allow_redirects=False, timeout=30)
    return int(json.loads(response.content)["result"], 16)


def setup():
    assert hasattr(pyhmy, "__version__")
    assert pyhmy.__version__.major == 20, "wrong pyhmy version"
    assert pyhmy.__version__.minor == 1, "wrong pyhmy version"
    assert pyhmy.__version__.micro >= 14, "wrong pyhmy version, update please"
    env = cli.download("./bin/hmy", replace=False)
    cli.environment.update(env)
    cli.set_binary("./bin/hmy")


if __name__ == "__main__":
    args = parse_args()
    args.endpoints = endpoints if args.endpoints is None else [el.strip() for el in args.endpoints.split(",")]
    args.chain_id = chain_id if args.chain_id is None else args.chain_id
    args.accounts = accounts if args.accounts is None else [el.strip() for el in args.accounts.split(",")]
    setup()

    transactions = []
    for i in range(len(args.endpoints)):
        starting_nonce = get_nonce(args.endpoints[i], args.addr)
        for j, acc in enumerate(args.accounts):
            transactions.append({
                "from": args.addr,
                "to": acc,
                "from-shard": str(i),
                "to-shard": str(i),
                "passphrase-string": "",
                "amount": str(args.amount),
                "nonce": str(starting_nonce + j),
            })

    filename = "./fund.json"
    with open(filename, 'w') as f:
        json.dump(transactions, f, indent=4)

    keystore_name = f"FAUCET_KEY_{random.randint(0,1e9)}"

    print("Imported keys...")
    cli.single_call(f"hmy keys import-private-key {args.key} {keystore_name}")

    command = f"hmy --node={args.endpoints[0]} transfer --file {filename} --chain-id {args.chain_id}"
    print("Sending transactions...")
    print(cli.single_call(command, timeout=int(args.timeout)*len(args.endpoints)*len(args.accounts)))
    cli.single_call(f"hmy keys remove {keystore_name}")
