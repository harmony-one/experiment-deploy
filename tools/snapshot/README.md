# Network Snapshot 
`snapshot.py` is an orchestrator script to snapshot the network using a given config. 
Ideally, the script would be called every hour (or whatever desired interval) to ensure minimal 
rollback should the network suffer a network wide corruption of the DBs. Moreover, it provides
a relatively updated snapshot that nodes (internal or external) can quickly sync to. 

## Install
This script will require **python 3.6** or higher. 
Dependencies can be installed with the following command while in this directory:
```bash
python3 -m pip install -r requirements.txt --user
```

## Running Snapshot
1) Define your config JSON file. You can reference the example config file (`testnet_config.json`).
2) Run the snapshot script using the following command: 
```bash
chmod +x ./snapshot.py
./snapshot.py --config ./config.json
```
3) If you wish to sync the snapshot to the configured bucket, do so with the following command:
```bash
chmod +x ./snapshot.py
./snapshot.py --config ./config.json --bucket-sync
```
4) You can debug the script or check its progress by inspecting the log file called `snapshot.log` in the same directory as `snapshot.py`.
> It is recommended to set up a cronjob to call this script evey set interval. For example, to run the script every
> hour, execute the following command (assuming you are in this directory) to setup the cronjob:
> ```bash
> echo "0 * * * * $(pwd)/snapshot.py --config $(pwd)/config.json --bucket-sync" > cronjob && crontab cronjob && crontab -l
> ```

## Config Documentation

The config file is a JSON file with the following 4 root keys: `ssh_key`, `machines`, `rsync`, `condition`, and `pager_duty`.
Below is a detailed description of what each file is.

### `ssh_key`
> Specify all things related to SSH-ing into snapshot machines

| Key                  | Value-type | Value-description|
| :-------------------:|:----------:| :----------------|
| `use_existing_agent` | boolean    | [**Required**] Specify if script is to use existing SSH agent |
| `path`               | string     | [**Required**] Path to the .pem file used to SSH into configured machines |
| `passphrase`         | string     | [**Required**] Passphrase to the .pem file, or `null` if no passphrase |

### `machines`
> Specify all things related to snapshot machines. Note that this filed is a **JSON Array** where each element
> contains the following field.

| Key              | Value-type | Value-description|
| :---------------:|:----------:| :----------------|
| `shard`          | int        | [**Required**] Shard for machine |
| `ip`             | string     | [**Required**] Ip of machine |
| `user`           | string     | [**Required**] User running the harmony process |
| `db_directory`   | string     | [**Required**] The directory of all harmony_db_<shard> directories. |

*Note that the snapshot script only accepts 1 machine per shard and requires that beacon chain machine be specified.*

### `rsync`
> Specify all things related to rclone. 

| Key                     | Value-type | Value-description|
| :----------------------:|:----------:| :----------------|
| `config_path_on_host`   | string     | [**Required**] Specify path to rclone config file on the host machine |
| `config_path_on_client` | string     | [**Required**] Specify path of where rclone config file will be temporarily saved on client machine |
| `snapshot_bin`          | string     | [**Required**] Specify rclone bin when doing bucket sync. I.e: `"testnet:pub.harmony.one/testnet"` |

### `condition`
> Specify all things related to condition checks before, during, and after the snapshot.

| Key                            | Value-type | Value-description|
| :-----------------------------:|:----------:| :----------------|
| `force`                        | boolean    | [**Required**] Bypass condition checks before and during snapshot |
| `max_seconds_since_last_block` | int        | [**Required**] Check for last block minted before and after snapshot |
| `role`                         | string     | [**Required**] Role for *ALL* configured nodes. (Validator/ExplorerNode) |
| `network`                      | string     | [**Required**] Network for *ALL* configured nodes. |
| `is_leader`                    | string     | [**Required**] Is leader status for *ALL* configured nodes |
| `is_archival`                  | string     | [**Required**] Archival status for *ALL* configured nodes |
| `is_snapdb`                    | string     | [**Required**] is a snapDB for *ALL* configured nodes |

### `pager_duty`
> Specify all things related to PagerDuty

| Key                            | Value-type | Value-description|
| :-----------------------------:|:----------:| :----------------|
| `ignore`                       | boolean    | [**Required**] Bypass/disable pager-duty notification |
| `service_key_v1`               | string     | [**Required**] Service key for the PagerDuty, null if ignored |


## Future usage
This script was designed to be imported from other scripts as a library. 
If you do so, make sure to look at the main execution to get an idea of how to use the script as a library.