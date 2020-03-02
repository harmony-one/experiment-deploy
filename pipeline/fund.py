#!/usr/bin/env python3
"""
This is a script to fund accounts without the use of an endpoint.

Note that this script assumes that the faucet key is in the CLI's keystore.

Example usage:
    python3 fund.py --amount 100000 --check
"""

import json
import random
import time
import argparse
import os
from multiprocessing.pool import ThreadPool

from pyhmy import (
    cli,
    util
)
import pyhmy
import requests

faucet_addr = "one1zksj3evekayy90xt4psrz8h6j2v3hla4qwz4ur"  # Assumes that this is in the CLI's keystore.
# From: https://docs.google.com/spreadsheets/d/1AQ3XoP4exPd1cYyqw-EBe5O-lM-Tm54so4ATyFGOaf4/edit#gid=0
accounts = [
    "one1jtmqh0alry2y7zp7z5xfdctal9wv3j6aacqw3z", "one1lqdkdgyhq54gl3cxrskj285pva4q8vqg63lghs",
    "one1psaanp83hshnvmz3hhhw3f6mkw6vpjg7my364c", "one1za9hctc0lknrfaxk7y5ng49rqqu94t9gnqcu9s",
    "one138tm5qkd7jfu95ahnp3sa6p3jkf7ccrgs3uycq", "one1m5ke8dehxl9rxvgn86ue3hwrjp4mqu62wqv6j2",
    "one1n38pm65f3ugwhsmqmc8ftvg9tdqqx30wf23fwf", "one17ye0qjrx0v0f4a47swu4ufufwjnjdp86w4jssm",
    "one16qg9hwmljq3t2gjatn4t4m7cc0dfpg6uadawh9", "one1jss3yu5lse6e86lzhcldcjsqsrfdwf7lp02cct",
    "one1czfecw2gfz0qwn3t7v0hxn79pv005n3mhgpecv", "one1q9h7m59jsdtm50kwgjrzmp832wppej00746uu0",
    "one19y2hg3gg2h5g94gzn4kwmmeps98u8tfd600pe4", "one184aka8nqkdman3nuahwwjtj4kv6au434tae55h",
    "one1wqualr388r6xy00dyk45cfzv0egpwq8juw9jjd", "one1mwkmgr5hhpuh87j0397vgwjkq3dqdpzz75mqha",
    "one1dfxf9ypkcnrhl4x3n4rn745g60zhwn2rch2tz9", "one18wwtc4skjld84uc2k5js2aau8tqatqxd9smqf4",
    "one1zclkcfwuwj59q9qjke489c3fl5kr0rnnes7ew7", "one1v7snzrdtr0a3hm8a9egxefp2g54y0lx5cft00d",
    "one1a7lghww9tseg4ly0jvuqfdqxgdj3lezkupqryd", "one1fcjg7hd46lx82pnqdua43qm6z22e5fntchd59z",
    "one1jvqvxuy4974dzz8xfx42su55q5enljk6rnsz9x", "one1x4ex83vtu3wgcs5d608jdu8cvf56ywzue6cunv",
    "one1g8sxzajdvp5lxk6mnrc49u93wdj499krs462uw", "one16qvlcdw40dmnhkrrm8jmzmjg47nu47mnvupcja",
    "one1p749hfdth7d0fvmrpj9yhg3kt7anrf3zu6k7t8", "one19zhjgwfcp4p405dqe05vahgrkgtj7h6jah7gh4",
    "one1q2mukanpt2q69zn67wmkyna2kcdh8epgpnp9yn", "one1tel4jfz2gyq3hc03juncuewdxhc0m73d0jeqxd",
    "one1kr44eup3652umqhetpqyzpymaelkx93fzgt0yc", "one1yjkdd9yu7rqvqczutp9ycsczy6eql7tkr43ra7",
    "one1cq68dr3y7ca00zlynl7869enkmk6vhz8pu5a2l", "one1m0m6kvq38lchhelc3zuja0gelzer74wlmfut5z",
    "one1tk9jf0z2mjsfexvls482m5n6chx8letf6rwzkc", "one1vnmwjxnjdj2nqg75fq37mcc9cjh7cawnz8vamj",
    "one1hd73n2qrljw42rwlpw8a4k7802rfs8ng8n4t43", "one1zvgpm6wtj4wz59006grs58tdqjuqutypm8p2ze",
    "one1wzvdlpkktq7sgjnktx4xefkv3akcgc5d2jhdzt", "one1jgu6yzps5mztgcrudqj9nc92eat5eh4mylecl8",
    "one1rf34n944n7q38e6vq5lnnvypf9r7vsh6xrjefw", "one104f3twannkn7apeud9d2avgxnls506dwm9sdes",
    "one1xftheh5dda2u5wd7wx7eqr4r2hle6w9zmuayc0", "one16hyeau0afqueyv83lx9a66h606ft6qp8zxgp5n",
    "one12s9cs2rsm09mu6avee4qk6nchllcalsugq3sfv", "one18duxk8aj0vm44fql9f0f43tq37kurgmg6et4dl",
    "one1ef7n0hthw0550czn5lyxujukmnysun6vcdkpxk", "one18z93gj29f72z0g86hhlqvq0zsnfvu4c5x0vqdu",
    "one15kyamluyqvpyfauf6a2l44sl47zzlaw2prtaak", "one1w84szkqw7me7ktesqnn7cvy23v9x596sk6050d",
    "one1lyl3csz88kxm0ytzx7uu3lhslae43ng03faw8d", "one1y2hqe5zfs2cfyxdcjjkrqqy74z7zuuw3hpjmev",
    "one1q9d74x96du90pph28k7d8zq58w67x9lf503g6y", "one1jmjyqzwhgk79mmzjfc5d9c9wac0ukav587av4h",
    "one15h7udqzj54u9sdqf0l8fyl923rrp6p0lgcvn7q", "one152dy0cttlszg78cflx886qmkvzsr0lj6hjdcx5",
    "one1403z2td5l8atchutt8f3eqq260957kwwafx23v", "one1hxzyr0yq4mpj7mq8mt70g2l2q8u2hatrata6sk",
    "one12wh7f2ssm5t7j5kjrha0hruljvr9ylyg53w94z", "one1pq4wd0u8nqwgcqyth7sfmke7ttf09z6mhwck8m",
    "one1mesjf0v03u52gdpdjxcq9mdqlmrfc8d2z2nlg9", "one1rajpgnq6ysjw7g907llhph7uwpq0tdd0mxwhpp",
    "one1cnjjj7wvuyrp6vjvk5mjyjnncwmtdn2scepvy7", "one1qv384xa9jdl8e7ff6hr87a24t4c99mukav0jrd",
    "one1y307cwqr44cedke2jl8fjw2pjrnkfaw8v399dt", "one1qspj8w4r4gdansguuczv820w52cgzyazxqa9gl",
    "one1spshr72utf6rwxseaz339j09ed8p6f8ke370zj", "one1zyxauxquys60dk824p532jjdq753pnsenrgmef",
    "one13v7kgpvc5f36yyglurrzv29rjlw9frqpfg4rcx", "one17lty3l9zdy47kjvycxvlw94ja83kxfak943pgy",
    "one17gjaqdeavntcz8jcv4lwe49n3cct28j2z8sasn", "one1qulnnz3z4r8ky2vw2sfqryzeh2vqjtllhhrkee",
    "one1rshlrwwq0n2ha6cf7wwpy8460sy2l7f945jwd6", "one16uq0nxq7kz9pyw304fhpskj6zggerfx5nqjavv",
    "one1s7fp0jrmd97estwye3mhkp7xsqf42vn5x2sfqy", "one17880eyyzxayejkvdmzlpupprqln8xd2vrl40nn",
    "one1675d7adqu9egn0ehd9fx4f6jmdjfynw3gkr48q", "one170xqsfzm4xdmuyax54t5pvtp5l5yt66u50ctrp",
    "one1zmtegpk65ghgwxzhq9q6hc6tjyj5z0ey8ge6zd", "one1jcxwu3hhkyqrmhx8erx0ys6d7l4fw83kgnd2l7",
    "one1k50mh9hyrdhc68d0m6jkxe509va3r9aaym2l4k", "one1qsl2ae672x2npukfqeg48j2ez2wpsar9knp457",
    "one1u4qlg5zupefpnx8f3h6t4lh3a063287mnk2q6c", "one1fx0kufq4v7v5dp5qlmec9tx0gun3m7g3xywy7n",
    "one18zd6ms8gwxq2hdu635kkhwyctq8qz2vwfcs4pe", "one1es3cl39sat3ma4ug5csdz5mqhx4x6lkjddyeen",
    "one1u6c4wer2dkm767hmjeehnwu6tqqur62gx9vqsd", "one10ph98cj7nveklqyr5ha5l3uk4as2mgy0fek6vm",
    "one1pmqdaw3s29g56333zkmnq03e9mfltfyrn8ggs5", "one18xx3f4gq6n94re4mulkfv97cza9g6vymx0v97t",
    "one14hd35aj7xvuq3vg4grnv2umkxkazcmjq68hpwh", "one1v8a7fcvd9kw3csl8w5p7nghr9fwddz2lcneq50",
    "one1yym297x9elfeqj0ru8pk3qcnhm60e0sgxgc7zd", "one1gjsxmewzws9mt3fn65jmdhr3e4hel9xza8wd6t",
    "one12y9uu2dvwee0vr3gv6xuqvw3scrw92g9krznq0", "one1ugkhsnhvj7dzx7tkk5nuhv0904kslzmqjyvqlq",
    "one1nnpxu3ttrv9lla8zc86prl0sdgngg7aguyx6tw", "one1aqy90q6y52uyexrtw9025052phx6x4qwf558kt",
    "one16ugr8apt45js6yfuyknet433fuylf6kkuwfq24", "one1lf80na267aapczqd52nr3u4mdm5vut3w8nt8p6",
    "one10e9nezqfcq6tkydmfnthq7zdffpclv24ezcy9l", "one10jvjrtwpz2sux2ngktg3kq7m3sdz5p5au5l8c8",
    "one1p89hf0zc594jckj3twz6hdxnth2vlhkfpwe6f0", "one17lkc9skd75r9splsrpkx7zqgl8dqmpcmnj03wu",
    "one1hzzydupatdqzsarj7gurfct7chr9kvdr4txql4", "one1anad0sar6vplr57lpm5uf9kmzgyg6mflmm2fjg",
    "one1pjusejwj3xug79tag35jxyrvl4zj0xma0dpemq", "one1c9h3u72czs6sk755tjyse7x5t70m38ppnkx922",
    "one1nf3cvq2asxrpwjsfpyldexuj38n0cpnezlpd5g", "one1fp63lh5s00tz6k88qsyzufya8nvg29j5eu9up7",
    "one104qvdfdfy9x7l3cskqwpxsgc3rpwlkhumqd7v6", "one1x8vm8v9ggnzuynca8ua340vl3f4xl3u4839wj4",
    "one1x7xh0mn08lc9t47znpf0cwpzjklpdz9n68hdvr", "one15uwuu2kwth75xxspzn7r4ja2cnhtpgqkvnpgh0",
    "one1v83yuvgdzrj9xgx69uwqmmxzhp5ngrczdcn0rf", "one1e7nppdku83jwp9jsuv8x3sehzcus7qpkrdgzw9",
    "one1tezah03evrl5yvld0spe2tmthwt0cfjejyanzm", "one1n35wphjp65wzzjljjtn5ewzm05ad7wlt6yd5nt",
    "one12z78cswezafgrsge63vyyh0df3svm7xnn0r6cw", "one18z2pmpdsh4hlgvv2xqv2kgxjc6f7sxzrpwgu08",
    "one18xfcqu7jf0cq5apweyu5jxr30x9cvetegwqfss", "one10fywus8dupljr2mzr95t0xhx7q4hgwms494x7v",
    "one14xkpgmwuv40rhggkwtt4pz03q3cwdlmnrfmy70", "one19r80atz3tahzkdr45tqgaqh397ga703ay53tyf",
    "one1me80pyjfmjvjxa4my8rlf2n8xuagp9pj2cps3u", "one19h3a3pw9x5xfm3l596gmd7lt3c60ua5c7f6uc4",
    "one162kkvcars3tfez4a4zdph0x8tp87vqqnfc3exz", "one1tq4hy947c9gr8qzv06yxz4aeyhc9vn78al4rmu",
    "one1y5gmmzumajkm5mx3g2qsxtza2d3haq0zxyg47r", "one1qrqcfek6sc29sachs3glhs4zny72mlad76lqcp",
    "one1jg5nxx0z3w573qp23um85wefyaas899jdjtu5d", "one1s2ylrdffm8qep5rfpyx4mst05x9t6z9qryl3rr",
    "one1tm2k28z7scx45y8nkqfzartta93laagj2nk862", "one1dhu02vdsthpe579y7pqf853c0p3jjy5yhvlyet",
    "one1xfwwg9tpf6avwrq74p845zx423f2s6r2hazq32", "one1cg5d67v28m3s0xuph46y8w842yu9dzd7094zr5",
    "one19v48440tce2v75umzv2xwljptapy64jwnyqfde", "one1lp7e7xwrr73d04q0ld7q4h5pe8ykjaztn6z0q5",
    "one1yyj2cu09rjxc5crjawv9zd9skwwf5gefvgxdfa", "one14cnm6prj76xy0qlwnpt55z9snqzj7whrp2kk46",
    "one1d6ru9fmsln6f54mmycjm2wklle7qzgx5wktc2f", "one1zdc4gtq6726v8vhv4tyxuhclhh0fde2gt8k90d",
    "one1c24wur7cc32t5q9m5dy4urq7p5z2pl43u8zaf8", "one17hjsx2gggku2rw5rc2ejj9dxkpyvdkduvd52sg",
    "one1807qqqnqj2qadgzrrzd4nrv8uv6wwqqzfhzc0h", "one1un3xx33847zdv5pdh7knn44zjy0306guu4gt9e",
    "one1qd2huslrjxsaf9tmxvp26zcc4kmtf9h0vghmpf", "one1t7tes48ghzwjgk7llucmcvup2qzvxea4xcxqcw",
    "one1y0v8aa7dgvek6utd0s0ys8maynattpndf6jm0n", "one15e826lcwjmllqzmdhx6adjjqwtyvupzuf02gcl",
    "one17u48r28zwrszxzxycgs3jnrz84sraancvgdss9", "one10ye49y8yegq447zhw6dthq06a5lg59aam57sdm",
    "one1w6ar0m8acfy56gxdpkw7vdx6puaca6lz474slz", "one1n7xkueyljul242fzzgrcyzjtfmlv8f8dr0qwyx",
    "one1gu347x8vg3ga2798mg60lfgdnrqrtp3wujggxj", "one1udw5evf9z7uvpwe02m89egmug5424ydyfk20qd",
    "one13dzry7crj4xrtnvhda695j3rp69cnfyaff0nku", "one18mdedqj6vmr6sgqph9c24649my77p7ssk8t872",
    "one1fuuwny4ehlm7u7eu7fedacje3jp7cdxdktnyze", "one1p328r66tn6uksdy5dnp3phswhqc4r0x9jjhh07",
    "one1nnyyyfqgqcf78flxdrr3r9vjstltj27aaxk29h", "one14qxkp4avq5lqsyvtjf5y47w43t9z7hg46ppqqk",
    "one13f0v6m0y26kuph6fajx8vz3gjwatswnep7l8c7", "one108en4a7axg0pu7yj7zgezsa2x9s8d2me86sc5m",
    "one1nfpnk3la8yqa232y20drf4st0wrq45wcwus509", "one12z765aselgrnxv66rnrr32kz52nga5fmpslw49",
    "one13hhr9hnhnx8c9mydxavq735szk693lupzewca5", "one1jvk4aexr5u0w99sfn4h4wydtej7w9n0cg6vhnf",
    "one1mmlm7wtlzfe8tkf3kkkwm7meevkd2pnhfyr59t", "one14xg2cxw3nyll6laws2xc9zfql3cd3ww2yl5vut",
    "one1f0aptkk4hnlzz6zn93u4k4ulc0rl0a4xf9ylsp", "one12mr00g5l9juwt7xk8p88qhs7v77etmtr7awh6m",
    "one1jdgxud6xxzwcgqnkwccans6mz9ysl8egrvnnqq", "one1tnnncpjdqdjyk7y4d9gaxrg9qk927ueqptmptz",
    "one1gkjn307zmv89vdpk4m0thfkhtgq023pp0hlyuu", "one1zkqtl2hjhzt8lpvv9afyr06a0nn5ctyfa48jgr",
    "one1tsjlkmz2pracxnw0mzj24d9axsx00g9u30f74u", "one1el27y4zutgpth8vm50gwrmtf9jdn0h67kd54mg",
]


