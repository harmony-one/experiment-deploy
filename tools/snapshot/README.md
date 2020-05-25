# Network Snapshot 
`snapshot.py` is an orchestrator script to snapshot the network using a given config. 
Ideally, the script would be called every hour (or whatever desired interval) to ensure minimal 
rollback should the network suffer a network wide corruption of the DBs.

## Install
This script will require **python 3.6** or higher. 
Dependencies can be installed with the following command while in this directory:
```bash
python3 -m pip install -r requirements.txt
```

## Running Snapshot
1) Define your config JSON file. You can reference the example config file (`config.json`).
2) Run the snapshot script using the following command: 
```bash
chmod +x ./snapshot.py
./snapshot.py --config ./config.json
```
3) You can debug the script or check its progress by inspecting the log file called `snapshot.log` in the same directory as `snapshot.py`.
> It is recommended to set up a cronjob to call this script evey set interval. For example, to run the script every
> hour, execute the following command (assuming you are in this directory) to setup the cronjob:
> ```bash
> echo "0 * * * * $(pwd)/snapshot.py --config $(pwd)/config.json" > cronjob && crontab cronjob && crontab -l
> ```

## Future usage
This script was designed to be imported from other scripts as a library. 
If you do so, make sure to look at the main execution to get an idea of how to use the script as a library.