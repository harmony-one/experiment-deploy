#!/usr/bin/env bash

# Amounts and accounts are from: https://harmony.one/keys2

rm -rf ./bin  # Clear existing CLI, assuption made of where fund.py stores CLI binary.
echo "~~Funding Team~~"
python3 -u fund.py --amount 3384800 --check --shards "0" --yes --accounts "one1kvfsza4u4e5ml6qv92j2pmsal2am9mcv9u4g83, one1ujljr2nuymtxm0thjm32f64xsa9uzs54swreyw, one1p5hv9qv90dyrag9fj3wzrvvrs273ypcq8mz7zn, one1egemh5e9xjy3x8d3cq0kq7mw4sw4jjwgkc7axs, one1y5n7p8a845v96xyx2gh75wn5eyhtw5002lah27, one10qq0uqa4gvgdufqjph89pp7nj6yeatz94xdjrt, one1j33qtvx86j4ugy0a8exwwhtldm5wv4daksrwsl, one1fv5ku7szkm60h4j4tcd2yanvjaw2ym3ugnls33, one1rcv3chw86tprvhpw4fjnpy2gnvqy4gp4fmhdd9, one1wh4p0kuc7unxez2z8f82zfnhsg4ty6dupqyjt2, one19gr02mxulyatwz4lpuhl2z3pezwx62xg2uchtg, one1t0x76npc295gpsv64xzyf3qk9zml7a099v4cqj, one1k7hgd27qggp8wcmn7n5u9sdhrjy7d2ed3m3c75, one1xw94y2z7uc2qynyumze2ps8g4nq2w2qtzmdn8r, one18vn078vyp5jafma8q7kek6w0resrgex9yufqws, one1tpxl87y4g8ecsm6ceqay49qxyl5vs94jjyfvd9, one103q7qe5t2505lypvltkqtddaef5tzfxwsse4z7, one1tewvfjk0d4whmajpqvcvzfpx6wftrh0gagsa7n, one1tnnncpjdqdjyk7y4d9gaxrg9qk927ueqptmptz, one1337twjy8nfcwxzjqrc6lgqxxhs0zeult242ttw, one15ap4frdwexw2zcue4hq5jjad5jjzz678urwkyw, one12sujm2at8j8terh7nmw2gnxtrmk74wza3tvjd9, one1wxlm29z9u08udhwuulgssnnh902vh9wfnt5tyh, one1m6j80t6rhc3ypaumtsfmqwjwp0mrqk9ff50prh, one10fjqteq6q75nm62cx8vejqsk7mc8t5hle8ewnl, one1vzsj3julf0ljcj3hhxuqpu6zvadu488zfrtttz, one1marnnvc8hywmfxhrc8mtpjkvvdt32x9kxtwkvv"
echo "~~Funding P-Ops"
python3 -u fund.py --amount 1184680 --check --shards "0" --yes --accounts "one1u6c4wer2dkm767hmjeehnwu6tqqur62gx9vqsd, one1t4p6x5k7zw59kers7hwmjh3kymj0n6spr02qnf, one1s7fp0jrmd97estwye3mhkp7xsqf42vn5x2sfqy, one10jvjrtwpz2sux2ngktg3kq7m3sdz5p5au5l8c8, one1km7xg8e3xjys7azp9f4xp8hkw79vm2h3f2lade, one1c9h3u72czs6sk755tjyse7x5t70m38ppnkx922, one170xqsfzm4xdmuyax54t5pvtp5l5yt66u50ctrp, one1vfqqagdzz352mtvdl69v0hw953hm993n6v26yl, one1gjsxmewzws9mt3fn65jmdhr3e4hel9xza8wd6t, one1mpzx5wr2kmz9nvkhsgj6jr6zs87ahm0gxmhlck, one1la07f5wduc3379ffzlpqrl4rcvlchyvtwf3uyj"
echo "~~Funding P-Volunteer"
python3 -u fund.py --amount 1184680 --check --shards "0" --yes --accounts "one15x96zu9nvsyrepq3ma3epszjnc5vwpphrq239p, one17tj2jjehdlg8xfgp48xpeyqur2qf6nvs88jvyu, one1dcmp24uqgwszcvmm8n6r5dvhqhuukdj86pkg6n, one1ekup98s5tqxtr5hdzsz664cfy579jpq6w5smrr, one1mpzx5wr2kmz9nvkhsgj6jr6zs87ahm0gxmhlck, one1k7hgd27qggp8wcmn7n5u9sdhrjy7d2ed3m3c75, one1hpxxxnqp5epvs2ktzdft24q39r4pttywkmt3cy, one1gm8xwupd9e77ja46eaxv8tk4ea7re5zknaauvq, one12d5a58rcpyf8chlcd2my8r8ns572uppetmxqrx, one1wxlm29z9u08udhwuulgssnnh902vh9wfnt5tyh, one1dsy63tatz7avdrl24y5clramvgur9hsarglcdl"
echo "~~Funding Partners~~"
python3 -u fund.py --amount 1974467 --check --shards "0" --yes --accounts "one1a8avzz3hcvhfrh2tp7rdprpvwt838y9um9c2q7"
echo "~~Funding Hackers~~"
python3 -u fund.py --amount 2850113 --check --shards "0" --yes --accounts ""
echo "~~Funding Community~~"
python3 -u fund.py --amount 709050 --check --shards "0" --yes --accounts ""
echo "~~Funding Foundational Nodes~~"
python3 -u fund.py --amount 4709012 --check --shards "0" --yes --accounts "one19cuygr776f7j9ep97hjm0np9ay6nus9w5msy0n, one1rhkl7c0jz09c9ffp2pncyr4uwamfpmcr83ufkr, one17d60e5nvjnzechwl56y38ze6w49wejhtanncra, one1jjq5pl4le0fhhu3n2znkkt9tydrzjcyzaljtnl, one1wz9fmjrwua3le0c8qxv058p3wpdg4ctjyc3ha4, one1leh5rmuclw5u68gw07d86kqxjd69zuny3h23c3, one14shlkfq00yfmf3r4gglt0hqfcxrgx7ysmsz832, one1u0sa36a28dq4fufc9vs9hlnkjsrxr9k67w5ysu, one1uvt0yl7dxyt9rh37gzm49vy3pgf0c3aud4k5p5"
echo "Done funding!"