def parse_args():
    parser = argparse.ArgumentParser(description='Funding script for a new network')
    parser.add_argument("--timeout", dest="timeout", default=120, help="timeout for each transaction")
    parser.add_argument("--amount", dest="amount", default="1000", type=str, help="Amount to fund each account")
    parser.add_argument("--accounts", dest="accounts", default=None, help="CSV of one1... addresses")
    parser.add_argument("--check", action="store_true", help="Spot check balances after funding")
    parser.add_argument("--force", action="store_true", help="Send transactions even if network appears to be offline")
    p_arg = parser.parse_args()
    p_arg.accounts = accounts if p_arg.accounts is None else [el.strip() for el in p_arg.accounts.split(",")]
    return p_arg


def setup():
    assert hasattr(pyhmy, "__version__")
    assert pyhmy.__version__.major == 20, "wrong pyhmy version"
    assert pyhmy.__version__.minor == 1, "wrong pyhmy version"
    assert pyhmy.__version__.micro >= 14, "wrong pyhmy version, update please"
    env = cli.download("./bin/hmy", replace=True)
    cli.environment.update(env)
    cli.set_binary("./bin/hmy")


def get_nonce(endpoint, address):
    url = endpoint
    payload = "{\"jsonrpc\": \"2.0\", \"method\": \"hmy_getTransactionCount\"," \
              "\"params\": [\"" + address + "\", \"latest\"],\"id\": 1}"
    headers = {
        'Content-Type': 'application/json'
    }
    response = requests.request('POST', url, headers=headers, data=payload, allow_redirects=False, timeout=30)
    return int(json.loads(response.content)["result"], 16)


