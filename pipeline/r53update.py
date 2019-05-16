import argparse
import ipaddress
import logging
from pprint import pprint
import sys
import time
import uuid

import boto3

logger = logging.getLogger(__name__)


def list_hosted_zones(client):
    """List hosted zones in Route 53.
    
    :param client: the Route 53 client.
    :return: zone objects.
    :rtype: generator
    """
    kwargs = dict()
    while True:
        resp = client.list_hosted_zones(**kwargs)
        yield from resp['HostedZones']
        if not resp['IsTruncated']:
            break
        kwargs.update(Marker=resp['NextMarker'])


def get_rrsets(client, zone_id, name, rrtype=None):
    """Get resource record sets.

    :param client: the Route 53 client.
    :param zone_id: the hosted zone ID.
    :type zone_id: `str`
    :param name: the name to query.
    :type name: `str`
    :param rrtype: the resource record type (default: all rrtypes).
    :return: resource record sets.
    """
    kwargs = dict(HostedZoneId=zone_id, StartRecordName=name)
    if rrtype is not None:
        kwargs.update(StartRecordType=rrtype)
    while True:
        resp = client.list_resource_record_sets(**kwargs)
        for rrset in resp['ResourceRecordSets']:
            if rrset['Name'] != name:
                return
            if rrtype is not None and rrset['Type'] != rrtype:
                return
            yield rrset
        if not resp['IsTruncated']:
            return
        for arg_name in ('Name', 'Type', 'Identifier'):
            try:
                arg_value = resp[f'NextRecord{arg_name}']
            except KeyError:
                kwargs.pop(f'StartRecord{arg_name}', None)
            else:
                kwargs[f'StartRecord{arg_name}'] = arg_value


DEFAULT_SHARD_FORMAT = 's{shard}'
DEFAULT_LEADER_FORMAT = 'l{shard}'
DEFAULT_ZONE_FORMAT = '{network}.hmny.io.'


def _find_parent(zones, name):
    labels = name.split('.')
    for idx in range(len(labels)):
        subzone_name = '.'.join(labels[:idx])
        parent = '.'.join(labels[idx:])
        try:
            return zones[parent], subzone_name
        except KeyError:
            pass
    return None, None


def _normalize_fqdn(s):
    if not s.endswith(s):
        s += '.'
    return s


def _create_subzone(client, zone_name, parent_zone_id):
    ref = uuid.uuid4()
    logger.debug(f"creating zone {zone_name!r}")
    resp = client.create_hosted_zone(Name=zone_name, CallerReference=str(ref))
    zone = resp['HostedZone']
    nameservers = resp['DelegationSet']['NameServers']
    logger.debug(f"created zone {zone!r}")
    logger.debug(f"adding nameservers {nameservers!r} to parent zone")
    resp = client.change_resource_record_sets(
            HostedZoneId=parent_zone_id,
            ChangeBatch={'Changes': [{'Action': 'CREATE', 'ResourceRecordSet': {
                'Name': zone['Name'],
                'Type': 'NS',
                'TTL': 172800,
                'ResourceRecords': [{'Value': _normalize_fqdn(ns)}
                                    for ns in nameservers],
            }}]},
    )
    logger.debug(f"nameservers added, response {resp!r}")
    return zone