def get_network_config():
    """
    Strong assumption made about where config is and what it is named.
    """
    config_path = f"{os.path.dirname(os.path.realpath(__file__))}/../configs/benchmark-{os.environ['HMY_PROFILE']}.json"
    assert os.path.isfile(config_path), f"`{config_path}` does not exist!"
    with open(config_path, 'r') as f:
        return json.load(f)


def get_chain_id(config):
    assert "benchmark" in config
    benchmark = config["benchmark"]
    return benchmark["network_type"] if "network_type" in benchmark.keys() else "testnet"


def get_endpoints(config):
    """
    Strong assumption made about where network logs get put after network init.
    """
    assert "benchmark" in config
    assert "shards" in config["benchmark"]
    eps = []
    num_shards = int(config["benchmark"]["shards"])
    shard_log_files = [f"shard{j}.txt" for j in range(num_shards)]
    log_dir = f"{os.path.dirname(os.path.realpath(__file__))}/logs/{os.environ['HMY_PROFILE']}"
    assert os.path.isdir(log_dir)
    for shard_file in shard_log_files:
        shard_log_path = f"{log_dir}/{shard_file}"
        assert os.path.isfile(shard_log_path)
        with open(shard_log_path, 'r') as f:
            ip_list = f.readlines()
        assert len(ip_list) > 0
        eps.append(f"http://{ip_list[0].strip()}:9500/")
    return eps


def fund(shard):
    if shard >= len(endpoints):
        return
    transactions = []
    starting_nonce = get_nonce(endpoints[shard], faucet_addr)
    for j, acc in enumerate(args.accounts):
        transactions.append({
            "from": faucet_addr,
            "to": acc,
            "from-shard": str(shard),
            "to-shard": str(shard),
            "passphrase-string": "",
            "amount": str(args.amount),
            "nonce": str(starting_nonce + j),
        })
    filename = f"./fund{shard}.json"
    with open(filename, 'w') as f:
        json.dump(transactions, f, indent=4)
    command = f"hmy --node={endpoints[shard]} transfer --file {filename} --chain-id {chain_id} --timeout 0"
    print(f"{util.Typgpy.HEADER}Sending funds for shard {shard} ({len(transactions)} transaction(s)){util.Typgpy.ENDC}")
    print(util.Typgpy.HEADER,
          f"Transaction for shard {shard}:\n",
          util.Typgpy.OKGREEN,
          cli.single_call(command, timeout=int(args.timeout) * len(endpoints) * len(args.accounts)),
          util.Typgpy.ENDC)


def get_balance(address):
    """
    Assumes that endpoints provided are ips and that the CLI
    only returns the balances for a specific shard.
    """
    balances = []
    for endpoint in endpoints:
        cli_bal = json.loads(cli.single_call(f"hmy --node={endpoint} balances {address}"))
        assert len(cli_bal) == 1, f"Expect CLI to only return balances for 1 shard. Got: {cli_bal}"
        balances.append(cli_bal[0])
    return balances