def main():
    logging.basicConfig()
    parser = argparse.ArgumentParser()
    parser.add_argument('--debug', action='store_const', const=True,
                        help="enable debug logging")
    parser.add_argument('--confirm-remove', action='store_const', const=True,
                        help="remove nodes")
    parser.add_argument('--wait', action='store_const', const=True,
                        help="""wait for the request to finish
                                (may take some time)""")
    parser.add_argument('--zone-format', metavar='F',
                        help=f"""zone name format
                                 (default: {DEFAULT_ZONE_FORMAT})""")
    parser.add_argument('--create-zone', action='store_const', const=True,
                        help="""if the zone is not found, create in the
                                closest ancestor zone""")
    parser.add_argument('--shard-format', metavar='F',
                        help=f"""shard DNS name format in zone
                                 (default: {DEFAULT_SHARD_FORMAT})""")
    parser.add_argument('--leader-format', metavar='F',
                        help=f"""leader DNS name format in zone
                                 (default: {DEFAULT_LEADER_FORMAT})""")
    parser.add_argument('--aws-profile', metavar='NAME',
                        help=f"""AWS config/credential profile name""")
    parser.add_argument('network', metavar='NETWORK',
                        help="network ID (example: t0)")
    parser.add_argument('shard', type=int, metavar='SHARD',
                        help="shard ID (example: 0)")
    parser.add_argument('nodes', type=ipaddress.ip_address, nargs='*',
                        metavar='NODE', help="node IP (first is leader)")
    parser.set_defaults(zone_format=DEFAULT_ZONE_FORMAT,
                        shard_format=DEFAULT_SHARD_FORMAT,
                        leader_format=DEFAULT_LEADER_FORMAT)
    args = parser.parse_args()

    # retrieve/sanitize cmdline args
    format_args = dict(
            network=args.network,
            shard=args.shard,
    )
    def fmt(s):
        r = s.format(**format_args)
        logger.debug(f"formatted {s!r} -> {r!r}")
        return r
    zone_name = fmt(args.zone_format)
    if not zone_name.endswith('.'):
        zone_name += '.'
    node_ips = args.nodes
    if args.debug:
        logger.setLevel(logging.DEBUG)
    else:
        logger.setLevel(logging.INFO)

    if node_ips:
        if args.confirm_remove:
            parser.error("--confirm-remove cannot be given with nodes")
    else:
        if not args.confirm_remove:
            parser.error("no node IPs given, will only remove existing ones; "
                         "add --confirm-remove to confirm this")

    logger.debug("creating Route 53 client")
    session_kwargs = dict()
    if args.aws_profile:
        session_kwargs.update(profile_name=args.aws_profile)
    session = boto3.Session(**session_kwargs)
    r53 = session.client('route53')

    logger.debug(f"retrieving zone ID for zone {zone_name!r}")
    zones = {zone['Name']: zone for zone in list_hosted_zones(r53)}
    parent_zone, subzone_name = _find_parent(zones, zone_name)
    logger.debug(f"parent {parent_zone['Name']!r}, subzone {subzone_name!r}")
    if subzone_name is None:
        # not found, not even potential parent
        logger.error(f"zone {zone_name!r} is not found")
        return 1
    elif subzone_name == '':
        # exact match
        zone = parent_zone
    elif not args.create_zone:
        logger.error(f"zone {zone_name!r} is not found; "
                     f"add --create-zone to create in {parent_zone['Name']!r}")
        return 1
    else:
        logger.info(f"zone {zone_name!r} is not found, "
                    f"creating in {parent_zone['Name']!r}")
        zone = _create_subzone(r53, zone_name, parent_zone['Id'])
    zone_id = zone['Id']

    batch = []
    rrtype_by_version = {4: 'A', 6: 'AAAA'}

    shard_label = fmt(args.shard_format)
    leader_label = fmt(args.leader_format)

    def schedule_removal(label):
        for rrtype in rrtype_by_version.values():
            name = f'{label}.{zone_name}'
            for old_rrset in get_rrsets(r53, zone_id, name, rrtype):
                logger.info(f"scheduling removal of {name!r} {rrtype} RRs")
                batch.append({
                    'Action': 'DELETE',
                    'ResourceRecordSet': old_rrset,
                })

    schedule_removal(shard_label)
    schedule_removal(leader_label)

    # classify by rrtype
    nodes = {}
    for node_ip in node_ips:
        nodes.setdefault(node_ip.version, []).append(node_ip)

    for version, addrs in nodes.items():
        logger.debug(f"adding {len(addrs)} IPv{version} nodes")
        assert addrs
        batch.append({
            'Action': 'CREATE',
            'ResourceRecordSet': {
                'Name': f'{shard_label}.{zone_name}',
                'Type': rrtype_by_version[version],
                'TTL': 60,
                'ResourceRecords': [{'Value': str(addr)} for addr in addrs],
            },
        })

    if node_ips:
        leader = node_ips[0]
        batch.append({
            'Action': 'CREATE',
            'ResourceRecordSet': {
                'Name': f'{leader_label}.{zone_name}',
                'Type': rrtype_by_version[leader.version],
                'TTL': 60,
                'ResourceRecords': [{'Value': str(leader)}],
            },
        })

    if not batch:
        logger.info(f"nothing to do; exiting")
        return

    logger.debug(f"requesting change batch={batch!r}")
    resp = r53.change_resource_record_sets(
            HostedZoneId=zone_id, ChangeBatch={'Changes': batch})
    change_id = resp['ChangeInfo']['Id']
    logger.info(f"request submitted, id={change_id!r}")

    if not args.wait:
        return
    logger.info(f"waiting for the request to finish (may take some time)")
    backoff = 1.0
    backoff_rate = 1.2
    max_backoff = 10.0
    while True:
        logger.debug(f"checking request status")
        resp = r53.get_change(Id=change_id)
        status = resp['ChangeInfo']['Status']
        logger.debug(f"request status={status!r}")
        if status != 'PENDING':
            break
        time.sleep(backoff)
        backoff = min(backoff * backoff_rate, max_backoff)
    if status != 'INSYNC':
        logger.error(f"request failed, status={status!r}")
        return 1
    logger.info(f"request succeeded")


if __name__ == '__main__':
    sys.exit(main() or 0)