if __name__ == "__main__":
    args = parse_args()
    setup()
    assert cli.get_accounts(faucet_addr), f"`{faucet_addr}` is not found in CLI's keystore"
    net_config = get_network_config()
    chain_id = get_chain_id(net_config)
    endpoints = get_endpoints(net_config)
    if not args.force:
        for ep in endpoints:
            assert util.is_active_shard(ep, delay_tolerance=120), f"`{ep}` is not an active endpoint"

    print(f"{util.Typgpy.HEADER}Funding using endpoints: {util.Typgpy.OKGREEN}{endpoints}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.HEADER}Chain-ID: {util.Typgpy.OKGREEN}{chain_id}{util.Typgpy.ENDC}")

    pool = ThreadPool(processes=len(endpoints))
    threads = []
    i = 0
    while i < len(endpoints):
        for _ in range(os.cpu_count()):
            threads.append(pool.apply_async(fund, (i,)))
            i += 1
            if i >= len(endpoints):
                break
    for t in threads:
        t.get()

    print(f"{util.Typgpy.HEADER}Finished sending transactions!{util.Typgpy.ENDC}")
    if args.check:
        print(f"{util.Typgpy.HEADER}Sleeping 90 seconds before checking balances{util.Typgpy.ENDC}")
        time.sleep(90)
        addrs_to_check = random.sample(args.accounts, max(len(args.accounts) // 10, 1))
        print(f"{util.Typgpy.HEADER}Spot checking {len(addrs_to_check)} balances....{util.Typgpy.ENDC}")
        failed = False
        for addr in addrs_to_check:
            for bal in get_balance(addr):
                if float(bal["amount"]) < float(args.amount):
                    print(f"{util.Typgpy.FAIL}{addr} did not get funded!{util.Typgpy.ENDC}")
                    failed = True
                    break
        if not failed:
            print(f"{util.Typgpy.HEADER}Successfully checked {len(addrs_to_check)} balances....{util.Typgpy.ENDC}")
        else:
            exit(-1)
